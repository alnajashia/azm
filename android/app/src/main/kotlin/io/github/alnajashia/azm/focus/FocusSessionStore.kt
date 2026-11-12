package io.github.alnajashia.azm.focus

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import android.util.Log
import io.github.alnajashia.azm.data.AzmState
import io.github.alnajashia.azm.data.SettingsStore
import io.github.alnajashia.azm.data.SuspensionReason
import io.github.alnajashia.azm.deviceowner.AzmDeviceAdminReceiver
import io.github.alnajashia.azm.notifications.FocusReceiver
import org.json.JSONObject

/**
 * Native focus-session engine — a port of the original `data/FocusMode.kt`
 * (plus its `FocusCycle`) from DeChainer (Apache-2.0, warleysr/dechainer),
 * adapted to this codebase's layering: state lives in the `focus_prefs`
 * store owned by [SettingsStore], suspensions/restrictions go through the
 * platform `DevicePolicyManager` with our admin component (the role
 * `DeviceAdmin` plays in the original), and phase changes are published on
 * the existing events bridge ([AzmState.eventSink]) as
 * `focusPhaseChanged`.
 *
 * A session is **data, not a process**: every entry point (channel call,
 * phase-end alarm, boot/time-change receiver, foreground-service tick)
 * funnels into [sync], which is idempotent. Deadlines use elapsed realtime
 * while the device stays up and the wall clock only across a reboot, so
 * moving the clock can't shorten a phase — the original's contract,
 * verbatim.
 *
 * Session config (durations, cycle count, auto-start, sound, vibration) is
 * snapshotted into the original's key names by [startSession]; the
 * suspension targets are read from the Dart-owned focus config JSON
 * (`focus_prefs`/`config`, written by `ConfigStore`) at start and likewise
 * snapshotted into the original's `suspended_apps` / `suspended_groups` /
 * `focus_restrictions` keys, so a running session's claim set is stable
 * even if the Dart config is edited mid-session.
 *
 * One structural divergence from the original, forced by our architecture:
 * the original's `release()` also leaves alone apps held by the impulse
 * lock or visual blocking (`isTrackedElsewhere`). Ours has no native
 * impulse/visual claim set (impulse suspensions are applied from Dart and
 * are not claim-tracked natively), so release acts on exactly this
 * session's own claim set — the safety property (never release what focus
 * did not claim) is preserved.
 */
object FocusSessionStore {
    private const val TAG = "FocusSessionStore"

    // Bounds and defaults, from the original FocusMode.kt.
    const val FOCUS_MIN_MINUTES = 5
    const val FOCUS_MAX_MINUTES = 120
    const val SHORT_BREAK_MIN_MINUTES = 1
    const val SHORT_BREAK_MAX_MINUTES = 30
    const val LONG_BREAK_MIN_MINUTES = 5
    const val LONG_BREAK_MAX_MINUTES = 60
    const val CYCLES_MIN = 2
    const val CYCLES_MAX = 8

    enum class Phase {
        FOCUS,
        SHORT_BREAK,
        LONG_BREAK,

        /** A break ran out without auto-start on: nothing is suspended until the next focus is started. */
        WAITING,
    }

    data class Status(
        val phase: Phase,
        val paused: Boolean,
        val releasedApps: Boolean,
        val remainingMillis: Long,
        val phaseDurationMillis: Long,
        val completedFocus: Int,
        val cyclesBeforeLongBreak: Int,
    )

    // Config keys — the original's names in focus_prefs.
    private const val KEY_FOCUS_MINUTES = "focus_minutes"
    private const val KEY_SHORT_BREAK_MINUTES = "short_break_minutes"
    private const val KEY_LONG_BREAK_MINUTES = "long_break_minutes"
    private const val KEY_CYCLES = "cycles_before_long_break"
    private const val KEY_AUTO_START_FOCUS = "auto_start_focus"
    private const val KEY_SOUND_ENABLED = "sound_enabled"
    private const val KEY_VIBRATION_ENABLED = "vibration_enabled"
    private const val KEY_APPS = "suspended_apps"
    private const val KEY_GROUPS = "suspended_groups"
    private const val KEY_RESTRICTIONS = "focus_restrictions"

