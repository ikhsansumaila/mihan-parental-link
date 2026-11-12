package com.mihan.parentallink

import android.content.Context
import android.content.SharedPreferences
import android.os.SystemClock
import android.provider.Settings

/** Penyimpanan lokal: ID device + policy terakhir dari Firestore (supaya jalan offline). */
object Prefs {
    private const val FILE = "mihan_parental_link"
    private fun sp(c: Context): SharedPreferences = c.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun deviceId(c: Context): String? = sp(c).getString("deviceId", null)
    fun setDeviceId(c: Context, id: String?) = sp(c).edit().putString("deviceId", id).apply()

    fun policyJson(c: Context): String? = sp(c).getString("policy", null)
    fun setPolicyJson(c: Context, json: String?) = sp(c).edit().putString("policy", json).apply()

    /** Jeda tamper-guard sementara saat orang tua sedang mengatur izin dari layar anak. */
    fun guardPausedUntil(c: Context): Long = sp(c).getLong("guardPausedUntil", 0)
    fun pauseGuard(c: Context, ms: Long) =
        sp(c).edit().putLong("guardPausedUntil", System.currentTimeMillis() + ms).apply()

    /** Waktu kirim pesan terakhir ke orang tua (batas spam). */
    fun lastMessageAt(c: Context): Long = sp(c).getLong("lastMessageAt", 0)
    fun setLastMessageAt(c: Context, t: Long) = sp(c).edit().putLong("lastMessageAt", t).apply()

    // ---- kode buka darurat (lihat UnlockCode)
    fun unlockSecret(c: Context): String? = sp(c).getString("unlockSecret", null)
    fun setUnlockSecret(c: Context, v: String?) = sp(c).edit().putString("unlockSecret", v).apply()
    fun codeFails(c: Context): Int = sp(c).getInt("codeFails", 0)
    fun setCodeFails(c: Context, v: Int) = sp(c).edit().putInt("codeFails", v).apply()
    fun codeBlockedUntil(c: Context): Long = sp(c).getLong("codeBlockedUntil", 0)
    fun setCodeBlockedUntil(c: Context, v: Long) = sp(c).edit().putLong("codeBlockedUntil", v).apply()
    fun usedCodes(c: Context): List<String> = sp(c).getString("usedCodes", "")!!.split(',').filter { it.isNotEmpty() }
    fun addUsedCode(c: Context, k: String) =
        sp(c).edit().putString("usedCodes", (usedCodes(c) + k).takeLast(20).joinToString(",")).apply()

    /** Buka lokal dari kode. Disimpan juga versi elapsedRealtime supaya mundurin jam tidak memperpanjang. */
    fun setLocalUnlock(c: Context, at: Long, until: Long) {
        val dur = until - at
        sp(c).edit()
            .putLong("localUnlockAt", at)
            .putLong("localUnlockUntil", until)
            .putLong("localUnlockElapsedUntil", SystemClock.elapsedRealtime() + dur)
            .putInt("localUnlockBoot", bootCount(c))
            .apply()
    }
    fun clearLocalUnlock(c: Context) =
        sp(c).edit().remove("localUnlockAt").remove("localUnlockUntil").remove("localUnlockElapsedUntil").apply()
    fun localUnlockAt(c: Context): Long = sp(c).getLong("localUnlockAt", 0)

    /** Batas buka lokal yang masih berlaku, atau null. */
    fun activeLocalUnlockUntil(c: Context, now: Long = System.currentTimeMillis()): Long? {
        val until = sp(c).getLong("localUnlockUntil", 0)
        if (until == 0L || now >= until) return null
        // Boot yang sama → pakai jam monoton (tidak bisa diubah pengguna).
        if (sp(c).getInt("localUnlockBoot", -1) == bootCount(c)) {
            val left = sp(c).getLong("localUnlockElapsedUntil", 0) - SystemClock.elapsedRealtime()
            if (left <= 0) return null
            return minOf(until, now + left)
        }
        return until
    }

    private fun bootCount(c: Context): Int =
        try { Settings.Global.getInt(c.contentResolver, Settings.Global.BOOT_COUNT) } catch (_: Exception) { -1 }

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
        var d = if (paired) PolicyEngine.evaluate(p) else Decision(false, "Belum dipasangkan", null)
        if (paired && d.locked) {
            Prefs.activeLocalUnlockUntil(c)?.let { d = Decision(false, "Dibuka dengan kode orang tua", it) }
        }
        val changed = d.locked != decision.locked || d.reason != decision.reason || d.nextChange != decision.nextChange
        policy = p
        decision = d
        val snapshot = synchronized(this) { listeners.toList() }
        snapshot.forEach { it.onDecision(d, changed) }
    }
}
