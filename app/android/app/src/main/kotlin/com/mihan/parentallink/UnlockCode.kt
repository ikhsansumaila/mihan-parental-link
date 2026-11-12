package com.mihan.parentallink

import android.content.Context
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Kode buka darurat offline. Harus identik dengan lib/core/unlock_code.dart.
 * Kode = HMAC-SHA256(secret, "unlock:{step}:{durasi}") → 6 digit, step = 5 menit.
 */
object UnlockCode {
    const val STEP_MS = 5 * 60_000L
    val DURATIONS_MIN = longArrayOf(30, 60, 180, 1440)
    private const val ACCEPT_PAST = 2
    private const val ACCEPT_FUTURE = 1
    private const val MAX_FAILS = 5
    private const val BLOCK_MS = 5 * 60_000L

    fun code(secret: String, step: Long, idx: Int): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        val h = mac.doFinal("unlock:$step:$idx".toByteArray(Charsets.UTF_8))
        val o = h[h.size - 1].toInt() and 0x0f
        val bin = ((h[o].toInt() and 0x7f) shl 24) or
            ((h[o + 1].toInt() and 0xff) shl 16) or
            ((h[o + 2].toInt() and 0xff) shl 8) or
            (h[o + 3].toInt() and 0xff)
        return (bin % 1_000_000).toString().padStart(6, '0')
    }

    /** Cocokkan kode; kembalikan (step, indeks durasi) atau null. Murni, mudah dites. */
    fun match(secret: String, input: String, now: Long): Pair<Long, Int>? {
        val step = now / STEP_MS
        for (s in (step - ACCEPT_PAST)..(step + ACCEPT_FUTURE)) {
            for (i in DURATIONS_MIN.indices) {
                if (code(secret, s, i) == input) return s to i
            }
        }
        return null
    }

    sealed class Result {
        data class Unlocked(val until: Long, val minutes: Long) : Result()
        data class Error(val message: String) : Result()
    }

    /** Dipanggil dari keypad layar kunci. Membatasi percobaan & mencegah kode dipakai ulang. */
    fun tryUnlock(c: Context, input: String, now: Long = System.currentTimeMillis()): Result {
        val blocked = Prefs.codeBlockedUntil(c)
        if (now < blocked) {
            return Result.Error("Terlalu banyak salah. Coba lagi ${(blocked - now) / 60_000 + 1} menit lagi.")
        }
        val secret = Prefs.unlockSecret(c)
            ?: return Result.Error("Kode belum bisa dipakai: HP ini perlu online sekali dulu.")
        val m = match(secret, input, now)
        if (m == null) {
            val fails = Prefs.codeFails(c) + 1
            if (fails >= MAX_FAILS) {
                Prefs.setCodeFails(c, 0)
                Prefs.setCodeBlockedUntil(c, now + BLOCK_MS)
                return Result.Error("Kode salah $MAX_FAILS kali. Keypad dikunci 5 menit.")
            }
            Prefs.setCodeFails(c, fails)
            return Result.Error("Kode salah. Sisa ${MAX_FAILS - fails} percobaan.")
        }
        val key = "${m.first}:${m.second}"
        if (key in Prefs.usedCodes(c)) return Result.Error("Kode ini sudah dipakai. Minta kode baru.")
        Prefs.addUsedCode(c, key)
        Prefs.setCodeFails(c, 0)
        val minutes = DURATIONS_MIN[m.second]
        val until = now + minutes * 60_000
        Prefs.setLocalUnlock(c, now, until)
        LockState.refresh(c)
        return Result.Unlocked(until, minutes)
    }
}