    // Session keys — the original's names in focus_prefs.
    private const val KEY_PHASE = "phase"
    private const val KEY_PHASE_START_RTC = "phase_start_rtc"
    private const val KEY_PHASE_START_ELAPSED = "phase_start_elapsed"
    private const val KEY_PHASE_DURATION = "phase_duration"
    private const val KEY_PHASE_BOOT_COUNT = "phase_boot_count"
    private const val KEY_PAUSED_REMAINING = "paused_remaining"
    private const val KEY_PAUSE_RELEASES = "pause_releases"
    private const val KEY_COMPLETED_FOCUS = "completed_focus"
    private const val KEY_ACTIVE_SUSPENSION = "active_suspension"
    private const val KEY_ACTIVE_RESTRICTIONS = "active_restrictions"

    /** The Dart-owned config JSON key in the same store (ConfigStore). */
    private const val KEY_DART_CONFIG = "config"

    private fun prefs(): SharedPreferences = SettingsStore.prefs(SettingsStore.PREFS_FOCUS)

    private fun edit(block: SharedPreferences.Editor.() -> Unit) {
        prefs().edit().apply(block).apply()
    }

    // ------------------------------------------------------------ config

    fun getFocusMinutes(): Int =
        prefs().getInt(KEY_FOCUS_MINUTES, 25).coerceIn(FOCUS_MIN_MINUTES, FOCUS_MAX_MINUTES)

    fun getShortBreakMinutes(): Int =
        prefs().getInt(KEY_SHORT_BREAK_MINUTES, 5)
            .coerceIn(SHORT_BREAK_MIN_MINUTES, SHORT_BREAK_MAX_MINUTES)

    fun getLongBreakMinutes(): Int =
        prefs().getInt(KEY_LONG_BREAK_MINUTES, 15)
            .coerceIn(LONG_BREAK_MIN_MINUTES, LONG_BREAK_MAX_MINUTES)

    fun getCyclesBeforeLongBreak(): Int =
        prefs().getInt(KEY_CYCLES, 4).coerceIn(CYCLES_MIN, CYCLES_MAX)

    fun isAutoStartFocus(): Boolean = prefs().getBoolean(KEY_AUTO_START_FOCUS, false)

    fun isSoundEnabled(): Boolean = prefs().getBoolean(KEY_SOUND_ENABLED, true)

    fun isVibrationEnabled(): Boolean = prefs().getBoolean(KEY_VIBRATION_ENABLED, true)

    fun getApps(): Set<String> = prefs().getStringSet(KEY_APPS, emptySet()) ?: emptySet()

    fun getGroupIds(): Set<String> = prefs().getStringSet(KEY_GROUPS, emptySet()) ?: emptySet()

    fun getFocusRestrictions(): Set<String> =
        prefs().getStringSet(KEY_RESTRICTIONS, emptySet()) ?: emptySet()

    fun getAllTargetApps(): Set<String> {
        val groupIds = getGroupIds()
        val fromGroups = if (groupIds.isEmpty()) {
            emptySet()
        } else {
            SettingsStore.groups().filter { it.id in groupIds }
                .flatMap { it.packageNames }.toSet()
        }
        return getApps() + fromGroups
    }

    /**
     * Reads the suspension targets out of the Dart-owned focus config JSON
     * (`FocusConfig.toJson`: `suspendApps`, `suspendGroups`, `restrictions`).
     * Any parse failure yields empty sets — a session with no targets is
     * valid (timer only), a guessed target set would not be.
     */
    private fun dartConfigTargets(): Triple<Set<String>, Set<String>, Set<String>> {
        val raw = prefs().getString(KEY_DART_CONFIG, null) ?: return Triple(emptySet(), emptySet(), emptySet())
        return try {
            val json = JSONObject(raw)
            fun strings(key: String): Set<String> {
                val array = json.optJSONArray(key) ?: return emptySet<String>()
                return (0 until array.length()).map { array.optString(it) }
                    .filter { it.isNotEmpty() }.toSet()
            }
            Triple(strings("suspendApps"), strings("suspendGroups"), strings("restrictions"))
        } catch (e: Exception) {
            Log.w(TAG, "Unparseable Dart focus config; session will have no targets", e)
            Triple(emptySet(), emptySet(), emptySet())
        }
    }

