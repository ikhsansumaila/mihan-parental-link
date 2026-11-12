package com.mihan.parentallink

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Port 1:1 dari lib/core/schedule.dart. Berjalan offline di HP anak.
 * Kalau aturan di Dart berubah, ubah juga di sini.
 */
data class TimeWindow(val start: Int, val end: Int) {
    fun contains(m: Int) = m in start until end
}

data class Schedule(
    val id: String,
    val name: String,
    val enabled: Boolean,
    val startDate: LocalDate?,
    val endDate: LocalDate?,
    val createdAt: Long,
    val days: Map<Int, List<TimeWindow>>,
) {
    val hasPeriod get() = startDate != null || endDate != null
    val periodLength: Long?
        get() = if (startDate != null && endDate != null) ChronoUnit.DAYS.between(startDate, endDate) + 1 else null

    fun covers(d: LocalDate) =
        enabled && (startDate == null || !d.isBefore(startDate)) && (endDate == null || !d.isAfter(endDate))

    fun windowsFor(weekday: Int) = days[weekday] ?: emptyList()
}

data class Override(val mode: String, val until: Long?) {
    fun activeAt(millis: Long) = until == null || millis < until
}

data class Policy(
    val schedules: List<Schedule> = emptyList(),
    val noScheduleMode: String = "unlocked",
    val override: Override? = null,
    val tamperGuard: Boolean = true,
)

data class Decision(val locked: Boolean, val reason: String, val nextChange: Long?)

object PolicyEngine {
    private val zone: ZoneId get() = ZoneId.systemDefault()

    fun parse(json: String?): Policy {
        if (json.isNullOrBlank()) return Policy()
        return try {
            val j = JSONObject(json)
            val arr = j.optJSONArray("schedules") ?: JSONArray()
            val schedules = (0 until arr.length()).map { parseSchedule(arr.getJSONObject(it)) }
            val o = j.optJSONObject("override")
            Policy(
                schedules = schedules,
                noScheduleMode = j.optString("noScheduleMode", "unlocked"),
                override = o?.let {
                    Override(it.optString("mode", "lock"), if (it.isNull("until")) null else it.getLong("until"))
                },
                tamperGuard = j.optBoolean("tamperGuard", true),
            )
        } catch (e: Exception) {
            Policy()
        }
    }

    private fun parseDate(j: JSONObject, key: String): LocalDate? =
        if (j.isNull(key) || j.optString(key).isEmpty()) null else LocalDate.parse(j.getString(key))

    private fun parseSchedule(j: JSONObject): Schedule {
        val daysObj = j.optJSONObject("days") ?: JSONObject()
        val days = mutableMapOf<Int, List<TimeWindow>>()
        for (k in daysObj.keys()) {
            val a = daysObj.getJSONArray(k)
            days[k.toInt()] = (0 until a.length())
                .map { a.getJSONObject(it) }
                .map { TimeWindow(it.getInt("s"), it.getInt("e")) }
                .sortedBy { it.start }
        }
        return Schedule(
            id = j.optString("id"),
            name = j.optString("name", "Jadwal"),
            enabled = j.optBoolean("enabled", true),
            startDate = parseDate(j, "startDate"),
            endDate = parseDate(j, "endDate"),
            createdAt = j.optLong("createdAt", 0),
            days = days,
        )
    }

    fun activeSchedule(p: Policy, d: LocalDate): Schedule? =
        p.schedules.filter { it.covers(d) }.sortedWith(
            compareBy<Schedule> { if (it.hasPeriod) 0 else 1 }
                .thenBy { it.periodLength ?: Long.MAX_VALUE }
                .thenByDescending { it.createdAt }
        ).firstOrNull()

    private fun scheduleLocked(p: Policy, t: LocalDateTime): Boolean {
        val s = activeSchedule(p, t.toLocalDate()) ?: return p.noScheduleMode == "locked"
        val m = t.hour * 60 + t.minute
        return s.windowsFor(t.dayOfWeek.value).none { it.contains(m) }
    }

    private fun millis(t: LocalDateTime) = t.atZone(zone).toInstant().toEpochMilli()
    private fun local(ms: Long) = LocalDateTime.ofInstant(Instant.ofEpochMilli(ms), zone)

    fun lockedAt(p: Policy, t: LocalDateTime): Boolean {
        val o = p.override
        if (o != null && o.activeAt(millis(t))) return o.mode == "lock"
        return scheduleLocked(p, t)
    }

    fun nextChange(p: Policy, now: LocalDateTime): LocalDateTime? {
        val current = lockedAt(p, now)
        val candidates = sortedSetOf<LocalDateTime>()
        p.override?.until?.let { candidates.add(local(it)) }
        val today = now.toLocalDate()
        for (i in 0..8) {
            val day = today.plusDays(i.toLong())
            val midnight = day.atStartOfDay()
            candidates.add(midnight)
            val s = activeSchedule(p, day) ?: continue
            for (w in s.windowsFor(day.dayOfWeek.value)) {
                candidates.add(midnight.plusMinutes(w.start.toLong()))
                if (w.end < 1440) candidates.add(midnight.plusMinutes(w.end.toLong()))
            }
        }
        return candidates.filter { it.isAfter(now) }.firstOrNull { lockedAt(p, it) != current }
    }

    fun evaluate(p: Policy, nowMs: Long = System.currentTimeMillis()): Decision {
        val now = local(nowMs)
        val locked = lockedAt(p, now)
        val o = p.override
        val s = activeSchedule(p, now.toLocalDate())
        val reason = when {
            o != null && o.activeAt(nowMs) ->
                if (o.mode == "lock") "Dikunci manual oleh orang tua" else "Dibuka manual oleh orang tua"
            s == null ->
                if (p.noScheduleMode == "locked") "Tidak ada jadwal aktif (default: kunci)"
                else "Tidak ada jadwal aktif (bebas)"
            locked -> "Di luar jam pakai \"${s.name}\""
            else -> "Jam pakai \"${s.name}\""
        }
        return Decision(locked, reason, nextChange(p, now)?.let { millis(it) })
    }
}
