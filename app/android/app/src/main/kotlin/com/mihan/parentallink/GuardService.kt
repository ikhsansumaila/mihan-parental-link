package com.mihan.parentallink

import android.accessibilityservice.AccessibilityService
import android.app.KeyguardManager
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
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
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
        @Volatile private var instance: GuardService? = null
        /**
         * Selama MessageActivity tampil, overlay disembunyikan supaya keyboard bisa dipakai.
         * Pakai batas waktu (bukan boolean) supaya overlay pasti kembali walau activity gagal dibuka.
         */
        @Volatile private var composingUntil = 0L

        fun setComposing(v: Boolean) = setComposingFor(if (v) 4 * 60_000L else 0L)

        private fun setComposingFor(ms: Long) {
            composingUntil = if (ms > 0) System.currentTimeMillis() + ms else 0L
            instance?.let { g ->
                g.handler.post { g.updateOverlay() }
                if (ms > 0) g.handler.postDelayed({ g.updateOverlay() }, ms + 100)
            }
        }
        private val composing get() = System.currentTimeMillis() < composingUntil

        /** Mode "Pilih Wi-Fi": halaman Wi-Fi di Settings boleh tampil walau terkunci. */
        private const val WIFI_MAX_MS = 3 * 60_000L
        private const val WIFI_GRACE_MS = 5_000L
        /** Nama activity Settings yang dianggap halaman Wi-Fi / koneksi. */
        private val WIFI_ACTIVITY = Regex("(?i)wifi|wlan|panel|internet|network|hotspot|tether|connection")

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
    private var wifiUntil = 0L      // batas mode Wi-Fi
    private var wifiGraceUntil = 0L // jeda awal sebelum event Settings pertama datang
    private var wifiPageOk = false  // activity Settings yang terakhir tampil adalah halaman Wi-Fi
    private var lastShadeDismiss = 0L
    /** Keyboard bukan "aplikasi di depan" — supaya bisa mengetik password Wi-Fi / nomor telepon. */
    private val imePkgs by lazy {
        try {
            getSystemService(InputMethodManager::class.java).enabledInputMethodList.map { it.packageName }.toSet()
        } catch (_: Exception) { emptySet() }
    }
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
        instance = this
        LockState.addListener(this)
        EnforcerService.start(this) // accessibility service boleh start FGS dari background
        LockState.refresh(this)
    }

    override fun onDestroy() {
        running = false
        if (instance === this) instance = null
        LockState.removeListener(this)
        hideOverlay()
        super.onDestroy()
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(e: AccessibilityEvent?) {
        val pkg = e?.packageName?.toString() ?: return
        if (Prefs.deviceId(this) == null) return

        if (e.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            if (pkg == "com.android.systemui") dismissShadeIfLocked()
            if (pkg !in IGNORED && pkg !in imePkgs && pkg != packageName) {
                foregroundPkg = pkg
                trackWifiMode(pkg, e.className?.toString())
                updateOverlay()
            }
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

    // ------------------------------------------------------------------ mode Wi-Fi

    private fun startWifiMode() {
        val now = System.currentTimeMillis()
        wifiUntil = now + WIFI_MAX_MS
        wifiGraceUntil = now + WIFI_GRACE_MS
        wifiPageOk = true
        val panel = Intent(Settings.Panel.ACTION_WIFI)
        val intent = if (Build.VERSION.SDK_INT >= 29 && panel.resolveActivity(packageManager) != null) panel
            else Intent(Settings.ACTION_WIFI_SETTINGS)
        try {
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: Exception) {
            android.util.Log.w("OctaGuard", "wifi settings failed", e)
            wifiUntil = 0
        }
        updateOverlay()
        handler.postDelayed({ updateOverlay() }, WIFI_GRACE_MS + 100)
        handler.postDelayed({ updateOverlay() }, WIFI_MAX_MS + 100)
    }

    /**
     * Selama mode Wi-Fi: hanya activity Settings yang namanya seperti halaman Wi-Fi yang diizinkan.
     * Dialog (mis. isian password) bukan activity, jadi tidak mengubah status.
     * Pindah ke aplikasi lain → mode Wi-Fi selesai.
     */
    private fun trackWifiMode(pkg: String, cls: String?) {
        if (wifiUntil == 0L) return
        if (pkg !in SETTINGS_PKGS) {
            wifiUntil = 0
            wifiGraceUntil = 0
            return
        }
        if (cls != null && isActivity(pkg, cls)) wifiPageOk = WIFI_ACTIVITY.containsMatchIn(cls)
    }

    private fun isActivity(pkg: String, cls: String): Boolean = try {
        packageManager.getActivityInfo(ComponentName(pkg, cls), 0)
        true
    } catch (_: Exception) { false }

    private fun wifiAllowed(): Boolean {
        val now = System.currentTimeMillis()
        if (now >= wifiUntil) return false
        if (now < wifiGraceUntil) return true
        return foregroundPkg in SETTINGS_PKGS && wifiPageOk
    }

    // ------------------------------------------------------------------ panel notifikasi

    /** Saat terkunci, tutup panel notifikasi / quick settings (Android 12+). */
    private fun dismissShadeIfLocked() {
        if (Build.VERSION.SDK_INT < 31) return
        if (!LockState.decision.locked || composing || wifiAllowed()) return
        // Jangan ganggu layar kunci bawaan HP (PIN / pola).
        if (getSystemService(KeyguardManager::class.java)?.isKeyguardLocked == true) return
        val now = System.currentTimeMillis()
        if (now - lastShadeDismiss < 400) return
        lastShadeDismiss = now
        performGlobalAction(GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE)
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
        val show = d.locked && Prefs.deviceId(this) != null && foregroundPkg !in allowed && !composing && !wifiAllowed()
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

        // Tombol aksi dan keypad kode saling bergantian tampil.
        val actions = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER }
        val keypad = buildKeypad(onClose = {
            it.visibility = View.GONE
            actions.visibility = View.VISIBLE
        })
        keypad.visibility = View.GONE
        root.addView(actions)
        root.addView(keypad)

        actions.addView(Button(this).apply {
            this.text = "💬  Kirim pesan ke orang tua"
            setOnClickListener {
                // Beri 5 dtk untuk membuka activity; onResume-nya memperpanjang.
                setComposingFor(5_000)
                MessageActivity.open(this@GuardService)
            }
        }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(40) })
        actions.addView(Button(this).apply {
            this.text = "📶  Pilih Wi-Fi"
            setOnClickListener { startWifiMode() }
        }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(12) })
        actions.addView(Button(this).apply {
            this.text = "🔑  Masukkan kode orang tua"
            setOnClickListener {
                actions.visibility = View.GONE
                keypad.visibility = View.VISIBLE
            }
        }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(12) })
        actions.addView(Button(this).apply {
            this.text = "📞  Panggilan darurat / telepon"
            setOnClickListener {
                foregroundPkg = allowed.firstOrNull()
                hideOverlay()
                startActivity(Intent(Intent.ACTION_DIAL).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(12) })

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_FULLSCREEN,
            PixelFormat.TRANSLUCENT,
        )
        // ScrollView: keypad tetap terjangkau di layar pendek.
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(Color.parseColor("#F2101820"))
            addView(root, android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.MATCH_PARENT)
        }
        try {
            wm.addView(scroll, lp)
            overlay = scroll
        } catch (e: Exception) {
            android.util.Log.e("OctaGuard", "overlay failed", e)
        }
    }

    /**
     * Keypad angka di dalam overlay (tanpa keyboard sistem, jadi tidak perlu menyembunyikan overlay).
     * Kode diverifikasi offline oleh [UnlockCode].
     */
    private fun buildKeypad(onClose: (View) -> Unit): LinearLayout {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(0, dp(24), 0, 0)
        }
        val entered = StringBuilder()
        val display = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 32f)
            typeface = Typeface.MONOSPACE
            letterSpacing = 0.3f
            gravity = Gravity.CENTER
        }
        val info = TextView(this).apply {
            setTextColor(Color.parseColor("#CCFFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            gravity = Gravity.CENTER
            text = "Minta kode 6 digit ke orang tua\n(dashboard → perangkat → Kode buka darurat)"
        }
        fun render() { display.text = (entered.toString() + "______").take(6).chunked(3).joinToString(" ") }
        render()
        box.addView(display)
        box.addView(info, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { bottomMargin = dp(12) })

        fun submit() {
            when (val r = UnlockCode.tryUnlock(this, entered.toString())) {
                is UnlockCode.Result.Unlocked -> {
                    info.setTextColor(Color.parseColor("#8FE3A3"))
                    info.text = "Terbuka sampai ${SimpleDateFormat("HH:mm", Locale("id")).format(Date(r.until))}"
                    // LockState.refresh di tryUnlock sudah memicu onDecision → overlay hilang.
                }
                is UnlockCode.Result.Error -> {
                    info.setTextColor(Color.parseColor("#FFB4AB"))
                    info.text = r.message
                }
            }
            entered.clear()
            render()
        }

        val keys = listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf("⌫", "0", "OK"))
        for (row in keys) {
            val r = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER }
            for (k in row) {
                r.addView(Button(this).apply {
                    text = k
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
                    setOnClickListener {
                        when (k) {
                            "⌫" -> if (entered.isNotEmpty()) entered.deleteCharAt(entered.length - 1)
                            "OK" -> if (entered.length == 6) { submit(); return@setOnClickListener }
                            else -> if (entered.length < 6) entered.append(k)
                        }
                        render()
                        if (entered.length == 6 && k != "OK" && k != "⌫") submit()
                    }
                }, LinearLayout.LayoutParams(dp(76), dp(60)).apply { setMargins(dp(4), dp(4), dp(4), dp(4)) })
            }
            box.addView(r)
        }
        box.addView(Button(this).apply {
            text = "Batal"
            setOnClickListener {
                entered.clear()
                render()
                onClose(box)
            }
        }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(8) })
        return box
    }

    private fun hideOverlay() {
        overlay?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        overlay = null
        overlayText = null
        if (!LockState.decision.locked) releaseAudioFocus()
    }
}
