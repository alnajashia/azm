package com.alnajashia.azm.focus

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray

/**
 * Focus-schedule storage (Batch I-A, item 13): a port of Dechainer's
 * `data/FocusScheduleStorage.kt` (Apache-2.0). JSON array in
 * SharedPreferences `focus_schedules_prefs`; corrupt JSON decodes to
 * empty (safe default, logged by the caller when it matters). Every
 * mutation re-arms the alarm via [FocusScheduleManager.reschedule].
 */
object FocusScheduleStorage {
    const val PREFS_NAME = "focus_schedules_prefs"
    private const val KEY_SCHEDULES = "schedules"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getSchedules(context: Context): List<FocusSchedule> {
        val json = prefs(context).getString(KEY_SCHEDULES, null) ?: return emptyList()
        return decode(json)
    }

    fun saveSchedules(context: Context, schedules: List<FocusSchedule>) {
        prefs(context).edit().putString(KEY_SCHEDULES, encode(schedules)).apply()
        FocusScheduleManager.reschedule(context)
    }

    fun addOrUpdateSchedule(context: Context, schedule: FocusSchedule) {
        val current = getSchedules(context).toMutableList()
        val index = current.indexOfFirst { it.id == schedule.id }
        if (index >= 0) {
            current[index] = schedule
        } else {
            current.add(schedule)
        }
        saveSchedules(context, current)
    }

    fun deleteSchedule(context: Context, id: String) {
        saveSchedules(context, getSchedules(context).filterNot { it.id == id })
    }

    fun toggleSchedule(context: Context, id: String, enabled: Boolean) {
        saveSchedules(
            context,
            getSchedules(context).map {
                if (it.id == id) it.copy(enabled = enabled) else it
            },
        )
    }

    fun decode(json: String): List<FocusSchedule> = try {
        val array = JSONArray(json)
        (0 until array.length()).mapNotNull { array.optJSONObject(it)?.let { FocusSchedule.fromJson(it) } }
    } catch (_: Exception) {
        emptyList()
    }

    fun encode(schedules: List<FocusSchedule>): String {
        val array = JSONArray()
        schedules.forEach { array.put(it.toJson()) }
        return array.toString()
    }
}
