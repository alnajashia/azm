package com.alnajashia.azm.focus

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import com.alnajashia.azm.notifications.FocusReminderNotifier
import com.alnajashia.azm.notifications.FocusScheduleReceiver

/**
 * Focus-schedule alarms (Batch I-A, item 13): a port of Dechainer's
 * `data/FocusScheduleManager.kt` (Apache-2.0), plus the Azm
 * pre-reminder alarm ([FocusSchedule.remindMinutesBefore]) and the
 * exact-alarm permission helpers.
 *
 * One next-trigger exact alarm, exactly as in the original:
 * `RTC_WAKEUP`, `setExactAndAllowWhileIdle` when the app may schedule
 * exact alarms, else `setAndAllowWhileIdle` (inexact — the UI shows an
 * honest banner in that case, it never silently schedules an alarm
 * that will not fire on time).
 */
object FocusScheduleManager {
    private const val TAG = "FocusScheduleManager"
    private const val SCHEDULE_ALARM_REQUEST_CODE = 0x0F0C10
    private const val SNOOZE_ALARM_REQUEST_CODE = 0x0F0C11
    private const val PRE_REMINDER_ALARM_REQUEST_CODE = 0x0F0C12
    const val SNOOZE_DELAY_MILLIS = 5 * 60 * 1000L // 5 minutes
    const val MAX_SNOOZES = 2

    const val EXTRA_SCHEDULE_ID = "schedule_id"
    const val EXTRA_SCHEDULE_LABEL = "schedule_label"
    const val EXTRA_REMIND_MINUTES = "remind_minutes"

    fun reschedule(context: Context) {
        val schedules = FocusScheduleStorage.getSchedules(context)
        val next = schedules.filter { it.enabled }
            .mapNotNull { s -> s.nextTriggerMillis()?.let { it to s } }
            .minByOrNull { it.first }

        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val triggerIntent = schedulePendingIntent(context)

        if (next == null) {
            Log.d(TAG, "No enabled focus schedules, cancelling alarms")
            alarmManager.cancel(triggerIntent)
            alarmManager.cancel(preReminderPendingIntent(context))
            return
        }

        val (nextTrigger, schedule) = next
        Log.d(TAG, "Next focus schedule trigger at: $nextTrigger")
        setAlarm(alarmManager, nextTrigger, triggerIntentWithSchedule(context, schedule.id))

        // Pre-reminder (Azm extension): a second exact alarm at
        // start − N minutes. Armed only while it is still in the
        // future, so a re-arm from the pre-reminder path itself can
        // never re-fire it in a loop.
        val preIntent = preReminderPendingIntent(context)
        val preTrigger = nextTrigger - schedule.remindMinutesBefore * 60_000L
        if (schedule.remindMinutesBefore > 0 && preTrigger > System.currentTimeMillis()) {
            setAlarm(
                alarmManager,
                preTrigger,
                preReminderIntentWithSchedule(context, schedule),
            )
        } else {
            alarmManager.cancel(preIntent)
        }
    }

    private fun setAlarm(
        alarmManager: AlarmManager,
        triggerAtMillis: Long,
        pendingIntent: PendingIntent,
    ) {
        if (canScheduleExactAlarms(alarmManager)) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        } else {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        }
    }

    /**
     * Arms the 5-minute snooze for the schedule that showed the
     * reminder. The schedule id rides in the PendingIntent so a
     * snooze never fires for a schedule that was deleted or disabled
     * meanwhile.
     */
    fun scheduleSnooze(
        context: Context,
        snoozeCount: Int,
        scheduleId: String?,
        scheduleLabel: String,
    ) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val triggerAt = System.currentTimeMillis() + SNOOZE_DELAY_MILLIS
        Log.d(TAG, "Scheduling focus snooze #$snoozeCount for 5 min from now")
        setAlarm(
            alarmManager,
            triggerAt,
            snoozePendingIntent(context, snoozeCount, scheduleId, scheduleLabel),
        )
    }

    fun cancelSnooze(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        // PendingIntent matching ignores extras, so the null-id
        // intent cancels any armed snooze.
        alarmManager.cancel(snoozePendingIntent(context, 0, null, ""))
    }

    /** Posts the reminder notification AND tries a direct activity start (belt and braces). */
    fun launchReminder(context: Context, schedule: FocusSchedule, snoozeCount: Int) {
        val activityIntent = Intent(context, FocusReminderActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(FocusReminderActivity.EXTRA_SNOOZE_COUNT, snoozeCount)
            putExtra(EXTRA_SCHEDULE_ID, schedule.id)
            putExtra(EXTRA_SCHEDULE_LABEL, schedule.label)
        }

        FocusReminderNotifier.showReminder(context, activityIntent, schedule.label)

        try {
            context.startActivity(activityIntent)
        } catch (e: Exception) {
            Log.w(TAG, "Could not start FocusReminderActivity directly from background", e)
        }
    }

    fun canScheduleExactAlarms(context: Context): Boolean {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return false
        return canScheduleExactAlarms(alarmManager)
    }

    private fun canScheduleExactAlarms(alarmManager: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

    /** Opens the system exact-alarm permission screen for this app. */
    fun openExactAlarmSettings(context: Context) {
        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
            data = Uri.parse("package:${context.packageName}")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        context.startActivity(intent)
    }

    private fun schedulePendingIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            SCHEDULE_ALARM_REQUEST_CODE,
            Intent(context, FocusScheduleReceiver::class.java)
                .setAction(FocusScheduleReceiver.ACTION_SCHEDULE_TRIGGER),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun triggerIntentWithSchedule(context: Context, scheduleId: String): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            SCHEDULE_ALARM_REQUEST_CODE,
            Intent(context, FocusScheduleReceiver::class.java)
                .setAction(FocusScheduleReceiver.ACTION_SCHEDULE_TRIGGER)
                .putExtra(EXTRA_SCHEDULE_ID, scheduleId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun snoozePendingIntent(
        context: Context,
        snoozeCount: Int,
        scheduleId: String?,
        scheduleLabel: String,
    ): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            SNOOZE_ALARM_REQUEST_CODE,
            Intent(context, FocusScheduleReceiver::class.java).apply {
                action = FocusScheduleReceiver.ACTION_SNOOZE_TRIGGER
                putExtra(FocusScheduleReceiver.EXTRA_SNOOZE_COUNT, snoozeCount)
                putExtra(EXTRA_SCHEDULE_ID, scheduleId)
                putExtra(EXTRA_SCHEDULE_LABEL, scheduleLabel)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun preReminderPendingIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            PRE_REMINDER_ALARM_REQUEST_CODE,
            Intent(context, FocusScheduleReceiver::class.java)
                .setAction(FocusScheduleReceiver.ACTION_PRE_REMINDER),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun preReminderIntentWithSchedule(
        context: Context,
        schedule: FocusSchedule,
    ): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            PRE_REMINDER_ALARM_REQUEST_CODE,
            Intent(context, FocusScheduleReceiver::class.java)
                .setAction(FocusScheduleReceiver.ACTION_PRE_REMINDER)
                .putExtra(EXTRA_SCHEDULE_ID, schedule.id)
                .putExtra(EXTRA_SCHEDULE_LABEL, schedule.label)
                .putExtra(EXTRA_REMIND_MINUTES, schedule.remindMinutesBefore),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}
