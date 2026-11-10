package io.github.alnajashia.dominanter.notifications

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log
import io.github.alnajashia.dominanter.MainActivity
import io.github.alnajashia.dominanter.R
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import kotlin.math.roundToInt

/**
 * Staged usage warnings (F12) — a port of the original
 * `data/UsageWarningSettings.kt`, `models/UsageAlertStage.kt`,
 * `notifications/UsageWarningNotifier.kt` and
 * `notifications/UsageWarningDismissReceiver.kt` from DeChainer
 * (Apache-2.0, warleysr/dechainer).
 *
 * Settings live in the `usage_warning_prefs` store owned by SettingsStore
 * under the original's keys (`enabled`, `stages` as a JSON string) — the
 * exact schema the Dart `ConfigStore` reads and writes, so the
 * Accessibility Service (which schedules and fires the warnings), the Dart
 * editor and this notifier all see one source of truth.
 *
 * Adaptations: the original's custom `RemoteViews` progress layout (three
 * colour-bucketed bars) becomes a framework notification with a single
 * progress bar — this project ships no notification layouts; the shown /
 * dismissed bookkeeping, per-type channels (including per-count vibration
 * channels), notification ids and the dismiss receiver are the original's.
 */

enum class UsageAlertType { SILENT, SOUND, VIBRATE }

data class UsageAlertStage(
    val id: String,
    val minutesBefore: Float,
    val type: UsageAlertType = UsageAlertType.SOUND,
    val vibrationCount: Int = 1,
)

object UsageWarningSettings {
    const val KEY_ENABLED = "enabled"
    const val KEY_STAGES = "stages"

    const val DEFAULT_ENABLED = true
    const val MIN_MINUTES_BEFORE = 0.1f
    const val MAX_MINUTES_BEFORE = 180f
    const val MAX_VIBRATION_COUNT = 10

    fun defaultStages(): List<UsageAlertStage> = listOf(
        UsageAlertStage(UUID.randomUUID().toString(), 15f, UsageAlertType.SILENT),
        UsageAlertStage(UUID.randomUUID().toString(), 5f, UsageAlertType.SOUND),
        UsageAlertStage(UUID.randomUUID().toString(), 1f, UsageAlertType.VIBRATE, vibrationCount = 1),
        UsageAlertStage(UUID.randomUUID().toString(), 0.5f, UsageAlertType.VIBRATE, vibrationCount = 3),
    )

    fun isEnabled(prefs: SharedPreferences): Boolean =
        prefs.getBoolean(KEY_ENABLED, DEFAULT_ENABLED)

    fun loadOrSeedStages(prefs: SharedPreferences): List<UsageAlertStage> {
        val raw = prefs.getString(KEY_STAGES, null) ?: return defaultStages().also {
            prefs.edit().putString(KEY_STAGES, encodeStages(it)).apply()
        }
        return decodeStages(raw)
    }

    fun decodeStages(json: String?): List<UsageAlertStage> {
        if (json == null) return defaultStages()
        if (json.isEmpty()) return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { i ->
                val obj = array.getJSONObject(i)
                UsageAlertStage(
                    id = obj.getString("id"),
                    // Bounds enforced on decode (v1.0.5 audit A-L4): the
                    // MIN/MAX constants were defined but never applied,
                    // so a hand-edited store could schedule warnings at
                    // absurd times. The Dart decoder clamps identically.
                    minutesBefore = obj.getDouble("minutes").toFloat()
                        .coerceIn(MIN_MINUTES_BEFORE, MAX_MINUTES_BEFORE),
                    type = try {
                        UsageAlertType.valueOf(obj.getString("type"))
                    } catch (e: Exception) {
                        Log.w("UsageWarningSettings", "Unknown stage type, using SOUND", e)
                        UsageAlertType.SOUND
                    },
                    vibrationCount = obj.optInt("vibrationCount", 1)
                        .coerceIn(0, MAX_VIBRATION_COUNT),
                )
            }
        } catch (e: Exception) {
            // Logged, not silent (audit A-L4): falling back to the
            // default stages changes user-visible behaviour.
            Log.w("UsageWarningSettings", "Malformed stages JSON, using defaults", e)
            defaultStages()
        }
    }

    fun encodeStages(stages: List<UsageAlertStage>): String {
        val array = JSONArray()
        stages.forEach { stage ->
            array.put(JSONObject().apply {
                put("id", stage.id)
                put("minutes", stage.minutesBefore.toDouble())
                put("type", stage.type.name)
                put("vibrationCount", stage.vibrationCount)
            })
        }
        return array.toString()
    }
}

object UsageWarningNotifier {
    private const val TAG = "UsageWarningNotifier"
    private const val CHANNEL_SILENT = "usage_warning_silent"
    private const val CHANNEL_SOUND = "usage_warning_sound"
    private const val STATE_PREFS = "usage_warning_state"

    private const val VIBRATE_PULSE_MS = 250L
    private const val VIBRATE_PAUSE_MS = 150L

    private fun channelIdFor(stage: UsageAlertStage): String = when (stage.type) {
        UsageAlertType.SILENT -> CHANNEL_SILENT
        UsageAlertType.SOUND -> CHANNEL_SOUND
        UsageAlertType.VIBRATE -> "usage_warning_vibrate_${stage.vibrationCount.coerceAtLeast(1)}"
    }

    private fun ensureChannel(context: Context, stage: UsageAlertStage) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channelId = channelIdFor(stage)
        if (manager.getNotificationChannel(channelId) != null) return

