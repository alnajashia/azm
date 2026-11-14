package com.alnajashia.azm.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.alnajashia.azm.data.SettingsStore
import com.alnajashia.azm.focus.FocusScheduleManager
import com.alnajashia.azm.focus.FocusScheduleStorage
import com.alnajashia.azm.focus.FocusSessionStore

/**
 * Focus-schedule alarms (Batch I-A, item 13): a port of Dechainer's
 * `notifications/FocusScheduleReceiver.kt` (Apache-2.0), plus the
 * pre-reminder action and the auto-start branch.
 *
 *  - SCHEDULE_TRIGGER: re-arm the next alarm, skip when a focus
 *    session is already running (any phase but WAITING — a break that
 *    ran out without auto-start does not count as running), then
 *    either start the session directly (schedule auto-start) or show
 *    the reminder.
 *  - SNOOZE_TRIGGER: same skip rule; a snooze that fires while focus
 *    started meanwhile cancels itself.
 *  - PRE_REMINDER: a plain heads-up notification; re-arms (safe: the
 *    pre-reminder arm is future-only, so it cannot loop).
 */
class FocusScheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Removal teardown disarm (v1.0.5 audit A-H2): while a Device
        // Owner removal is in progress, no focus work may run.
        if (SettingsStore.isRemovalInProgress()) return
        when (intent.action) {
            ACTION_SCHEDULE_TRIGGER -> {
                Log.d(TAG, "Focus scheduled alarm triggered")
                FocusScheduleManager.reschedule(context)

                if (isSessionRunning(context)) {
                    Log.d(TAG, "Focus already active, skipping scheduled reminder")
                    return
                }

                val scheduleId = intent.getStringExtra(FocusScheduleManager.EXTRA_SCHEDULE_ID)
                val schedule = scheduleId?.let { id ->
                    FocusScheduleStorage.getSchedules(context).firstOrNull { it.id == id }
                } ?: return
                if (schedule.autoStart) {
                    Log.d(TAG, "Schedule ${schedule.id} auto-starts focus")
                    FocusSessionStore.startFocus(context)
                } else {
                    FocusScheduleManager.launchReminder(context, schedule, snoozeCount = 0)
                }
            }
            ACTION_SNOOZE_TRIGGER -> {
                val snoozeCount = intent.getIntExtra(EXTRA_SNOOZE_COUNT, 1)
                Log.d(TAG, "Focus snooze triggered, count=$snoozeCount")

                if (isSessionRunning(context)) {
                    Log.d(TAG, "Focus already active, cancelling snooze")
                    FocusScheduleManager.cancelSnooze(context)
                    return
                }

                // The snooze belongs to the schedule that armed it; if
                // that schedule is gone or disabled meanwhile, the
                // snooze is stale — drop it, do not remind for some
                // other schedule.
                val scheduleId = intent.getStringExtra(FocusScheduleManager.EXTRA_SCHEDULE_ID)
                val schedule = scheduleId?.let { id ->
                    FocusScheduleStorage.getSchedules(context)
                        .firstOrNull { it.id == id && it.enabled }
                } ?: run {
                    FocusScheduleManager.cancelSnooze(context)
                    return
                }
                FocusScheduleManager.launchReminder(context, schedule, snoozeCount = snoozeCount)
            }
            ACTION_PRE_REMINDER -> {
                FocusScheduleManager.reschedule(context)
                val label = intent.getStringExtra(FocusScheduleManager.EXTRA_SCHEDULE_LABEL) ?: ""
                val minutes = intent.getIntExtra(FocusScheduleManager.EXTRA_REMIND_MINUTES, 0)
                if (minutes > 0) {
                    FocusReminderNotifier.showPreReminder(context, label, minutes)
                }
            }
        }
    }

    /** A focus session is running in any phase except WAITING. */
    private fun isSessionRunning(context: Context): Boolean {
        val phase = FocusSessionStore.getStatus(context)?.phase ?: return false
        return phase != FocusSessionStore.Phase.WAITING
    }

    companion object {
        private const val TAG = "FocusScheduleReceiver"
        const val ACTION_SCHEDULE_TRIGGER = "com.alnajashia.azm.focus.SCHEDULE_TRIGGER"
        const val ACTION_SNOOZE_TRIGGER = "com.alnajashia.azm.focus.SNOOZE_TRIGGER"
        const val ACTION_PRE_REMINDER = "com.alnajashia.azm.focus.PRE_REMINDER"
        const val EXTRA_SNOOZE_COUNT = "snooze_count"
    }
}
