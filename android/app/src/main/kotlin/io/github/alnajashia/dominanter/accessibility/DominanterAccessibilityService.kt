package io.github.alnajashia.dominanter.accessibility

import android.accessibilityservice.AccessibilityService
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.UserManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.github.alnajashia.dominanter.data.DominanterState
import io.github.alnajashia.dominanter.data.SettingsStore
import io.github.alnajashia.dominanter.data.SuspensionReason
import io.github.alnajashia.dominanter.data.TimeWindow
import io.github.alnajashia.dominanter.deviceowner.DominanterDeviceAdminReceiver
import io.github.alnajashia.dominanter.notifications.UsageAlertStage
import io.github.alnajashia.dominanter.notifications.UsageWarningNotifier
import io.github.alnajashia.dominanter.notifications.UsageWarningSettings
import java.time.LocalDate
import java.time.LocalTime
import java.util.concurrent.TimeUnit

/**
 * Runtime enforcement — a scoped v1 port of the original 1,546-line
 * `DechainerAccessibilityService` (Apache-2.0, warleysr/dechainer), keeping
 * its structure and semantics for the v1 scope (`docs/ARCHITECTURE.md` §6):
 *
 *  - per-app / per-group **time limits** (F9) with self-tracked usage —
 *    accumulated foreground sessions on `elapsedRealtime`, stored in
 *    `internal_usage_stats` / `group_usage_stats`, reset on date change.
 *    (Not `UsageStatsManager` — the original declared that permission but
 *    never used it.)
 *  - **allowed time windows** (F10), app ∩ group intersection, blocking
 *    outside the window;
 *  - **staged usage warnings** (F12): as the foreground app (or its group)
 *    approaches its limit, warnings fire through
 *    [UsageWarningNotifier] on the original's schedule/tick cadence —
 *    settings come from the `usage_warning_prefs` store, whose schema
 *    [UsageWarningSettings] shares with the Dart editor;
 *  - **active word blocking** (F14: forbidden word in the focused editable
 *    field of a target app, checked when typing stops, as in the original)
 *    and **passive word blocking** (F15: word anywhere on screen);
 *  - **activity blocking** (F18 plumbing: class-name match → BACK, plus the
 *    in-memory seen-activities log);
 *  - the **accessibility-loss lockdown** (F28): on unbind without the
 *    intentional-disable flag, suspend every controlled package and add
 *    `DISALLOW_INSTALL_APPS`; on connect, restore both.
 *
 * Deliberately NOT in this v1 service (per ARCH §6 scope calls): the NSFW
 * TFLite pipeline (F16/F17, v1.1), reopening cooldown enforcement (F11,
 * v1.1), colour-filter sync (F26, v1.1), install-watcher auto-suspension
 * (F6/F19/F20, v1.1 / not ported) and impulse suspension sync (F21 effects).
 * Focus (F25) is likewise not driven from here: its native runtime lives in
 * `focus/FocusSessionStore` + `focus/FocusService`, independent of this
 * service — as in the original, where `FocusMode` is independent of the
 * Accessibility Service too.
 *
 * This class contains **no Shizuku import** (ARCH §1.3).
 */
class DominanterAccessibilityService : AccessibilityService() {

    private val handler = Handler(Looper.getMainLooper())

    private var currentPackage: String? = null
    private var lastForegroundPackage: String? = null
    private var sessionStartElapsed: Long = 0L
    private var wasTypingActively: Boolean = false
    private var lastActiveTypedText: String = ""
    private var lastCheckDate: String = LocalDate.now().toString()

    private var targetPackages: Set<String> = emptySet()
    private var forbiddenPatterns: Map<String, Regex> = emptyMap()
    private var passiveForbiddenPatterns: Map<String, Map<String, Regex>> = emptyMap()

    // Staged usage warnings (F12), mirroring the original's fields
    // (DechainerAccessibilityService.kt:133-138).
    private var usageWarningEnabled: Boolean = UsageWarningSettings.DEFAULT_ENABLED
    private var usageWarningStages: List<UsageAlertStage> = emptyList()
    private var currentWarnKey: String? = null
    private var activeStageId: String? = null

    private val blockRunnable = Runnable { executeBlocking() }
    private val windowEndRunnable = Runnable { executeBlocking(outsideWindow = true) }
    private val warnTickRunnable = Runnable { tickUsageWarning() }

