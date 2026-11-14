package com.alnajashia.azm.lockdown

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.alnajashia.azm.notifications.LockdownReceiver

/**
 * The lockdown's alarm manager (Batch I-B, item 14).
 *
 * Two alarms, both exact-or-fallback (the same honesty rule as
 * [FocusScheduleManager]: `setExactAndAllowWhileIdle` when the app
 * may schedule exact alarms, else `setAndAllowWhileIdle` and the UI
 * shows the inexact banner):
 *
 *  - the **end alarm** (`ELAPSED_REALTIME_WAKEUP` at the active
 *    lockdown's elapsed-realtime deadline — moving the clock cannot
 *    move it);
 *  - the **window-start alarm** (`RTC_WAKEUP` at the next enabled
 *    recurring window's start — windows are calendar concepts).
 *
 * One window alarm at a time: the earliest start wins; when it
 * fires, the receiver starts that window and re-reschedules.
 */
object LockdownManager {
    const val ACTION_WINDOW_START = "com.alnajashia.azm.lockdown.WINDOW_START"
    const val ACTION_END = "com.alnajashia.azm.lockdown.END"
    const val EXTRA_LOCKDOWN_ID = "lockdownId"

    private const val REQUEST_WINDOW_START = 0x0F0C30
    private const val REQUEST_END = 0x0F0C31

    fun canScheduleExactAlarms(context: Context): Boolean {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return false
        return canScheduleExactAlarms(alarmManager)
    }

    private fun canScheduleExactAlarms(alarmManager: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

    fun armEndAlarm(context: Context, endElapsedRealtime: Long) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = endIntent(context)
        if (canScheduleExactAlarms(alarmManager)) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                endElapsedRealtime,
                intent,
            )
        } else {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                endElapsedRealtime,
                intent,
            )
        }
    }

    fun cancelEndAlarm(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        alarmManager.cancel(endIntent(context))
    }

    private fun endIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        REQUEST_END,
        Intent(context, LockdownReceiver::class.java).setAction(ACTION_END),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /**
     * Arms the next enabled recurring window's start (or cancels the
     * window alarm when no window is enabled). Called on every
     * config save and on every sync, so a window survives reboots
     * and force-stops.
     */
    fun rescheduleWindows(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val next = LockdownStore.getLockdowns(context)
            .mapNotNull { lockdown ->
                lockdown.nextWindowStartMillis()?.let { it to lockdown.id }
            }
            .minByOrNull { it.first }
        if (next == null) {
            alarmManager.cancel(windowStartIntent(context, null))
            return
        }
        val (startMillis, id) = next
        val intent = windowStartIntent(context, id)
        if (canScheduleExactAlarms(alarmManager)) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                startMillis,
                intent,
            )
        } else {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                startMillis,
                intent,
            )
        }
    }

    private fun windowStartIntent(context: Context, lockdownId: String?): PendingIntent {
        val intent = Intent(context, LockdownReceiver::class.java)
            .setAction(ACTION_WINDOW_START)
        if (lockdownId != null) intent.putExtra(EXTRA_LOCKDOWN_ID, lockdownId)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_WINDOW_START,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Launches the Tier 2 kiosk activity unconditionally. */
    fun launchActivity(context: Context) {
        val intent = Intent(context, LockdownActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        context.startActivity(intent)
    }

    /** Launches the kiosk activity only when it is not already visible. */
    fun launchActivityIfNeeded(context: Context) {
        if (!LockdownActivity.isRunning) launchActivity(context)
    }
}
