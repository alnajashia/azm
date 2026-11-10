package io.github.alnajashia.dominanter.focus

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import io.github.alnajashia.dominanter.MainActivity
import io.github.alnajashia.dominanter.R
import io.github.alnajashia.dominanter.notifications.FocusReceiver

/**
 * The focus status notification and its foreground service — a port of the
 * original `notifications/FocusNotifier.kt` + `notifications/FocusService.kt`
 * from DeChainer (Apache-2.0, warleysr/dechainer), adapted to this codebase:
 * the original's custom `RemoteViews` countdown layout is replaced by a
 * framework notification with a chronometer + progress bar (this project
 * ships no notification layouts), and Timber becomes `Log`. The behaviour —
 * channel, actions, tick cadence, foreground discipline — is the original's.
 *
 * The service's only job is to re-post the countdown notification so its
 * progress moves, which, unlike the chronometer, doesn't happen on its own.
 * Phase changes are driven by the alarm in [FocusSessionStore], not by this.
 *
 * The original's `stopForDebugInstall` hatch (keeping the service down so a
 * debug build can install) belongs to the deliberately excluded F34 debug
 * surface and is not ported.
 */
object FocusStatusNotifier {
    private const val TAG = "FocusStatusNotifier"
    private const val CHANNEL_TIMER = "focus_timer"

    const val STATUS_ID = 0x0F0C05

    private fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_TIMER) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_TIMER, context.getString(R.string.focus_channel_name),
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    setSound(null, null)
                    enableVibration(false)
                    setShowBadge(false)
                },
            )
        }
    }

    private fun contentIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context, 0,
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun actionIntent(context: Context, action: String): PendingIntent =
        PendingIntent.getBroadcast(
            context, action.hashCode(),
            Intent(context, FocusReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun phaseTitle(context: Context, status: FocusSessionStore.Status): String =
        when (status.phase) {
            FocusSessionStore.Phase.FOCUS -> context.getString(
                R.string.focus_phase_focus,
                minOf(status.completedFocus + 1, status.cyclesBeforeLongBreak),
                status.cyclesBeforeLongBreak,
            )
            FocusSessionStore.Phase.SHORT_BREAK ->
                context.getString(R.string.focus_phase_short_break)
            FocusSessionStore.Phase.LONG_BREAK ->
                context.getString(R.string.focus_phase_long_break)
            FocusSessionStore.Phase.WAITING ->
                context.getString(R.string.focus_phase_waiting)
        }

    /** Also makes sure [FocusService] is running to keep the progress bar moving. */
    fun showStatus(context: Context) {
        if (!FocusSessionStore.isActive()) return
        updateStatus(context)
        FocusService.ensureRunning(context)
    }

    /** For a service start that finds no session: it still has to go foreground before stopping. */
    fun buildPlaceholder(context: Context): Notification {
        ensureChannel(context)
        return Notification.Builder(context, CHANNEL_TIMER)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(context.getString(R.string.focus_mode_title))
            .setPriority(Notification.PRIORITY_LOW)
            .build()
    }

    fun updateStatus(context: Context) {
        val notification = buildStatus(context) ?: return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (!manager.areNotificationsEnabled()) {
            Log.d(TAG, "Focus mode: notifications not enabled, status not shown")
            return
        }
        try {
            manager.notify(STATUS_ID, notification)
        } catch (e: SecurityException) {
            Log.w(TAG, "Focus mode: could not post status notification", e)
        }
    }

    fun buildStatus(context: Context): Notification? {
        val status = FocusSessionStore.getStatus(context) ?: return null
        ensureChannel(context)

        val title = phaseTitle(context, status).let {
            if (status.paused) context.getString(R.string.focus_paused_prefix, it) else it
        }
        val message = when {
            status.phase == FocusSessionStore.Phase.WAITING ->
                context.getString(R.string.focus_msg_waiting)
            status.paused && !status.releasedApps &&
                FocusSessionStore.getActiveSuspension().isNotEmpty() ->
                context.getString(R.string.focus_msg_paused_apps)
            status.paused -> context.getString(R.string.focus_msg_paused)
            status.phase == FocusSessionStore.Phase.FOCUS -> {
                val apps = FocusSessionStore.getActiveSuspension().size
                if (apps > 0) {
                    context.getString(R.string.focus_msg_apps_suspended, apps)
                } else {
                    context.getString(R.string.focus_msg_stay_focused)
                }
            }
            else -> context.getString(R.string.focus_msg_break)
        }

        val builder = Notification.Builder(context, CHANNEL_TIMER)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(message)
            .setShowWhen(false)
            .setContentIntent(contentIntent(context))
            // Swiping it away just brings it back (via sync).
            .setDeleteIntent(actionIntent(context, FocusReceiver.ACTION_REPOST))
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setPriority(Notification.PRIORITY_LOW)

        if (status.phase != FocusSessionStore.Phase.WAITING) {
            builder.setUsesChronometer(true)
            builder.setChronometerCountDown(true)
            builder.setWhen(SystemClock.elapsedRealtime() + status.remainingMillis)
            val durationSeconds = (status.phaseDurationMillis / 1000).toInt().coerceAtLeast(1)
            val elapsedSeconds = ((status.phaseDurationMillis - status.remainingMillis) / 1000).toInt()
            builder.setProgress(durationSeconds, elapsedSeconds.coerceIn(0, durationSeconds), false)
        }

        // Only actions that need no recovery code.
        val isBreak = status.phase == FocusSessionStore.Phase.SHORT_BREAK ||
            status.phase == FocusSessionStore.Phase.LONG_BREAK
        if (status.phase == FocusSessionStore.Phase.WAITING) {
            builder
                .addAction(
                    Notification.Action.Builder(
                        android.R.drawable.ic_media_play,
                        context.getString(R.string.focus_action_start),
                        actionIntent(context, FocusReceiver.ACTION_START_FOCUS),
                    ).build(),
                )
                .addAction(
                    Notification.Action.Builder(
                        android.R.drawable.ic_menu_close_clear_cancel,
                        context.getString(R.string.focus_action_end),
                        actionIntent(context, FocusReceiver.ACTION_STOP),
                    ).build(),
                )
        }
        if (status.paused) {
            builder.addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_media_play,
                    context.getString(R.string.focus_action_resume),
                    actionIntent(context, FocusReceiver.ACTION_RESUME),
                ).build(),
            )
        }
        if (isBreak) {
            builder.addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_media_next,
                    context.getString(R.string.focus_action_skip_break),
                    actionIntent(context, FocusReceiver.ACTION_SKIP_BREAK),
                ).build(),
            )
        }

        return builder.build()
    }

    fun cancel(context: Context) {
        FocusService.stop(context)
        context.getSystemService(NotificationManager::class.java)?.cancel(STATUS_ID)
    }
}