    /**
     * Per-store dispatch, mirroring the original's `prefsListener`
     * (DechainerAccessibilityService.kt:257-306): a limit change for the
     * CURRENT package re-arms the block callback and re-tracks it; a window
     * or group change additionally re-arms the window-end callback and
     * re-tracks unconditionally (group membership of the current package may
     * itself have changed); blocked-words changes only rebuild the patterns;
     * a usage-warning change reloads the warning settings, cancels the
     * active warning when warnings were switched off, and re-tracks the
     * current package (the original's usage-warning branch, :292-301).
     * (The original also syncs visual-blocking / colour-filter / impulse
     * state here — F16/F17/F26/F21 syncs are v1.1 and intentionally absent,
     * as in the rest of this service.)
     */
    private val prefsListener = SharedPreferences.OnSharedPreferenceChangeListener { prefs, key ->
        when (prefs) {
            SettingsStore.prefs(SettingsStore.PREFS_APP_LIMITS),
            SettingsStore.prefs(SettingsStore.PREFS_APP_WEEKLY_LIMITS) -> {
                if (key == currentPackage) retrackCurrent(removeWindowCallback = false)
            }
            SettingsStore.prefs(SettingsStore.PREFS_APP_WINDOWS),
            SettingsStore.prefs(SettingsStore.PREFS_APP_WEEKLY_WINDOWS) -> {
                if (key == currentPackage) retrackCurrent(removeWindowCallback = true)
            }
            SettingsStore.prefs(SettingsStore.PREFS_GROUPS) ->
                retrackCurrent(removeWindowCallback = true)
            SettingsStore.prefs(SettingsStore.PREFS_BLOCKED_WORDS) ->
                updateForbiddenPatterns()
            SettingsStore.prefs(SettingsStore.PREFS_USAGE_WARNING) -> {
                updateUsageWarningSettings()
                if (!usageWarningEnabled) {
                    cancelActiveUsageWarning()
                }
                currentPackage?.let { startTracking(it) }
            }
            // Activity-blocker changes need no refresh: blocked activities are
            // read live from SettingsStore on every window-state event.
        }
    }

    /** Re-arms tracking for the foreground app after its limits/windows/group changed. */
    private fun retrackCurrent(removeWindowCallback: Boolean) {
        val pkg = currentPackage ?: return
        handler.removeCallbacks(blockRunnable)
        if (removeWindowCallback) handler.removeCallbacks(windowEndRunnable)
        startTracking(pkg)
    }

