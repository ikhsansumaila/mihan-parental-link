package com.mihan.parentallink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Foreground service di HP anak:
 * - mendengarkan dokumen devices/{id} di Firestore → simpan policy lokal
 * - evaluasi jadwal tiap 15 detik (offline-capable)
 * - kirim heartbeat/status ke Firestore tiap 60 detik atau saat status berubah
 */
class EnforcerService : Service(), LockState.Listener {
    companion object {
        private const val TAG = "OctaEnforcer"
        private const val CHANNEL = "mihan_status"
        private const val NOTIF_ID = 42
        private const val TICK_MS = 15_000L
        private const val HEARTBEAT_MS = 60_000L

        fun start(c: Context) {
            if (Prefs.deviceId(c) == null) return
            val i = Intent(c, EnforcerService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i) else c.startService(i)
            } catch (e: Exception) {
                // Android 12+ bisa menolak start dari background; GuardService akan mencoba lagi.
                Log.w(TAG, "start failed: $e")
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var registration: ListenerRegistration? = null
    private var listeningId: String? = null
    private var lastHeartbeat = 0L
    private var lastPolicyJson: String? = null

    private val tick = object : Runnable {
        override fun run() {
            LockState.refresh(this@EnforcerService)
            if (System.currentTimeMillis() - lastHeartbeat > HEARTBEAT_MS) heartbeat()
            handler.postDelayed(this, TICK_MS)
        }
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) = LockState.refresh(c)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        val n = buildNotification(LockState.decision)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, n)
        }
        LockState.addListener(this)
        ContextCompat.registerReceiver(this, screenReceiver, IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
        }, ContextCompat.RECEIVER_NOT_EXPORTED)
        handler.post(tick)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = Prefs.deviceId(this)
        if (id == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        listen(id)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        registration?.remove()
        LockState.removeListener(this)
        try { unregisterReceiver(screenReceiver) } catch (_: Exception) {}
        super.onDestroy()
    }

    // ------------------------------------------------------------------ firestore

    private fun db(): FirebaseFirestore? = try {
        if (FirebaseApp.getApps(this).isEmpty()) FirebaseApp.initializeApp(this)
        FirebaseFirestore.getInstance()
    } catch (e: Exception) {
        Log.e(TAG, "Firebase init failed", e)
        null
    }

    private fun listen(id: String) {
        if (listeningId == id && registration != null) return
        registration?.remove()
        val db = db() ?: return
        if (FirebaseAuth.getInstance().currentUser == null) {
            Log.w(TAG, "Belum login; menunggu.")
            handler.postDelayed({ listen(id) }, 30_000)
            return
        }
        listeningId = id
        registration = db.collection("devices").document(id).addSnapshotListener { snap, err ->
            if (err != null) {
                Log.w(TAG, "listen error: $err")
                return@addSnapshotListener
            }
            if (snap == null) return@addSnapshotListener
            if (!snap.exists()) {
                // Dokumen dihapus orang tua (bukan karena cache kosong) → lepas perangkat.
                if (!snap.metadata.isFromCache) unpair()
                return@addSnapshotListener
            }
            @Suppress("UNCHECKED_CAST")
            val policy = snap.get("policy") as? Map<String, Any?>
            val json = policy?.let { JSONObject(it).toString() }
            if (json != lastPolicyJson) {
                lastPolicyJson = json
                Prefs.setPolicyJson(this, json)
                LockState.refresh(this)
                heartbeat()
            }
        }
    }

    private fun unpair() {
        Log.i(TAG, "Perangkat dilepas oleh orang tua.")
        Prefs.clear(this)
        LockState.refresh(this)
        try {
            val dpm = getSystemService(DevicePolicyManager::class.java)
            val admin = ComponentName(this, AdminReceiver::class.java)
            if (dpm.isAdminActive(admin)) dpm.removeActiveAdmin(admin)
        } catch (_: Exception) {}
        try { FirebaseAuth.getInstance().signOut() } catch (_: Exception) {}
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun heartbeat() {
        val id = Prefs.deviceId(this) ?: return
        val db = db() ?: return
        if (FirebaseAuth.getInstance().currentUser == null) return
        lastHeartbeat = System.currentTimeMillis()
        val d = LockState.decision
        val status = hashMapOf<String, Any?>(
            "locked" to d.locked,
            "reason" to d.reason,
            "nextChange" to d.nextChange,
            "accessibility" to GuardService.isEnabled(this),
            "admin" to isAdminActive(),
            "battery" to batteryLevel(),
            "ignoringBattery" to getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName),
            "tz" to TimeZone.getDefault().id,
            "deviceTime" to SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(Date()),
            "appVersion" to try { packageManager.getPackageInfo(packageName, 0).versionName } catch (_: Exception) { null },
        )
        db.collection("devices").document(id)
            .update(mapOf("status" to status, "lastSeen" to FieldValue.serverTimestamp()))
            .addOnFailureListener { Log.w(TAG, "heartbeat failed: $it") }
    }

    private fun isAdminActive() =
        getSystemService(DevicePolicyManager::class.java).isAdminActive(ComponentName(this, AdminReceiver::class.java))

    private fun batteryLevel(): Int? =
        getSystemService(BatteryManager::class.java)?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)

    // ------------------------------------------------------------------ state

    override fun onDecision(d: Decision, changed: Boolean) {
        if (!changed) return
        getSystemService(NotificationManager::class.java).notify(NOTIF_ID, buildNotification(d))
        heartbeat()
    }

    // ------------------------------------------------------------------ notification

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val ch = NotificationChannel(CHANNEL, "Status Mihan Parental Link", NotificationManager.IMPORTANCE_LOW)
        ch.setShowBadge(false)
        getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
    }

    private fun buildNotification(d: Decision): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        val next = d.nextChange?.let {
            " · ${if (d.locked) "terbuka" else "terkunci"} ${SimpleDateFormat("EEE HH:mm", Locale("id")).format(Date(it))}"
        } ?: ""
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setContentTitle(if (d.locked) "HP terkunci" else "Mihan Parental Link aktif")
            .setContentText(d.reason + next)
            .setOngoing(true)
            .setContentIntent(open)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