    // ------------------------------------------------------------ channel entry points

    /**
     * The `startFocusSession` channel method: snapshots the (clamped)
     * config and the current Dart-config targets, tries the original's
     * device-owner notification-permission grant, and starts a focus phase
     * — the original's `startFocus`, which keeps the completed count when a
     * session is already active and resets it otherwise.
     */
    fun startSession(
        context: Context,
        focusMinutes: Int,
        breakMinutes: Int,
        longBreakMinutes: Int,
        cycles: Int,
        autoStartFocus: Boolean,
        soundEnabled: Boolean,
        vibrationEnabled: Boolean,
    ) {
        val (apps, groups, restrictions) = dartConfigTargets()
        edit {
            putInt(KEY_FOCUS_MINUTES, focusMinutes.coerceIn(FOCUS_MIN_MINUTES, FOCUS_MAX_MINUTES))
            putInt(KEY_SHORT_BREAK_MINUTES, breakMinutes.coerceIn(SHORT_BREAK_MIN_MINUTES, SHORT_BREAK_MAX_MINUTES))
            putInt(KEY_LONG_BREAK_MINUTES, longBreakMinutes.coerceIn(LONG_BREAK_MIN_MINUTES, LONG_BREAK_MAX_MINUTES))
            putInt(KEY_CYCLES, cycles.coerceIn(CYCLES_MIN, CYCLES_MAX))
            putBoolean(KEY_AUTO_START_FOCUS, autoStartFocus)
            putBoolean(KEY_SOUND_ENABLED, soundEnabled)
            putBoolean(KEY_VIBRATION_ENABLED, vibrationEnabled)
            putStringSet(KEY_APPS, apps)
            putStringSet(KEY_GROUPS, groups)
            putStringSet(KEY_RESTRICTIONS, restrictions)
        }
        grantNotificationPermission(context)
        startFocus(context)
    }

    fun startFocus(context: Context) {
        if (!isActive()) edit { putInt(KEY_COMPLETED_FOCUS, 0) }
        enterPhase(context, Phase.FOCUS)
    }

    fun skipBreak(context: Context) {
        val phase = currentPhase() ?: return
        if (phase != Phase.SHORT_BREAK && phase != Phase.LONG_BREAK) return
        if (phase == Phase.LONG_BREAK) edit { putInt(KEY_COMPLETED_FOCUS, 0) }
        enterPhase(context, Phase.FOCUS)
    }

    /** With [releaseApps] the apps come back too, so callers gate that one behind the recovery code. */
    fun pause(context: Context, releaseApps: Boolean) {
        if (!isTicking()) return
        edit {
            putLong(KEY_PAUSED_REMAINING, remainingMillis(context).coerceAtLeast(0L))
            putBoolean(KEY_PAUSE_RELEASES, releaseApps)
        }
        sync(context)
    }

    fun resume(context: Context) {
        val p = prefs()
        if (!p.contains(KEY_PAUSED_REMAINING)) return
        val remaining = p.getLong(KEY_PAUSED_REMAINING, 0L)
        val elapsedSoFar = p.getLong(KEY_PHASE_DURATION, 0L) - remaining
        // Re-anchor the start so the phase ends `remaining` from now and the progress picks up where it was.
        edit {
            remove(KEY_PAUSED_REMAINING)
            remove(KEY_PAUSE_RELEASES)
            putLong(KEY_PHASE_START_RTC, System.currentTimeMillis() - elapsedSoFar)
            putLong(KEY_PHASE_START_ELAPSED, SystemClock.elapsedRealtime() - elapsedSoFar)
            putInt(KEY_PHASE_BOOT_COUNT, bootCount(context))
        }
        sync(context)
    }

    /** Outside [Phase.WAITING] this loosens the session, so callers gate it behind the recovery code. */
    fun stop(context: Context) {
        edit {
            remove(KEY_PHASE)
            remove(KEY_PHASE_START_RTC)
            remove(KEY_PHASE_START_ELAPSED)
            remove(KEY_PHASE_DURATION)
            remove(KEY_PHASE_BOOT_COUNT)
            remove(KEY_PAUSED_REMAINING)
            remove(KEY_PAUSE_RELEASES)
            remove(KEY_COMPLETED_FOCUS)
        }
        releaseSuspension(context)
        releaseRestrictions(context)
        cancelAlarm(context)
        FocusStatusNotifier.cancel(context)
        emitPhaseChanged("idle")
    }