/**
 * Re-posts the countdown notification so its progress bar moves. A direct
 * port of the original `FocusService` (see [FocusStatusNotifier]).
 */
class FocusService : Service() {
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())

    private val tick = object : Runnable {
        override fun run() {
            FocusSessionStore.syncIfDue(this@FocusService)
            val status = FocusSessionStore.getStatus(this@FocusService)
            if (status == null) {
                stopSelf()
                return
            }
            if (status.phase == FocusSessionStore.Phase.WAITING || status.paused) {
                schedule(WAITING_TICK_MS)
                return
            }
            if (getSystemService(PowerManager::class.java)?.isInteractive != false) {
                FocusStatusNotifier.updateStatus(this@FocusService)
            }
            schedule(tickInterval(status.phaseDurationMillis))
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // startForeground() must be called for every startForegroundService(), even when the session
        // ended in between; skipping it crashes the app with ForegroundServiceDidNotStartInTimeException.
        val notification = FocusStatusNotifier.buildStatus(this)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    FocusStatusNotifier.STATUS_ID,
                    notification ?: FocusStatusNotifier.buildPlaceholder(this),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(
                    FocusStatusNotifier.STATUS_ID,
                    notification ?: FocusStatusNotifier.buildPlaceholder(this),
                )
            }
        } catch (e: Exception) {
            Log.w("FocusService", "Focus mode: could not go foreground", e)
            stopSelf()
            return START_NOT_STICKY
        }
        if (notification == null) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        restartTicking()
        return START_STICKY
    }

    private fun restartTicking() {
        handler.removeCallbacks(tick)
        handler.post(tick)
    }

    // Always dropping what's queued keeps a single tick pending, even when a tick's own sync restarts ticking.
    private fun schedule(delayMillis: Long) {
        handler.removeCallbacks(tick)
        handler.postDelayed(tick, delayMillis)
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val MIN_TICK_MS = 1_000L
        private const val WAITING_TICK_MS = 60_000L

        private const val BAR_STEPS = 300

        private var instance: FocusService? = null

        private fun tickInterval(phaseDurationMillis: Long) =
            (phaseDurationMillis / BAR_STEPS).coerceAtLeast(MIN_TICK_MS)

        fun ensureRunning(context: Context) {
            instance?.let {
                it.restartTicking()
                return
            }
            try {
                context.startForegroundService(Intent(context, FocusService::class.java))
            } catch (e: Exception) {
                Log.w("FocusService", "Focus mode: could not start the timer service", e)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, FocusService::class.java))
        }
    }
}
