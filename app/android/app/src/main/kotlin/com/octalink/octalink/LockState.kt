package com.octalink.octalink

import android.content.Context
import android.content.SharedPreferences

/** Penyimpanan lokal: ID device + policy terakhir dari Firestore (supaya jalan offline). */
object Prefs {
    private const val FILE = "octalink"
    private fun sp(c: Context): SharedPreferences = c.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun deviceId(c: Context): String? = sp(c).getString("deviceId", null)
    fun setDeviceId(c: Context, id: String?) = sp(c).edit().putString("deviceId", id).apply()

    fun policyJson(c: Context): String? = sp(c).getString("policy", null)
    fun setPolicyJson(c: Context, json: String?) = sp(c).edit().putString("policy", json).apply()

    /** Jeda tamper-guard sementara saat orang tua sedang mengatur izin dari layar anak. */
    fun guardPausedUntil(c: Context): Long = sp(c).getLong("guardPausedUntil", 0)
    fun pauseGuard(c: Context, ms: Long) =
        sp(c).edit().putLong("guardPausedUntil", System.currentTimeMillis() + ms).apply()

    fun clear(c: Context) = sp(c).edit().clear().apply()
}

/** Status kunci terkini + listener (dipakai GuardService & EnforcerService di proses yang sama). */
object LockState {
    fun interface Listener {
        fun onDecision(d: Decision, changed: Boolean)
    }

    @Volatile var decision: Decision = Decision(false, "Belum dipasangkan", null)
        private set
    @Volatile var policy: Policy = Policy()
        private set

    private val listeners = mutableSetOf<Listener>()

    @Synchronized fun addListener(l: Listener) { listeners.add(l) }
    @Synchronized fun removeListener(l: Listener) { listeners.remove(l) }

    /** Evaluasi ulang dari policy tersimpan. Murah, aman dipanggil sering. */
    fun refresh(c: Context) {
        val paired = Prefs.deviceId(c) != null
        val p = if (paired) PolicyEngine.parse(Prefs.policyJson(c)) else Policy()
        val d = if (paired) PolicyEngine.evaluate(p) else Decision(false, "Belum dipasangkan", null)
        val changed = d.locked != decision.locked || d.reason != decision.reason || d.nextChange != decision.nextChange
        policy = p
        decision = d
        val snapshot = synchronized(this) { listeners.toList() }
        snapshot.forEach { it.onDecision(d, changed) }
    }
}
