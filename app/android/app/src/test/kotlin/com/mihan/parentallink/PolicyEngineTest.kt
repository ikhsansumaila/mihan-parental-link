package com.mihan.parentallink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime

/** Kasus yang sama dengan test/schedule_test.dart agar Dart & Kotlin dijamin identik. */
class PolicyEngineTest {
    private val monday = LocalDate.of(2026, 11, 16)
    private fun at(d: LocalDate, h: Int, m: Int = 0) = d.atTime(h, m)

    private val json = """
    {"noScheduleMode":"unlocked","tamperGuard":true,"override":null,"schedules":[
      {"id":"harian","name":"Harian","enabled":true,"startDate":null,"endDate":null,"createdAt":0,
       "days":{"1":[{"s":720,"e":840},{"s":360,"e":420},{"s":1140,"e":1260}]}},
      {"id":"ujian","name":"Ujian","enabled":true,"startDate":"2026-12-01","endDate":"2026-12-31","createdAt":1,
       "days":{"1":[{"s":1140,"e":1200}]}},
      {"id":"minggu","name":"Minggu","enabled":true,"startDate":"2026-12-07","endDate":"2026-12-13","createdAt":2,
       "days":{}}
    ]}
    """.trimIndent()
    private val p = PolicyEngine.parse(json)

    @Test fun multiSlot() {
        assertEquals(false, PolicyEngine.lockedAt(p, at(monday, 6, 30)))
        assertEquals(false, PolicyEngine.lockedAt(p, at(monday, 13)))
        assertEquals(true, PolicyEngine.lockedAt(p, at(monday, 7)))
        assertEquals(true, PolicyEngine.lockedAt(p, at(monday, 15)))
        assertEquals(true, PolicyEngine.lockedAt(p, at(monday, 21)))
        assertEquals(true, PolicyEngine.lockedAt(p, at(monday.plusDays(1), 13)))
    }

    @Test fun nextChange() {
        assertEquals(at(monday, 12), PolicyEngine.nextChange(p, at(monday, 8)))
        assertEquals(at(monday, 14), PolicyEngine.nextChange(p, at(monday, 12, 5)))
    }

    @Test fun periodPriority() {
        assertEquals("harian", PolicyEngine.activeSchedule(p, monday)?.id)
        assertEquals("ujian", PolicyEngine.activeSchedule(p, LocalDate.of(2026, 12, 1))?.id)
        assertEquals("minggu", PolicyEngine.activeSchedule(p, LocalDate.of(2026, 12, 7))?.id)
        assertEquals("harian", PolicyEngine.activeSchedule(p, LocalDate.of(2027, 1, 4))?.id)
        // 2026-12-14 Senin: ujian, hanya 19:00-20:00
        assertEquals(true, PolicyEngine.lockedAt(p, LocalDateTime.of(2026, 12, 14, 13, 0)))
        assertEquals(false, PolicyEngine.lockedAt(p, LocalDateTime.of(2026, 12, 14, 19, 30)))
    }

    @Test fun overrideAndDefault() {
        val until = at(monday, 11).atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
        val po = p.copy(override = Override("lock", until))
        assertEquals(true, PolicyEngine.lockedAt(po, at(monday, 6, 30)))
        assertEquals(true, PolicyEngine.lockedAt(Policy(noScheduleMode = "locked"), at(monday, 10)))
        assertEquals(false, PolicyEngine.lockedAt(Policy(), at(monday, 10)))
        assertNull(PolicyEngine.activeSchedule(Policy(), monday))
    }
}
