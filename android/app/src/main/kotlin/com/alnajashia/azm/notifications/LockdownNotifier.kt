package com.alnajashia.azm.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.alnajashia.azm.MainActivity
import com.alnajashia.azm.R
import com.alnajashia.azm.lockdown.LockdownStore
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The lockdown's notification (Batch I-B, item 14).
 *
 * A persistent (ongoing) notification carrying the lockdown's
 * wall-clock end time — static text, not a ticking countdown, so
 * no foreground service is needed for it. The live countdown is
 * the Tier 2 kiosk activity, and the Dart UI while the app is
 * open.
 */
object LockdownNotifier {
    const val CHANNEL_LOCKDOWN = "lockdown"
    const val NOTIFICATION_ID = 0x0F0C32

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_LOCKDOWN,
            context.getString(R.string.lockdown_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        )
        manager.createNotificationChannel(channel)
    }

    fun showActive(context: Context, active: LockdownStore.ActiveLockdown) {
        ensureChannel(context)
        val endText = SimpleDateFormat("HH:mm", Locale.getDefault())
            .format(Date(active.endWallClock))
        val label = active.lockdown.label
        val body = if (label.isEmpty()) {
            context.getString(R.string.lockdown_notification_body, endText)
        } else {
            context.getString(R.string.lockdown_notification_body_label, label, endText)
        }
        val openIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_LOCKDOWN)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(context.getString(R.string.lockdown_notification_title))
            .setContentText(body)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .build()
        context.getSystemService(NotificationManager::class.java)
            ?.notify(NOTIFICATION_ID, notification)
    }

    fun cancel(context: Context) {
        context.getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
    }
}
