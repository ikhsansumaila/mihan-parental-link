package com.mihan.parentallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class UnlockCodeTest {
    // Vektor acuan yang sama dengan test/unlock_code_test.dart (dihitung dengan Python hmac).
    @Test fun kodeSamaDenganVektorAcuan() {
        assertEquals("729148", UnlockCode.code("test-secret-123", 5000000, 0))
        assertEquals("560662", UnlockCode.code("test-secret-123", 5000000, 3))
        assertEquals("936705", UnlockCode.code("AbCdEfGh0123456789xyzXYZ_-", 5912345, 1))
    }

    @Test fun matchMenerimaKodeSampai2StepLalu() {
        val now = 5000000L * UnlockCode.STEP_MS + 1000
        val old = UnlockCode.code("s", 5000000 - 2, 1)
        assertEquals(Pair(5000000L - 2, 1), UnlockCode.match("s", old, now))
    }

    @Test fun matchMenolakKodeKedaluwarsa() {
        val now = 5000000L * UnlockCode.STEP_MS
        assertNull(UnlockCode.match("s", UnlockCode.code("s", 5000000 - 3, 0), now))
    }

    @Test fun matchMenolakSecretLain() {
        val now = 5000000L * UnlockCode.STEP_MS
        assertNull(UnlockCode.match("lain", UnlockCode.code("s", 5000000, 0), now))
    }

    @Test fun matchMengenaliDurasi() {
        val now = 5000000L * UnlockCode.STEP_MS
        assertEquals(3, UnlockCode.match("s", UnlockCode.code("s", 5000000, 3), now)!!.second)
    }
}