    // ------------------------------------------------------------ state

    fun isActive(): Boolean = currentPhase() != null

    /**
     * Whether the session is in a focus phase right now (Batch C:
     * the colour-modes `apply_during_focus` trigger). A paused focus
     * phase still counts — the session has not ended, only paused —
     * and breaks never count. Deliberately broader than
     * [isEnforcing]: grayscale during a paused focus phase is the
     * safe direction, and a break is when the filter must come off.
     */
    fun isFocusPhase(): Boolean = currentPhase() == Phase.FOCUS

    private fun currentPhase(): Phase? =
        prefs().getString(KEY_PHASE, null)?.let { runCatching { Phase.valueOf(it) }.getOrNull() }

    private fun isPaused(): Boolean = prefs().contains(KEY_PAUSED_REMAINING)

    private fun isTicking(): Boolean {
        val phase = currentPhase() ?: return false
        return phase != Phase.WAITING && !isPaused()
    }

    private fun isReleasedPause(): Boolean = prefs().getBoolean(KEY_PAUSE_RELEASES, false)

    private fun isEnforcing(): Boolean =
        currentPhase() == Phase.FOCUS && !(isPaused() && isReleasedPause())

    fun getStatus(context: Context): Status? {
        val phase = currentPhase() ?: return null
        val p = prefs()
        val paused = isPaused()
        return Status(
            phase = phase,
            paused = paused,
            releasedApps = paused && isReleasedPause(),
            remainingMillis = when {
                phase == Phase.WAITING -> 0L
                paused -> p.getLong(KEY_PAUSED_REMAINING, 0L)
                else -> remainingMillis(context).coerceAtLeast(0L)
            },
            phaseDurationMillis = p.getLong(KEY_PHASE_DURATION, 0L),
            completedFocus = p.getInt(KEY_COMPLETED_FOCUS, 0),
            cyclesBeforeLongBreak = getCyclesBeforeLongBreak(),
        )
    }

    /** What was actually suspended — releasing acts on this, since the configured list may have changed. */
    fun getActiveSuspension(): Set<String> =
        prefs().getStringSet(KEY_ACTIVE_SUSPENSION, emptySet()) ?: emptySet()

    fun getActiveRestrictions(): Set<String> =
        prefs().getStringSet(KEY_ACTIVE_RESTRICTIONS, emptySet()) ?: emptySet()

    /**
     * The wire shape of the focus channel contract
     * (`startFocusSession` result / `getFocusSession`): `phase` is one of
     * `waiting|focus|shortBreak|longBreak|paused|idle`; when paused, the
     * underlying phase is reported via `pausedFrom` and `deadlineElapsedMs`
     * is the nominal (pre-pause) deadline. Null when no session exists.
     */
    fun stateMap(context: Context): Map<String, Any?>? {
        val phase = currentPhase() ?: return null
        val p = prefs()
        val paused = isPaused()
        val startElapsed = p.getLong(KEY_PHASE_START_ELAPSED, 0L)
        val duration = p.getLong(KEY_PHASE_DURATION, 0L)
        return mapOf(
            "phase" to if (paused) "paused" else wirePhase(phase),
            "phaseStartedElapsedMs" to startElapsed,
            "phaseDurationMs" to duration,
            "completedFocusInCycle" to p.getInt(KEY_COMPLETED_FOCUS, 0),
            "pausedFrom" to if (paused) wirePhase(phase) else null,
            "deadlineElapsedMs" to startElapsed + duration,
        )
    }

    private fun wirePhase(phase: Phase): String = when (phase) {
        Phase.FOCUS -> "focus"
        Phase.SHORT_BREAK -> "shortBreak"
        Phase.LONG_BREAK -> "longBreak"
        Phase.WAITING -> "waiting"
    }

    private fun emitPhaseChanged(wire: String) {
        AzmState.eventSink?.invoke("focusPhaseChanged", mapOf("phase" to wire))
    }