    private val watchedPrefs = listOf(
        SettingsStore.PREFS_APP_LIMITS,
        SettingsStore.PREFS_APP_WEEKLY_LIMITS,
        SettingsStore.PREFS_APP_WINDOWS,
        SettingsStore.PREFS_APP_WEEKLY_WINDOWS,
        SettingsStore.PREFS_GROUPS,
        SettingsStore.PREFS_BLOCKED_WORDS,
        SettingsStore.PREFS_ACTIVITY_BLOCKER,
        SettingsStore.PREFS_USAGE_WARNING,
    )

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    // Mirror the original (DechainerAccessibilityService.kt:227-249):
                    // stash the foreground package so SCREEN_ON can resume it.
                    lastForegroundPackage = currentPackage
                    stopTrackingAndSave(screenOff = true)
                    currentPackage = null
                }
                Intent.ACTION_SCREEN_ON -> {
                    // Resume accounting for the app that was in front when the
                    // screen went off — without this, usage between unlock and
                    // the next window-state event goes unaccounted (fail-open).
                    // (The original also calls syncColorFilters() here — F26,
                    // v1.1, intentionally absent.)
                    lastForegroundPackage?.let {
                        currentPackage = it
                        sessionStartElapsed = SystemClock.elapsedRealtime()
                        checkDateReset()
                        startTracking(it)
                    }
                }
                Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED -> checkDateReset()
            }
        }
    }

    companion object {
        const val MAX_SCREEN_TEXT = 64_000

        /** The original's warning re-check cadence (DechainerAccessibilityService.kt:403). */
        private const val USAGE_WARNING_TICK_INTERVAL_MS = 2000L

        data class ActivityLog(
            val packageName: String,
            val className: String,
            val timestamp: Long = System.currentTimeMillis(),
        )

        /** In-memory seen-activities log (F18), as in the original's companion object. */
        val accessedActivities: MutableList<ActivityLog> = mutableListOf()

        private fun addLog(packageName: String, className: String) {
            synchronized(accessedActivities) {
                accessedActivities.removeIf { it.packageName == packageName && it.className == className }
                accessedActivities.add(0, ActivityLog(packageName, className))
                while (accessedActivities.size > 100) accessedActivities.removeAt(accessedActivities.lastIndex)
            }
        }
    }

    // ---------------------------------------------------------------- lifecycle

    override fun onServiceConnected() {
        super.onServiceConnected()
        DominanterState.accessibilityServiceRunning = true
        SettingsStore.init(applicationContext)
        lastCheckDate = LocalDate.now().toString()
        SettingsStore.resetUsageIfNewDay(lastCheckDate)

        watchedPrefs.forEach {
            SettingsStore.prefs(it).registerOnSharedPreferenceChangeListener(prefsListener)
        }
        updateForbiddenPatterns()
        updateUsageWarningSettings()

        val screenFilter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
        }
        registerReceiver(screenReceiver, screenFilter)

        // Restore after a previous lockdown (original onServiceConnected semantics):
        // un-suspend the controlled packages and lift the install block.
        // v1.0.5 fix #6: this privileged work runs OFF the main thread
        // (it used to block the service's connect callback), and it is
        // skipped entirely while a removal teardown is in progress —
        // the teardown performs the release itself, in order.
        if (!SettingsStore.isRemovalInProgress()) {
            val appContext = applicationContext
            Thread {
                val controlled = SettingsStore.controlledPackages()
                if (controlled.isNotEmpty()) {
                    suspendPackages(controlled.toTypedArray(), suspend = false)
                }
                val dpm = appContext.getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
                val admin = ComponentName(appContext, DominanterDeviceAdminReceiver::class.java)
                if (dpm.isAdminActive(admin)) {
                    try {
                        dpm.clearUserRestriction(admin, UserManager.DISALLOW_INSTALL_APPS)
                    } catch (_: Exception) { /* not owner — nothing to clear */ }
                }
            }.start()
        }

        emitState()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        runCatching { unregisterReceiver(screenReceiver) }
        watchedPrefs.forEach {
            runCatching {
                SettingsStore.prefs(it).unregisterOnSharedPreferenceChangeListener(prefsListener)
            }
        }
        stopTrackingAndSave()
        DominanterState.accessibilityServiceRunning = false

        // F28 — fail closed on accessibility loss, unless this disable was
        // intentional (armed via setAccessibilityEnabled(false), the original's
        // prepareServiceDisable() guard).
        //
        // v1.0.5 fix #6: NEVER fire while a removal teardown is in
        // progress. This callback runs on the main thread, and the
        // lockdown below is heavy synchronous privileged work —
        // suspending every controlled package and adding
        // DISALLOW_INSTALL_APPS. When the unbind is caused by the
        // system tearing the app down (above all: an uninstall in
        // flight), that work lands inside the package manager's own
        // removal operation and wedges system_server — the device
        // froze on uninstall until the watchdog rebooted it. Removal
        // disarms this path FIRST, before anything stops.
        if (!SettingsStore.isRemovalInProgress() &&
            !SettingsStore.consumeIntentionalAccessibilityDisable()
        ) {
            val controlled = SettingsStore.controlledPackages()
            if (controlled.isNotEmpty()) {
                suspendPackages(
                    controlled.toTypedArray(),
                    suspend = true,
                    reason = SuspensionReason.ACCESSIBILITY_DISABLED,
                )
            }
            val dpm = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val admin = ComponentName(this, DominanterDeviceAdminReceiver::class.java)
            if (dpm.isAdminActive(admin)) {
                try {
                    dpm.addUserRestriction(admin, UserManager.DISALLOW_INSTALL_APPS)
                } catch (_: Exception) { /* not owner — lockdown is best-effort without it */ }
            }
            DominanterState.eventSink?.invoke(
                "accessibilityStatus",
                mapOf("controlledPackagesSuspended" to controlled.isNotEmpty()),
            )
            startActivity(
                Intent(this, AccessibilityRequestActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                },
            )
        }
        emitState()
        return super.onUnbind(intent)
    }

    override fun onInterrupt() {
        handler.removeCallbacks(blockRunnable)
        handler.removeCallbacks(windowEndRunnable)
        handler.removeCallbacks(warnTickRunnable)
    }

    private fun emitState() {
        DominanterState.eventSink?.invoke(
            "accessibilityStateChanged",
            mapOf(
                "isEnabled" to DominanterState.accessibilityServiceRunning,
                "isServiceRunning" to DominanterState.accessibilityServiceRunning,
            ),
        )
    }

    // ---------------------------------------------------------------- events

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.packageName == packageName) return

        if (event.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        ) {
            checkActiveBlocking()
        }

        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val newPackage = event.packageName?.toString() ?: return
            val className = event.className?.toString() ?: return
            if (newPackage == "com.android.systemui") return
            if (className.contains("InputMethodService", ignoreCase = true) ||
                className.contains("SoftInputWindow", ignoreCase = true)
            ) return

            if (newPackage != currentPackage) {
                stopTrackingAndSave()
                currentPackage = newPackage
                sessionStartElapsed = SystemClock.elapsedRealtime()
                checkDateReset()
                startTracking(newPackage)
                wasTypingActively = false
                lastActiveTypedText = ""
            }

            if (className.contains("Activity", ignoreCase = true)) {
                addLog(newPackage, className)
                if (SettingsStore.blockedActivities().contains(className)) {
                    performGlobalAction(GLOBAL_ACTION_BACK)
                }
            }
        } else if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            // Passive word blocking (F15).
            val pkg = currentPackage ?: return
            val patterns = passiveForbiddenPatterns[pkg] ?: return
            val screenText = buildScreenText(event) ?: return
            for ((word, regex) in patterns) {
                if (regex.containsMatchIn(screenText)) {
                    performGlobalAction(GLOBAL_ACTION_BACK)
                    showBlockedWordActivity(word)
                    return
                }
            }
        }
    }

    private fun buildScreenText(event: AccessibilityEvent): String? {
        val builder = StringBuilder()
        event.text?.forEach { builder.append(it).append(' ') }
        // Mirror the original (DechainerAccessibilityService.kt:749-767): walk
        // the EVENT SOURCE's subtree — the node the event actually came from —
        // not the whole active window. Fall back to the active window's root
        // only when the event carries no source.
        val source = event.source
        if (source != null) {
            traverse(source, builder)
            source.recycle()
        } else {
            val root = rootInActiveWindow
            if (root != null) {
                traverse(root, builder)
                root.recycle()
            }
        }
        return builder.toString().takeIf { it.isNotBlank() }
    }

    private fun traverse(node: AccessibilityNodeInfo?, builder: StringBuilder) {
        if (node == null || builder.length > MAX_SCREEN_TEXT) return
        node.text?.let { builder.append(it).append(' ') }
        node.contentDescription?.let { builder.append(it).append(' ') }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            traverse(child, builder)
            child?.recycle()
        }
    }

    // ---------------------------------------------------------------- word blocking (F14/F15)

    private fun updateForbiddenPatterns() {
        targetPackages = SettingsStore.wordTargetPackages()
        forbiddenPatterns = SettingsStore.blockedWords().associateWith { wordPattern(it) }
        passiveForbiddenPatterns = SettingsStore.passiveWordPackages().associateWith { pkg ->
            SettingsStore.passiveWordsFor(pkg).associateWith { wordPattern(it) }
        }
    }

    /**
     * The original's pattern (DechainerAccessibilityService.kt:353-356,
     * 368-371): Unicode letter/number/underscore lookarounds instead of ASCII
     * `\b`, so a forbidden word inside a longer non-ASCII word (e.g. a
     * Portuguese compound) does NOT match, while standalone words still do.
     */
    private fun wordPattern(word: String): Regex =
        Regex(
            "(?<![\\p{L}\\p{N}_])" + Regex.escape(word) + "(?![\\p{L}\\p{N}_])",
            RegexOption.IGNORE_CASE,
        )

    private fun checkForbiddenWord(text: String): String? {
        for ((word, regex) in forbiddenPatterns) {
            if (regex.containsMatchIn(text)) return word
        }
        return null
    }

    private data class ScreenExtraction(val text: String, val isTyping: Boolean)

    private fun extractEditableFieldsTextAndFocus(): ScreenExtraction {
        val root = rootInActiveWindow ?: return ScreenExtraction("", false)
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        root.recycle()
        val isTyping = focused?.isEditable == true
        val text = if (isTyping) focused?.text?.toString().orEmpty() else ""
        focused?.recycle()
        return ScreenExtraction(text, isTyping)
    }

    /**
     * Active blocking, with the original's exact nuance: the field content is
     * checked when typing *ends* (focus/activity transition), not per keystroke.
     */
    private fun checkActiveBlocking() {
        val pkg = currentPackage ?: return
        if (pkg !in targetPackages) return
        val extraction = extractEditableFieldsTextAndFocus()
        if (extraction.isTyping) {
            wasTypingActively = true
            lastActiveTypedText = extraction.text
            return
        }
        if (!wasTypingActively) return
        wasTypingActively = false
        val text = extraction.text.ifBlank { lastActiveTypedText }
        lastActiveTypedText = ""
        val forbiddenWord = checkForbiddenWord(text) ?: return
        performGlobalAction(GLOBAL_ACTION_BACK)
        showBlockedWordActivity(forbiddenWord)
    }

    private fun showBlockedWordActivity(word: String) {
        startActivity(
            Intent(this, BlockActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                putExtra(BlockActivity.EXTRA_VARIANT, BlockActivity.VARIANT_BLOCKED_WORD)
                putExtra(BlockActivity.EXTRA_WORD, word)
            },
        )
    }

    // ---------------------------------------------------------------- tracking (F9/F10)

    private data class TrackingConfig(
        val groupId: String?,
        val groupName: String?,
        val appLimitMinutes: Int,
        val groupLimitMinutes: Int,
        val windows: List<TimeWindow>,
    )

    private fun trackingConfigFor(pkg: String): TrackingConfig {
        val group = SettingsStore.groupForPackage(pkg)
        val appWindows = SettingsStore.timeWindowsFor(pkg).todayWindows()
        val appLimit = SettingsStore.timeLimitFor(pkg).todayMinutes()
        return if (group != null) {
            TrackingConfig(
                groupId = group.id,
                groupName = group.name,
                appLimitMinutes = appLimit,
                groupLimitMinutes = group.timeLimit.todayMinutes(),
                windows = TimeWindow.intersect(group.timeWindows.todayWindows(), appWindows),
            )
        } else {
            TrackingConfig(null, null, appLimit, 0, appWindows)
        }
    }

    private fun startTracking(pkg: String) {
        handler.removeCallbacks(warnTickRunnable)

        val config = trackingConfigFor(pkg)

        if (config.windows.isNotEmpty()) {
            val nowMinute = currentMinuteOfDay()
            val activeWindow = config.windows.firstOrNull { it.contains(nowMinute) }
            if (activeWindow == null) {
                executeBlocking(outsideWindow = true)
                return
            }
            handler.postDelayed(
                windowEndRunnable,
                TimeUnit.MINUTES.toMillis(activeWindow.minutesUntilEnd(nowMinute).toLong()),
            )
        }

        if (config.appLimitMinutes <= 0 && config.groupLimitMinutes <= 0) return

        var appRemaining: Long? = null
        var groupRemaining: Long? = null
        var limitReached = false

        if (config.appLimitMinutes > 0) {
            val remaining = TimeUnit.MINUTES.toMillis(config.appLimitMinutes.toLong()) -
                SettingsStore.usageMs(pkg)
            if (remaining <= 0) limitReached = true else appRemaining = remaining
        }
        if (config.groupId != null && config.groupLimitMinutes > 0) {
            val remaining = TimeUnit.MINUTES.toMillis(config.groupLimitMinutes.toLong()) -
                SettingsStore.groupUsageMs(config.groupId)
            if (remaining <= 0) limitReached = true else groupRemaining = remaining
        }
        if (limitReached) {
            executeBlocking()
            return
        }
        val remainingMillis = listOfNotNull(appRemaining, groupRemaining).minOrNull()
        if (remainingMillis != null) {
            handler.postDelayed(blockRunnable, remainingMillis)
        }

        scheduleUsageWarning(pkg, config, appRemaining, groupRemaining)
    }

    private fun stopTrackingAndSave(screenOff: Boolean = false) {
        handler.removeCallbacks(blockRunnable)
        handler.removeCallbacks(windowEndRunnable)
        handler.removeCallbacks(warnTickRunnable)
        val pkg = currentPackage ?: return
        if (sessionStartElapsed == 0L) return
        val config = trackingConfigFor(pkg)
        val sessionMillis = SystemClock.elapsedRealtime() - sessionStartElapsed
        if (config.appLimitMinutes > 0) {
            SettingsStore.addUsage(pkg, sessionMillis)
        }
        if (config.groupId != null && config.groupLimitMinutes > 0) {
            SettingsStore.addGroupUsage(config.groupId, sessionMillis)
        }
        sessionStartElapsed = 0
        if (screenOff) currentPackage = null
    }

    private fun executeBlocking(outsideWindow: Boolean = false) {
        val pkg = currentPackage ?: return
        val config = trackingConfigFor(pkg)
        stopTrackingAndSave()
        currentPackage = null

        if (!outsideWindow) {
            // Mirror the original (DechainerAccessibilityService.kt,
            // executeBlocking): a reached limit ends the warning countdown —
            // cancel every stage's notification for the app and its group.
            usageWarningStages.forEach { stage ->
                UsageWarningNotifier.cancel(applicationContext, pkg, stage.id)
                config.groupId?.let { UsageWarningNotifier.cancel(applicationContext, it, stage.id) }
            }
        }

        var displayName = appLabel(pkg)
        var displayLimit = config.appLimitMinutes
        if (!outsideWindow && config.groupId != null && config.groupLimitMinutes > 0) {
            val groupReached = SettingsStore.groupUsageMs(config.groupId) >=
                TimeUnit.MINUTES.toMillis(config.groupLimitMinutes.toLong())
            val appReached = config.appLimitMinutes > 0 &&
                SettingsStore.usageMs(pkg) >= TimeUnit.MINUTES.toMillis(config.appLimitMinutes.toLong())
            if (groupReached && !appReached) {
                displayName = config.groupName ?: displayName
                displayLimit = config.groupLimitMinutes
            }
        }

        val intent = Intent(this, BlockActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
            putExtra(
                BlockActivity.EXTRA_VARIANT,
                if (outsideWindow) BlockActivity.VARIANT_OUTSIDE_WINDOW else BlockActivity.VARIANT_TIME_UP,
            )
            putExtra(BlockActivity.EXTRA_APP_NAME, displayName)
            if (outsideWindow) {
                putStringArrayListExtra(
                    BlockActivity.EXTRA_WINDOWS,
                    ArrayList(config.windows.map { it.formatted() }),
                )
            } else {
                putExtra(BlockActivity.EXTRA_LIMIT, displayLimit)
            }
        }
        startActivity(intent)
    }

    // ---------------------------------------------------------------- usage warnings (F12)

    /**
     * The F12 engine, ported from the original
     * (DechainerAccessibilityService.kt:336-348, 1350-1445): settings are
     * re-read from the shared `usage_warning_prefs` store; [startTracking]
     * schedules the first tick for when the farthest stage is entered; the
     * tick (every [USAGE_WARNING_TICK_INTERVAL_MS]) recomputes the remaining
     * time from stored usage plus the live session's elapsed time, fires or
     * updates the entered stage's notification, and retires stages whose
     * window has passed. The warning key is the group id when the group's
     * limit is the binding one, else the package — as in the original.
     */
    private fun updateUsageWarningSettings() {
        val prefs = SettingsStore.prefs(SettingsStore.PREFS_USAGE_WARNING)
        usageWarningEnabled = UsageWarningSettings.isEnabled(prefs)
        usageWarningStages = UsageWarningSettings.loadOrSeedStages(prefs)
            .sortedByDescending { it.minutesBefore }
    }

    private fun cancelActiveUsageWarning() {
        val key = currentWarnKey ?: return
        val stageId = activeStageId ?: return
        UsageWarningNotifier.cancel(applicationContext, key, stageId)
    }

    private fun scheduleUsageWarning(
        pkg: String,
        config: TrackingConfig,
        appRemaining: Long?,
        groupRemaining: Long?,
    ) {
        currentWarnKey = null
        activeStageId = null
        if (!usageWarningEnabled || usageWarningStages.isEmpty()) return

        val useGroup = groupRemaining != null && config.groupId != null &&
            (appRemaining == null || groupRemaining < appRemaining)
        val key = when {
            useGroup -> config.groupId!!
            appRemaining != null -> pkg
            else -> return
        }
        val remaining = if (useGroup) groupRemaining!! else appRemaining!!

        currentWarnKey = key

        val farthestMillis = stageMillis(usageWarningStages.first())
        if (remaining > farthestMillis) {
            handler.postDelayed(warnTickRunnable, remaining - farthestMillis)
        } else {
            tickUsageWarning()
        }
    }

    private fun stageMillis(stage: UsageAlertStage): Long = (stage.minutesBefore * 60_000).toLong()

    private fun tickUsageWarning() {
        handler.removeCallbacks(warnTickRunnable)
        val pkg = currentPackage ?: return
        val key = currentWarnKey ?: return
        if (usageWarningStages.isEmpty()) return

        val config = trackingConfigFor(pkg)
        val elapsed = SystemClock.elapsedRealtime() - sessionStartElapsed
        val isGroupKey = config.groupId == key

        val remaining = when {
            isGroupKey && config.groupLimitMinutes > 0 ->
                TimeUnit.MINUTES.toMillis(config.groupLimitMinutes.toLong()) -
                    SettingsStore.groupUsageMs(key) - elapsed
            !isGroupKey && config.appLimitMinutes > 0 ->
                TimeUnit.MINUTES.toMillis(config.appLimitMinutes.toLong()) -
                    SettingsStore.usageMs(pkg) - elapsed
            else -> return
        }

        if (remaining <= 0) {
            activeStageId?.let { UsageWarningNotifier.cancel(applicationContext, key, it) }
            activeStageId = null
            return
        }

        val enteredStage = usageWarningStages.lastOrNull { remaining <= stageMillis(it) }

        if (enteredStage == null) {
            activeStageId?.let { staleId ->
                UsageWarningNotifier.cancel(applicationContext, key, staleId)
                UsageWarningNotifier.reset(applicationContext, key, staleId)
            }
            activeStageId = null
            val farthestMillis = stageMillis(usageWarningStages.first())
            handler.postDelayed(warnTickRunnable, (remaining - farthestMillis).coerceAtLeast(500L))
            return
        }

        if (enteredStage.id != activeStageId) {
            activeStageId?.let { UsageWarningNotifier.cancel(applicationContext, key, it) }
            activeStageId = enteredStage.id
        }

        if (!UsageWarningNotifier.isDismissed(applicationContext, key, enteredStage.id)) {
            if (!UsageWarningNotifier.hasBeenShown(applicationContext, key, enteredStage.id)) {
                UsageWarningNotifier.markShown(applicationContext, key, enteredStage.id)
            }
            val displayName = if (isGroupKey) config.groupName ?: key else appLabel(pkg)
            val barMillis = stageMillis(usageWarningStages.first())
            UsageWarningNotifier.showOrUpdate(
                applicationContext, key, enteredStage, displayName, remaining, barMillis,
            )
        }

        handler.postDelayed(warnTickRunnable, USAGE_WARNING_TICK_INTERVAL_MS)
    }

    // ---------------------------------------------------------------- helpers

    private fun suspendPackages(packages: Array<String>, suspend: Boolean, reason: SuspensionReason? = null) {
        val dpm = applicationContext.getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(applicationContext, DominanterDeviceAdminReceiver::class.java)
        if (!dpm.isAdminActive(admin)) return
        try {
            dpm.setPackagesSuspended(admin, packages, suspend)
        } catch (_: Exception) {
            return
        }
        if (suspend && reason != null) {
            packages.forEach { SettingsStore.logSuspension(it, reason) }
        }
    }

    private fun appLabel(pkg: String): String = try {
        packageManager.getApplicationInfo(pkg, 0).loadLabel(packageManager).toString()
    } catch (_: Exception) {
        pkg
    }

    private fun currentMinuteOfDay(): Int {
        val now = LocalTime.now()
        return now.hour * 60 + now.minute
    }

    private fun checkDateReset() {
        val today = LocalDate.now().toString()
        if (today != lastCheckDate) {
            lastCheckDate = today
            SettingsStore.resetUsageIfNewDay(today)
        }
    }
}
