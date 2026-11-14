package com.alnajashia.azm.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.alnajashia.azm.R
import com.alnajashia.azm.focus.FocusSessionStore

/**
 * Focus-schedule reminders (Batch I-A, item 13): a port of Dechainer's
 * `notifications/FocusReminderNotifier.kt` (Apache-2.0), plus the plain
 * pre-reminder heads-up. The reminder posts a high-priority
 * notification with a full-screen intent AND the manager tries a
 * direct activity start — belt and braces, as in the original.
 */
object FocusReminderNotifier {
    private const val TAG = "FocusReminderNotifier"
    private const val CHANNEL_REMINDER = "focus_schedule_reminder"
    const val NOTIFICATION_ID = 0x0F0C20
    const val PRE_REMINDER_NOTIFICATION_ID = 0x0F0C21

    private val vibrationPattern = longArrayOf(0, 400, 200, 400)

    private fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_REMINDER) == null) {
            val channel = NotificationChannel(
                CHANNEL_REMINDER,
                context.getString(R.string.focus_schedule_channel),
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = context.getString(R.string.focus_reminder_desc)
                enableVibration(true)
                vibrationPattern = FocusReminderNotifier.vibrationPattern
            }
            manager.createNotificationChannel(channel)
        }
    }

    fun showReminder(context: Context, activityIntent: Intent, label: String) {
        ensureChannel(context)

        val fullScreenPendingIntent = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID,
            activityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val title = if (label.isBlank()) {
            context.getString(R.string.focus_reminder_title)
        } else {
            context.getString(R.string.focus_reminder_title_label, label)
        }
        val notification = NotificationCompat.Builder(context, CHANNEL_REMINDER)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(context.getString(R.string.focus_reminder_desc))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            // No explicit sound: the channel default applies, as in
            // the original (its alert sound is the focus session's own).
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setContentIntent(fullScreenPendingIntent)
            .setAutoCancel(true)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (e: SecurityException) {
            Log.w(TAG, "Could not post focus reminder notification", e)
        }

        if (FocusSessionStore.isVibrationEnabled()) vibrate(context)
    }

    /** Plain heads-up (Azm extension): "focus starts in N minutes". No full-screen intent. */
    fun showPreReminder(context: Context, label: String, minutesBefore: Int) {
        ensureChannel(context)
        val text = if (label.isBlank()) {
            context.getString(R.string.focus_pre_reminder_body, minutesBefore)
        } else {
            context.getString(R.string.focus_pre_reminder_body_label, label, minutesBefore)
        }
        val notification = NotificationCompat.Builder(context, CHANNEL_REMINDER)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(context.getString(R.string.focus_pre_reminder_title))
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context)
                .notify(PRE_REMINDER_NOTIFICATION_ID, notification)
        } catch (e: SecurityException) {
            Log.w(TAG, "Could not post focus pre-reminder notification", e)
        }
    }

    fun cancel(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    private fun vibrate(context: Context) {
        val vibrator = context.getSystemService(Vibrator::class.java) ?: return
        if (!vibrator.hasVibrator()) return
        try {
            vibrator.vibrate(VibrationEffect.createWaveform(vibrationPattern, -1))
        } catch (e: Exception) {
            Log.w(TAG, "Could not vibrate for focus reminder", e)
        }
    }
}