    // ------------------------------------------------------------ sync engine

    /** Advances a phase that ran out (with the alert), then re-applies suspension, alarm and notification. */
    fun sync(context: Context) {
        val ctx = context.applicationContext
        var phase = currentPhase() ?: run {
            if (getActiveSuspension().isNotEmpty()) releaseSuspension(ctx)
            if (getActiveRestrictions().isNotEmpty()) releaseRestrictions(ctx)
            return
        }

        if (isTicking() && remainingMillis(ctx) <= 0L) {
            val finished = phase
            phase = nextPhase(finished)
            Log.d(TAG, "Focus mode: $finished ran out, moving to $phase")
            startPhase(ctx, phase)
            alertPhaseEnded(ctx)
        }

        applyState(ctx)
    }

    fun syncIfDue(context: Context) {
        if (isTicking() && remainingMillis(context) <= 0L) sync(context)
    }

    private fun enterPhase(context: Context, phase: Phase) {
        val ctx = context.applicationContext
        startPhase(ctx, phase)
        applyState(ctx)
    }

    private fun applyState(context: Context) {
        applySuspension(context, enforce = isEnforcing())
        applyRestrictions(context, enforce = isEnforcing())
        scheduleAlarm(context)
        FocusStatusNotifier.showStatus(context)
    }

    private fun nextPhase(finished: Phase): Phase {
        val completed = prefs().getInt(KEY_COMPLETED_FOCUS, 0)
        val (next, newCompleted) = FocusCycle.next(
            finished = finished,
            completedFocus = completed,
            cyclesBeforeLongBreak = getCyclesBeforeLongBreak(),
            autoStartFocus = isAutoStartFocus(),
        )
        edit { putInt(KEY_COMPLETED_FOCUS, newCompleted) }
        return next
    }

    private fun startPhase(context: Context, phase: Phase) {
        val minutes = when (phase) {
            Phase.FOCUS -> getFocusMinutes()
            Phase.SHORT_BREAK -> getShortBreakMinutes()
            Phase.LONG_BREAK -> getLongBreakMinutes()
            Phase.WAITING -> 0
        }
        edit {
            remove(KEY_PAUSED_REMAINING)
            remove(KEY_PAUSE_RELEASES)
            putString(KEY_PHASE, phase.name)
            putLong(KEY_PHASE_START_RTC, System.currentTimeMillis())
            putLong(KEY_PHASE_START_ELAPSED, SystemClock.elapsedRealtime())
            putLong(KEY_PHASE_DURATION, minutes * 60_000L)
            putInt(KEY_PHASE_BOOT_COUNT, bootCount(context))
        }
        emitPhaseChanged(wirePhase(phase))
    }

    // After a reboot only the wall clock is left; re-anchoring on the new boot hands back to elapsed realtime.
    private fun remainingMillis(context: Context): Long {
        val p = prefs()
        val duration = p.getLong(KEY_PHASE_DURATION, 0L)
        val startElapsed = p.getLong(KEY_PHASE_START_ELAPSED, 0L)
        val nowElapsed = SystemClock.elapsedRealtime()

        if (p.getInt(KEY_PHASE_BOOT_COUNT, -1) == bootCount(context)) {
            return startElapsed + duration - nowElapsed
        }

        val remaining = p.getLong(KEY_PHASE_START_RTC, 0L) + duration - System.currentTimeMillis()
        edit {
            putLong(KEY_PHASE_START_ELAPSED, nowElapsed + remaining - duration)
            putInt(KEY_PHASE_BOOT_COUNT, bootCount(context))
        }
        return remaining
    }