        val channel = when (stage.type) {
            UsageAlertType.SILENT -> NotificationChannel(
                channelId, context.getString(R.string.usage_channel_silent),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                setSound(null, null)
                enableVibration(false)
            }

            UsageAlertType.SOUND -> NotificationChannel(
                channelId, context.getString(R.string.usage_channel_sound),
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                enableVibration(false)
            }

            UsageAlertType.VIBRATE -> NotificationChannel(
                channelId,
                context.getString(
                    R.string.usage_channel_vibrate,
                    stage.vibrationCount.coerceAtLeast(1),
                ),
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                setSound(null, null)
                enableVibration(true)
                vibrationPattern = buildVibrationPattern(stage.vibrationCount)
            }
        }
        channel.description = context.getString(R.string.usage_channel_description)
        manager.createNotificationChannel(channel)
    }

    private fun buildVibrationPattern(count: Int): LongArray {
        val n = count.coerceAtLeast(1)
        val pattern = LongArray(n * 2)
        for (i in 0 until n) {
            pattern[i * 2] = if (i == 0) 0L else VIBRATE_PAUSE_MS
            pattern[i * 2 + 1] = VIBRATE_PULSE_MS
        }
        return pattern
    }

    fun notificationIdFor(key: String, stageId: String): Int = "$key:$stageId".hashCode()

    fun hasBeenShown(context: Context, key: String, stageId: String): Boolean =
        statePrefs(context).getBoolean(shownKey(key, stageId), false)

    fun markShown(context: Context, key: String, stageId: String) {
        statePrefs(context).edit().putBoolean(shownKey(key, stageId), true).apply()
    }

    fun isDismissed(context: Context, key: String, stageId: String): Boolean =
        statePrefs(context).getBoolean(dismissedKey(key, stageId), false)

    fun markDismissed(context: Context, key: String, stageId: String) {
        statePrefs(context).edit().putBoolean(dismissedKey(key, stageId), true).apply()
    }

    fun reset(context: Context, key: String, stageId: String) {
        statePrefs(context).edit()
            .remove(shownKey(key, stageId))
            .remove(dismissedKey(key, stageId))
            .apply()
    }

    fun resetAll(context: Context) {
        statePrefs(context).edit().clear().apply()
    }

    fun cancel(context: Context, key: String, stageId: String) {
        context.getSystemService(NotificationManager::class.java)
            ?.cancel(notificationIdFor(key, stageId))
    }

    fun showOrUpdate(
        context: Context,
        key: String,
        stage: UsageAlertStage,
        displayName: String,
        remainingMillis: Long,
        thresholdMillis: Long,
    ) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (!manager.areNotificationsEnabled()) {
            Log.d(TAG, "UsageWarning: showOrUpdate($key,${stage.id}) - notifications not enabled, skipping notify()")
            return
        }

        ensureChannel(context, stage)

        val clampedRemaining = remainingMillis.coerceIn(0L, thresholdMillis)
        val fraction = if (thresholdMillis > 0) clampedRemaining.toFloat() / thresholdMillis else 0f

        val totalSeconds = clampedRemaining / 1000
        val timeText = "%d:%02d".format(totalSeconds / 60, totalSeconds % 60)
        val progress = (fraction * 100).roundToInt().coerceIn(0, 100)

        val contentIntent = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val deleteIntent = PendingIntent.getBroadcast(
            context, notificationIdFor(key, stage.id),
            Intent(context, UsageWarningDismissReceiver::class.java).apply {
                putExtra(UsageWarningDismissReceiver.EXTRA_KEY, key)
                putExtra(UsageWarningDismissReceiver.EXTRA_STAGE_ID, stage.id)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = Notification.Builder(context, channelIdFor(stage))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(context.getString(R.string.usage_warning_title))
            .setContentText(context.getString(R.string.usage_warning_text, timeText, displayName))
            .setProgress(100, progress, false)
            .setContentIntent(contentIntent)
            .setDeleteIntent(deleteIntent)
            .setOnlyAlertOnce(true)
            .setAutoCancel(false)
            .setOngoing(false)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setPriority(Notification.PRIORITY_DEFAULT)
            .build()

        Log.d(
            TAG,
            "UsageWarning: showOrUpdate($key,${stage.id}) notify() id=${notificationIdFor(key, stage.id)} " +
                "remaining=${remainingMillis}ms fraction=$fraction timeText=$timeText",
        )
        try {
            manager.notify(notificationIdFor(key, stage.id), notification)
        } catch (e: SecurityException) {
            Log.w(TAG, "UsageWarning: could not post warning notification", e)
        }
    }

    private fun statePrefs(context: Context): SharedPreferences =
        context.getSharedPreferences(STATE_PREFS, Context.MODE_PRIVATE)

    private fun shownKey(key: String, stageId: String) = "shown_$key:$stageId"
    private fun dismissedKey(key: String, stageId: String) = "dismissed_$key:$stageId"
}

/** Marks a warning stage dismissed when the user swipes its notification away. */
class UsageWarningDismissReceiver : BroadcastReceiver() {
    companion object {
        const val EXTRA_KEY = "key"
        const val EXTRA_STAGE_ID = "stage_id"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val key = intent.getStringExtra(EXTRA_KEY) ?: return
        val stageId = intent.getStringExtra(EXTRA_STAGE_ID) ?: return
        UsageWarningNotifier.markDismissed(context, key, stageId)
    }
}
