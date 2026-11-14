package com.alnajashia.azm.focus

import org.json.JSONArray
import org.json.JSONObject
import java.time.DayOfWeek
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import java.util.UUID

/**
 * Focus schedules (Batch I-A, item 13): a port of Dechainer's
 * `models/FocusSchedule.kt` (Apache-2.0), plus three Azm extensions
 * ([autoStart], [remindMinutesBefore], [label]) that default to
 * Dechainer behaviour. A schedule is a START time only — the session
 * length comes from the Pomodoro config, exactly as in the original.
 */
data class FocusSchedule(
    val id: String = UUID.randomUUID().toString(),
    val daysOfWeek: Set<Int>, // 1 = Monday .. 7 = Sunday (DayOfWeek.value)
    val hour: Int, // 0..23
    val minute: Int, // 0..59
    val enabled: Boolean = true,
    val autoStart: Boolean = false,
    val remindMinutesBefore: Int = 0, // 0 = none; else 5/10
    val label: String = "",
) {
    fun formattedTime(): String = "%02d:%02d".format(hour, minute)

    /**
     * The next epoch timestamp (ms) at which this schedule should
     * trigger, given [now]. Null when disabled or no days configured.
     * Ported verbatim from the original (including the
     * `TemporalAdjusters.next` strictly-after-today rule).
     */
    fun nextTriggerMillis(now: LocalDateTime = LocalDateTime.now()): Long? {
        if (!enabled || daysOfWeek.isEmpty()) return null

        val currentDay = now.dayOfWeek.value
        val currentTimeInMinutes = now.hour * 60 + now.minute
        val targetTimeInMinutes = hour * 60 + minute

        // If today is in the schedule and the target time is later today:
        if (currentDay in daysOfWeek && targetTimeInMinutes > currentTimeInMinutes) {
            val targetDateTime = now.withHour(hour).withMinute(minute).withSecond(0).withNano(0)
            return targetDateTime.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        }

        // Otherwise find the earliest day of week from tomorrow up to 7 days ahead.
        var minDateTime: LocalDateTime? = null
        for (dayVal in daysOfWeek) {
            val dow = DayOfWeek.of(dayVal)
            val candidate = now.with(TemporalAdjusters.next(dow))
                .withHour(hour).withMinute(minute).withSecond(0).withNano(0)
            if (minDateTime == null || candidate.isBefore(minDateTime)) {
                minDateTime = candidate
            }
        }

        return minDateTime?.atZone(ZoneId.systemDefault())?.toInstant()?.toEpochMilli()
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "days" to daysOfWeek.sorted(),
        "hour" to hour,
        "minute" to minute,
        "enabled" to enabled,
        "autoStart" to autoStart,
        "remindMinutesBefore" to remindMinutesBefore,
        "label" to label,
    )

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("days", JSONArray(daysOfWeek.sorted()))
        .put("h", hour)
        .put("m", minute)
        .put("en", enabled)
        .put("autoStart", autoStart)
        .put("remindMinutesBefore", remindMinutesBefore)
        .put("label", label)

    companion object {
        fun fromJson(json: JSONObject): FocusSchedule? {
            return try {
                val daysArray = json.optJSONArray("days") ?: return null
                val days = (0 until daysArray.length())
                    .map { daysArray.optInt(it) }
                    .filter { it in 1..7 }
                    .toSet()
                FocusSchedule(
                    id = json.optString("id", "").takeIf { it.isNotEmpty() } ?: return null,
                    daysOfWeek = days,
                    hour = json.optInt("h", 0).coerceIn(0, 23),
                    minute = json.optInt("m", 0).coerceIn(0, 59),
                    enabled = json.optBoolean("en", true),
                    autoStart = json.optBoolean("autoStart", false),
                    remindMinutesBefore = json.optInt("remindMinutesBefore", 0).coerceIn(0, 60),
                    label = json.optString("label", ""),
                )
            } catch (_: Exception) {
                null
            }
        }

        fun fromMap(m: Map<*, *>): FocusSchedule? {
            val id = m["id"] as? String ?: return null
            if (id.isEmpty()) return null
            val days = (m["days"] as? List<*>)
                ?.mapNotNull { (it as? Number)?.toInt() }
                ?.filter { it in 1..7 }
                ?.toSet() ?: emptySet()
            return FocusSchedule(
                id = id,
                daysOfWeek = days,
                hour = ((m["hour"] as? Number)?.toInt() ?: 0).coerceIn(0, 23),
                minute = ((m["minute"] as? Number)?.toInt() ?: 0).coerceIn(0, 59),
                enabled = m["enabled"] as? Boolean ?: true,
                autoStart = m["autoStart"] as? Boolean ?: false,
                remindMinutesBefore =
                    ((m["remindMinutesBefore"] as? Number)?.toInt() ?: 0).coerceIn(0, 60),
                label = m["label"] as? String ?: "",
            )
        }
    }
}
