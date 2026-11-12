package com.mihan.parentallink

import android.accessibilityservice.AccessibilityService
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.telecom.TelecomManager
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Accessibility service:
 * - Menampilkan overlay layar kunci penuh saat jadwal mengunci (TYPE_ACCESSIBILITY_OVERLAY,
 *   tidak perlu izin "tampil di atas aplikasi lain").
 * - Mengizinkan aplikasi telepon/darurat tetap bisa dipakai.
 * - Tamper guard: menutup halaman Settings yang menampilkan Mihan Parental Link (mencegah mematikan
 *   layanan / admin / uninstall) bila diaktifkan orang tua.
 */
class GuardService : AccessibilityService(), LockState.Listener {
    companion object {
        @Volatile var running = false
            private set

        fun isEnabled(c: Context): Boolean {
            if (running) return true
            val enabled = Settings.Secure.getString(c.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
            val me = ComponentName(c, GuardService::class.java).flattenToString()
            return enabled.split(':').any { it.equals(me, ignoreCase = true) }
        }

        private val SETTINGS_PKGS = setOf(
            "com.android.settings", "com.google.android.packageinstaller", "com.android.packageinstaller",
            "com.miui.securitycenter", "com.samsung.android.settings", "com.coloros.safecenter",
        )
        private val ALWAYS_ALLOWED = setOf(
            "com.android.phone", "com.android.server.telecom", "com.android.dialer", "com.google.android.dialer",
            "com.samsung.android.dialer", "com.android.emergency", "com.google.android.apps.safetyhub",
        )
        /** Paket yang event-nya tidak mengubah "aplikasi di depan". */
        private val IGNORED = setOf("com.android.systemui")
    }

    private val handler = Handler(Looper.getMainLooper())
    private var overlay: View? = null
    private var overlayText: TextView? = null
    private var foregroundPkg: String? = null
    private var lastRefresh = 0L
    private var lastTamperCheck = 0L
    private var audioFocus: AudioFocusRequest? = null
    private val wm by lazy { getSystemService(WindowManager::class.java) }
    private val allowed by lazy {
        val dialer = try { getSystemService(TelecomManager::class.java)?.defaultDialerPackage } catch (_: Exception) { null }
        ALWAYS_ALLOWED + listOfNotNull(dialer)
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        running = true
        LockState.addListener(this)
        EnforcerService.start(this) // accessibility service boleh start FGS dari background
        LockState.refresh(this)
    }

    override fun onDestroy() {
        running = false
        LockState.removeListener(this)
        hideOverlay()
        super.onDestroy()
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(e: AccessibilityEvent?) {
        val pkg = e?.packageName?.toString() ?: return
        if (Prefs.deviceId(this) == null) return

        if (e.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && pkg !in IGNORED && pkg != packageName) {
            foregroundPkg = pkg
            updateOverlay()
        }

        val now = System.currentTimeMillis()
        if (now - lastRefresh > 5_000) {
            lastRefresh = now
            LockState.refresh(this)
        }
        if (pkg in SETTINGS_PKGS && now - lastTamperCheck > 700) {
            lastTamperCheck = now
            checkTamper(e)
        }
    }

    // ------------------------------------------------------------------ tamper guard

    private fun checkTamper(e: AccessibilityEvent) {
        if (!LockState.policy.tamperGuard) return
        if (System.currentTimeMillis() < Prefs.guardPausedUntil(this)) return
        // Hanya jaga setelah setup selesai (admin aktif), supaya orang tua bisa mengaktifkan izin.
        val dpm = getSystemService(DevicePolicyManager::class.java)
        if (!dpm.isAdminActive(ComponentName(this, AdminReceiver::class.java))) return
        val cls = e.className?.toString() ?: ""
        if (cls.contains("RequestIgnoreBatteryOptimizations")) return

        val root = rootInActiveWindow ?: return
        val label = getString(R.string.app_name)
        val mentionsUs = try {
            root.findAccessibilityNodeInfosByText(label).isNotEmpty()
        } catch (_: Exception) { false }
        if (mentionsUs) {
            performGlobalAction(GLOBAL_ACTION_BACK)
            handler.postDelayed({ performGlobalAction(GLOBAL_ACTION_HOME) }, 150)
        }
    }

    // ------------------------------------------------------------------ lock overlay

    override fun onDecision(d: Decision, changed: Boolean) {
        handler.post {
            if (changed && d.locked) onLockStarted()
            updateOverlay()
        }
    }

    private fun onLockStarted() {
        // Tutup aplikasi yang sedang dibuka & hentikan audio/video.
        performGlobalAction(GLOBAL_ACTION_HOME)
        grabAudioFocus()
        try {
            val dpm = getSystemService(DevicePolicyManager::class.java)
            if (dpm.isAdminActive(ComponentName(this, AdminReceiver::class.java))) dpm.lockNow()
        } catch (_: Exception) {}
    }

    private fun grabAudioFocus() {
        val am = getSystemService(AudioManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).build())
                .setOnAudioFocusChangeListener { }
                .build()
            audioFocus = req
            am.requestAudioFocus(req)
        }
    }

    private fun releaseAudioFocus() {
        val am = getSystemService(AudioManager::class.java) ?: return
        audioFocus?.let { if (Build.VERSION.SDK_INT >= 26) am.abandonAudioFocusRequest(it) }
        audioFocus = null
    }

    private fun updateOverlay() {
        val d = LockState.decision
        val show = d.locked && Prefs.deviceId(this) != null && foregroundPkg !in allowed
        if (show) showOverlay(d) else hideOverlay()
    }

    private fun dp(v: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

    private fun showOverlay(d: Decision) {
        val text = buildString {
            append(d.reason)
            d.nextChange?.let {
                append("\n\nBisa dipakai lagi ")
                append(SimpleDateFormat("EEEE, HH:mm", Locale("id")).format(Date(it)))
            }
        }
        if (overlay != null) {
            overlayText?.text = text
            return
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#F2101820"))
            setPadding(dp(32), dp(32), dp(32), dp(32))
            isClickable = true
            isFocusable = true
        }
        root.addView(TextView(this).apply {
            this.text = "🔒"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 64f)
            gravity = Gravity.CENTER
        })
        root.addView(TextView(this).apply {
            this.text = "Waktu pakai HP habis"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, dp(16), 0, dp(8))
        })
        overlayText = TextView(this).apply {
            this.text = text
            setTextColor(Color.parseColor("#CCFFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            gravity = Gravity.CENTER
        }
        root.addView(overlayText)
        root.addView(Button(this).apply {
            this.text = "📞  Panggilan darurat / telepon"
            setOnClickListener {
                foregroundPkg = allowed.firstOrNull()
                hideOverlay()
                startActivity(Intent(Intent.ACTION_DIAL).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(40) })

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_FULLSCREEN,
            PixelFormat.TRANSLUCENT,
        )
        try {
            wm.addView(root, lp)
            overlay = root
        } catch (e: Exception) {
            android.util.Log.e("OctaGuard", "overlay failed", e)
        }
    }

    private fun hideOverlay() {
        overlay?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        overlay = null
        overlayText = null
        if (!LockState.decision.locked) releaseAudioFocus()
    }
}