    private fun bootCount(context: Context): Int =
        Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)

    // ------------------------------------------------------------ effects (DPM)

    private fun dpm(context: Context): DevicePolicyManager =
        context.getSystemService(DevicePolicyManager::class.java)

    private fun admin(context: Context): ComponentName =
        ComponentName(context, AzmDeviceAdminReceiver::class.java)

    // An app already suspended by something untracked (e.g. the user) is left unclaimed, so ending focus won't release it.
    private fun applySuspension(context: Context, enforce: Boolean) {
        if (!enforce) {
            releaseSuspension(context)
            return
        }

        val dpm = dpm(context)
        val admin = admin(context)
        if (!dpm.isAdminActive(admin)) return

        val targets = getAllTargetApps()
        val claimed = getActiveSuspension()

        val dropped = claimed - targets
        if (dropped.isNotEmpty()) release(context, dropped)

        val toClaim = targets.filter { pkg -> pkg in claimed || !isSuspended(dpm, admin, pkg) }
        val failed = if (toClaim.isEmpty()) {
            emptyArray()
        } else {
            try {
                dpm.setPackagesSuspended(admin, toClaim.toTypedArray(), true)
            } catch (e: Exception) {
                Log.w(TAG, "Focus mode: setPackagesSuspended failed", e)
                return
            }
        }

        val nowClaimed = toClaim.toSet() - failed.toSet()
        nowClaimed.forEach { pkg ->
            SettingsStore.logSuspension(pkg, SuspensionReason.FOCUS_MODE)
        }
        edit { putStringSet(KEY_ACTIVE_SUSPENSION, nowClaimed) }
        if (failed.isNotEmpty()) Log.w(TAG, "Focus mode: could not suspend ${failed.joinToString()}")
    }

    private fun releaseSuspension(context: Context) {
        val claimed = getActiveSuspension()
        edit { remove(KEY_ACTIVE_SUSPENSION) }
        if (claimed.isNotEmpty()) release(context, claimed)
    }

    private fun release(context: Context, packages: Set<String>) {
        val dpm = dpm(context)
        val admin = admin(context)
        if (!dpm.isAdminActive(admin)) return
        try {
            dpm.setPackagesSuspended(admin, packages.toTypedArray(), false)
        } catch (e: Exception) {
            Log.w(TAG, "Focus mode: could not release ${packages.joinToString()}", e)
        }
    }

    private fun isSuspended(dpm: DevicePolicyManager, admin: ComponentName, pkg: String): Boolean =
        try {
            dpm.isPackageSuspended(admin, pkg)
        } catch (_: Exception) {
            false
        }

    private fun applyRestrictions(context: Context, enforce: Boolean) {
        if (!enforce) {
            releaseRestrictions(context)
            return
        }

        val dpm = dpm(context)
        val admin = admin(context)
        if (!dpm.isDeviceOwnerApp(admin.packageName)) return

        val configured = getFocusRestrictions()
        val claimed = getActiveRestrictions()

        // Clear restrictions that were deselected while the session was running
        val dropped = claimed - configured
        if (dropped.isNotEmpty()) {
            dropped.forEach { key ->
                runCatching { dpm.clearUserRestriction(admin, key) }
            }
        }

        val currentDpmRestrictions = dpm.getUserRestrictions(admin)
        val newlyClaimed = mutableSetOf<String>()

        configured.forEach { key ->
            if (key in claimed) {
                // Already managed by our active session
            } else if (!currentDpmRestrictions.containsKey(key)) {
                // Not previously set in system -> apply and claim it so we can revert it later
                try {
                    dpm.addUserRestriction(admin, key)
                    newlyClaimed.add(key)
                } catch (e: Exception) {
                    Log.w(TAG, "Focus mode: could not add user restriction $key", e)
                }
            }
        }

        val nowClaimed = (claimed - dropped) + newlyClaimed
        edit { putStringSet(KEY_ACTIVE_RESTRICTIONS, nowClaimed) }
    }

    private fun releaseRestrictions(context: Context) {
        val claimed = getActiveRestrictions()
        edit { remove(KEY_ACTIVE_RESTRICTIONS) }
        if (claimed.isEmpty()) return

        val dpm = dpm(context)
        val admin = admin(context)
        if (!dpm.isDeviceOwnerApp(admin.packageName)) return

        claimed.forEach { key ->
            runCatching { dpm.clearUserRestriction(admin, key) }
                .onFailure { Log.w(TAG, "Focus mode: could not clear user restriction $key", it) }
        }
    }

    // ------------------------------------------------------------ alarm

    private fun alarmIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, 0,
        Intent(context, FocusReceiver::class.java).setAction(FocusReceiver.ACTION_PHASE_END),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun scheduleAlarm(context: Context) {
        if (!isTicking()) {
            cancelAlarm(context)
            return
        }
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val triggerAt = SystemClock.elapsedRealtime() + remainingMillis(context).coerceAtLeast(0L)
        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()
        if (canExact) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, alarmIntent(context))
        } else {
            alarmManager.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, alarmIntent(context))
        }
    }

    private fun cancelAlarm(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(alarmIntent(context))
    }

    // ------------------------------------------------------------ phase-end alert

    /** Sound and vibration only: the status notification itself moves on to the next phase's countdown. */
    fun alertPhaseEnded(context: Context) {
        if (isSoundEnabled()) playSound(context)
        if (isVibrationEnabled()) vibrate(context)
    }

    private fun vibrate(context: Context) {
        val vibrator = context.getSystemService(Vibrator::class.java) ?: return
        if (!vibrator.hasVibrator()) return
        try {
            vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 300, 200, 300), -1))
        } catch (e: Exception) {
            Log.w(TAG, "Focus mode: could not vibrate", e)
        }
    }

    private fun playSound(context: Context) {
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: return
        val ringtone = RingtoneManager.getRingtone(context, uri) ?: return
        ringtone.audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        try {
            ringtone.play()
            // Guards against a user-chosen default sound that's a whole song.
            Handler(Looper.getMainLooper()).postDelayed({ ringtone.stop() }, SOUND_MAX_MS)
        } catch (e: Exception) {
            Log.w(TAG, "Focus mode: could not play alert sound", e)
        }
    }

    // ------------------------------------------------------------ notification permission

    fun hasNotificationPermission(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return false
        if (!manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    /**
     * The original's device-owner grant (`FocusMode.grantNotificationPermission`):
     * when we are the device owner, grant `POST_NOTIFICATIONS` via policy and
     * immediately reset it to the default state — the permission stays granted
     * but revocable. Returns whether notifications are permitted afterwards.
     */
    fun tryGrantNotificationPermissionViaDpm(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return hasNotificationPermission(context)
        if (hasNotificationPermission(context)) return true
        val dpm = dpm(context)
        if (!dpm.isDeviceOwnerApp(context.packageName)) return false
        runCatching {
            listOf(
                DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED,
                DevicePolicyManager.PERMISSION_GRANT_STATE_DEFAULT,
            ).forEach { state ->
                dpm.setPermissionGrantState(
                    admin(context), context.packageName, Manifest.permission.POST_NOTIFICATIONS, state,
                )
            }
        }.onFailure { Log.w(TAG, "Focus mode: could not grant notification permission", it) }
        return hasNotificationPermission(context)
    }

    // Resetting to the default policy after granting keeps the permission granted but still revocable.
    private fun grantNotificationPermission(context: Context) {
        tryGrantNotificationPermissionViaDpm(context)
    }

    private const val SOUND_MAX_MS = 5_000L

    /** How long a phase-end handler should keep its process alive for the alert sound. */
    const val SOUND_KEEP_ALIVE_MS = SOUND_MAX_MS
}

/** The phase-cycle rules, ported verbatim from the original's `FocusCycle`. */
object FocusCycle {
    fun next(
        finished: FocusSessionStore.Phase,
        completedFocus: Int,
        cyclesBeforeLongBreak: Int,
        autoStartFocus: Boolean,
    ): Pair<FocusSessionStore.Phase, Int> = when (finished) {
        FocusSessionStore.Phase.FOCUS -> {
            val completed = completedFocus + 1
            if (completed >= cyclesBeforeLongBreak) {
                FocusSessionStore.Phase.LONG_BREAK to completed
            } else {
                FocusSessionStore.Phase.SHORT_BREAK to completed
            }
        }
        FocusSessionStore.Phase.SHORT_BREAK ->
            (if (autoStartFocus) FocusSessionStore.Phase.FOCUS else FocusSessionStore.Phase.WAITING) to completedFocus
        FocusSessionStore.Phase.LONG_BREAK ->
            (if (autoStartFocus) FocusSessionStore.Phase.FOCUS else FocusSessionStore.Phase.WAITING) to 0
        FocusSessionStore.Phase.WAITING -> FocusSessionStore.Phase.WAITING to completedFocus
    }
}
