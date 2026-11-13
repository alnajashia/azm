package com.alnajashia.azm.data

import java.time.DayOfWeek
import java.time.LocalDate

/**
 * Time-limit / time-window models, ported from the original DeChainer
 * `models/TimeLimit.kt`, `models/TimeWindow.kt`, `models/TimeWindows.kt` and
 * `models/AppGroup.kt` (Apache-2.0, warleysr/dechainer). Behaviour is identical:
 * a package (or group) has either a plain daily value or a per-weekday one,
 * never a mixture at read time.
 */

data class TimeLimit(val dailyMinutes: Int = 0, val weeklyMinutes: List<Int>? = null) {
    val isPerDay: Boolean get() = weeklyMinutes != null
    val isSet: Boolean get() = weeklyMinutes?.any { it > 0 } ?: (dailyMinutes > 0)

    fun minutesFor(day: DayOfWeek): Int = weeklyMinutes?.getOrNull(day.ordinal) ?: dailyMinutes
    fun todayMinutes(): Int = minutesFor(LocalDate.now().dayOfWeek)

    companion object {
        val NONE = TimeLimit()
        fun daily(minutes: Int) = TimeLimit(dailyMinutes = minutes)
        fun perDay(minutes: List<Int>): TimeLimit {
            require(minutes.size == DayOfWeek.entries.size)
            return TimeLimit(weeklyMinutes = minutes)
        }
    }
}

/** An allowed-usage window in minutes-of-day; may span midnight. */
data class TimeWindow(val startMinute: Int, val endMinute: Int) {
    fun contains(minuteOfDay: Int): Boolean =
        if (startMinute <= endMinute) minuteOfDay in startMinute until endMinute
        else minuteOfDay >= startMinute || minuteOfDay < endMinute

    fun minutesUntilEnd(minuteOfDay: Int): Int =
        if (endMinute > minuteOfDay) endMinute - minuteOfDay else (1440 - minuteOfDay) + endMinute

    fun formatted(): String = "%02d:%02d - %02d:%02d".format(
        startMinute / 60, startMinute % 60, endMinute / 60, endMinute % 60,
    )

    private fun segments(): List<Pair<Int, Int>> =
        if (startMinute <= endMinute) listOf(startMinute to endMinute)
        else listOf(startMinute to 1440, 0 to endMinute)

    companion object {
        /** Overlap of two window lists; an empty list is "no restriction" (the identity). */
        fun intersect(a: List<TimeWindow>, b: List<TimeWindow>): List<TimeWindow> {
            if (a.isEmpty()) return b
            if (b.isEmpty()) return a
            val result = mutableListOf<TimeWindow>()
            for ((startA, endA) in a.flatMap { it.segments() }) {
                for ((startB, endB) in b.flatMap { it.segments() }) {
                    val start = maxOf(startA, startB)
                    val end = minOf(endA, endB)
                    if (start < end) result.add(TimeWindow(start, end))
                }
            }
            return result
        }
    }
}

data class TimeWindows(
    val dailyWindows: List<TimeWindow> = emptyList(),
    val weeklyWindows: List<List<TimeWindow>>? = null,
) {
    val isPerDay: Boolean get() = weeklyWindows != null
    val isSet: Boolean get() = weeklyWindows?.any { it.isNotEmpty() } ?: dailyWindows.isNotEmpty()

    fun windowsFor(day: DayOfWeek): List<TimeWindow> =
        weeklyWindows?.getOrNull(day.ordinal) ?: dailyWindows

    fun todayWindows(): List<TimeWindow> = windowsFor(LocalDate.now().dayOfWeek)

    companion object {
        val NONE = TimeWindows()
        fun daily(windows: List<TimeWindow>) = TimeWindows(dailyWindows = windows)
        fun perDay(windows: List<List<TimeWindow>>): TimeWindows {
            require(windows.size == DayOfWeek.entries.size)
            return TimeWindows(weeklyWindows = windows)
        }

        fun intersect(a: TimeWindows, b: TimeWindows): TimeWindows {
            if (!a.isPerDay && !b.isPerDay) {
                return daily(TimeWindow.intersect(a.dailyWindows, b.dailyWindows))
            }
            val days = DayOfWeek.entries.map { day ->
                TimeWindow.intersect(a.windowsFor(day), b.windowsFor(day))
            }
            return perDay(days)
        }
    }
}

data class AppGroup(
    val id: String,
    val name: String,
    val packageNames: Set<String> = emptySet(),
    val timeLimit: TimeLimit = TimeLimit.NONE,
    val timeWindows: TimeWindows = TimeWindows.NONE,
    /** Reopening cooldown in seconds, as on per-app limits (Phase B parity fix). */
    val reopenSeconds: Int = 0,
)

enum class SuspensionReason {
    UNSUPPORTED_BROWSER,
    TORRENT_APP,
    RATED_18_PLUS,
    VISUAL_BLOCKING,
    IMPULSE_LOCK,
    FOCUS_MODE,
    ACCESSIBILITY_DISABLED,
    MANUAL;

    companion object {
        fun fromName(name: String?): SuspensionReason =
            entries.firstOrNull { it.name == name } ?: MANUAL
    }
}
