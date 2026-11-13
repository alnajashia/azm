package com.alnajashia.azm.accessibility

import android.accessibilityservice.AccessibilityService
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.database.ContentObserver
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.UserManager
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.alnajashia.azm.data.AzmState
import com.alnajashia.azm.data.ColourMode
import com.alnajashia.azm.data.ColourModesController
import com.alnajashia.azm.data.ColourModesSettings
import com.alnajashia.azm.data.SealRules
import com.alnajashia.azm.data.SettingsStore
import com.alnajashia.azm.data.SuspensionReason
import com.alnajashia.azm.data.TimeWindow
import com.alnajashia.azm.data.VisualBlockingSettings
import com.alnajashia.azm.deviceowner.AzmDeviceAdminReceiver
import com.alnajashia.azm.focus.FocusSessionStore
import com.alnajashia.azm.notifications.UsageAlertStage
import com.alnajashia.azm.notifications.UsageWarningNotifier
import com.alnajashia.azm.notifications.UsageWarningSettings
import java.time.LocalDate
import java.time.LocalTime
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
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
 *  - **activity blocking** (F18, completed Batch C): class-name match →
 *    BACK (HOME fallback when BACK is swallowed), plus the in-memory
 *    seen-activities log; protected activities (launcher, system UI,
 *    Settings, in-call UI, Azm itself) can never be blocked;
 *  - **colour modes** (F26, completed Batch C): grayscale / night light
 *    / extra dim / inversion enforced through the seven daltonizer
 *    secure keys with save/restore, a content-observer re-enforcement
 *    loop, window schedules, per-app scope, and a night-light tint
 *    overlay on devices without a platform night light (see
 *    [ColourModesController] / [ColourModesSettings]);
 *  - the **accessibility-loss lockdown** (F28): on unbind without the
 *    intentional-disable flag, suspend every controlled package and add
 *    `DISALLOW_INSTALL_APPS`; on connect, restore both.
 *
 *  - **visual blocking** (F16/F17, added v1.0.6 at the user's order):
 *    in user-chosen apps, media regions on screen are classified
 *    on-device by the bundled MobileNetV2 NSFW model (see
 *    [NsfwContentDetector]); a detection closes the app, and repeated
 *    detections escalate to a timed suspension. Settings live in
 *    [VisualBlockingSettings]; inference runs on a dedicated
 *    single-thread executor, never on the main thread, and no screen
 *    content ever leaves the device.
 *
 * Deliberately NOT in this service (per ARCH §6 scope calls):
 * reopening cooldown enforcement (F11, v1.1), install-watcher
 * auto-suspension (F6/F19/F20, v1.1 / not ported) and impulse
 * suspension sync (F21 effects).
 * Focus (F25) is likewise not driven from here: its native runtime lives in
 * `focus/FocusSessionStore` + `focus/FocusService`, independent of this
 * service — as in the original, where `FocusMode` is independent of the
 * Accessibility Service too. (The colour-modes loop only READS the
 * focus phase, for `apply_during_focus`; it never drives focus.)
 *
 * This class contains **no Shizuku import** (ARCH §1.3).
 */
class AzmAccessibilityService : AccessibilityService() {

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

    // Colour modes (Batch C, C3 — GRAYSCALE_RESEARCH.md §6.2): the
    // enforcement loop state. The observer re-enforces when any of the
    // seven secure keys changes externally; the runnable re-arms the
    // loop at the next window boundary; the foreground package is
    // tracked apart from `currentPackage` (Dechainer keeps its own
    // `colorFilterForegroundPackage` for the same reason: the usage
    // tracker's package is not always the colour scope's package);
    // the overlay is the night-light tint on devices without a
    // platform night light.
    private var colourModesObserver: ContentObserver? = null
    private val colourModesSyncRunnable = Runnable { syncColourModes() }
    private var colourModesForegroundPackage: String? = null
    private var colourModesAppliedModes: Set<ColourMode> = emptySet()
    private var nightLightOverlay: NightLightOverlay? = null

    // Visual blocking (F16/F17, v1.0.6), mirroring the original's
    // fields (DechainerAccessibilityService.kt:115-156): a settings
    // snapshot reloaded on every prefs change, a lazily-created
    // detector living on a single-thread executor (the TFLite
    // interpreter is not thread-safe and must be created, used and
    // closed on that one thread), a scan throttle + in-flight flag,
    // and the pending escalation-release timers.
    private var visualConfig: VisualBlockingSettings.Config = VisualBlockingSettings.Config(
        enabled = false,
        targetPackages = VisualBlockingSettings.DEFAULT_TARGET_PACKAGES,
        categories = VisualBlockingSettings.DEFAULT_CATEGORIES,
        threshold = VisualBlockingSettings.DEFAULT_THRESHOLD,
        suspendEnabled = false,
        suspendBlockCount = VisualBlockingSettings.DEFAULT_SUSPEND_BLOCK_COUNT,
        suspendWindowMinutes = VisualBlockingSettings.DEFAULT_SUSPEND_WINDOW_MINUTES,
        suspendDurationMinutes = VisualBlockingSettings.DEFAULT_SUSPEND_DURATION_MINUTES,
    )
    private var visualDetector: NsfwContentDetector? = null
    private var visualExecutor: ExecutorService? = null
    @Volatile
    private var visualScanInFlight = false
    private var lastVisualScanElapsedMs = 0L
    private val visualReleases = HashMap<String, Runnable>()

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
     * A colour-modes or focus change re-syncs the colour filters — the
     * original's syncColorFilters() call in the same listener.
     * (The original also syncs visual-blocking / impulse state here —
     * F16/F17/F21 syncs are v1.1 and intentionally absent, as in the rest
     * of this service.)
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
            SettingsStore.prefs(SettingsStore.PREFS_VISUAL_BLOCKING) ->
                updateVisualBlockingSettings()
            SettingsStore.prefs(SettingsStore.PREFS_COLOUR_MODES),
            SettingsStore.prefs(SettingsStore.PREFS_FOCUS) -> syncColourModes()
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

    // ------------------------------------------------------------ colour modes (Batch C, C3)

    /**
     * The colour-modes enforcement loop, mirroring DeChainer's
     * `syncColorFilters` (DechainerAccessibilityService.kt:1140-1195):
     * compute the modes for the foreground package right now, enforce
     * their secure keys (or release when none apply), show or hide the
     * night-light overlay, and re-arm the boundary timer for the next
     * window start/end. Never throws: enforcement must never crash
     * the service.
     */
    private fun syncColourModes() {
        if (SettingsStore.isProtectionTornDown() || SettingsStore.isRemovalInProgress()) return
        try {
            val settings = ColourModesSettings.load()
            val modes = ColourModesSettings.modesToApply(
                config = settings,
                foregroundPackage = colourModesForegroundPackage ?: currentPackage,
                focusPhase = FocusSessionStore.isFocusPhase(),
            )
            if (modes.isEmpty()) {
                ColourModesController.release(applicationContext)
            } else {
                ColourModesController.enforce(
                    applicationContext,
                    ColourModesController.targetsFor(settings, modes),
                )
            }
            colourModesAppliedModes = modes
            // Night-light overlay: only on devices without a platform
            // night light, only while NIGHT_LIGHT applies. The platform
            // keys do nothing there — forcing them can black the screen.
            if (ColourMode.NIGHT_LIGHT in modes && !ColourModesController.platformNightLight) {
                if (nightLightOverlay == null) nightLightOverlay = NightLightOverlay(this)
                nightLightOverlay?.show(settings.nightLightTemperature, settings.nightLightIntensity)
            } else {
                nightLightOverlay?.hide()
            }
            // Re-arm the boundary timer for the next window start/end.
            handler.removeCallbacks(colourModesSyncRunnable)
            val delay = ColourModesSettings.millisUntilNextBoundary(
                ColourModesSettings.scheduledWindows(settings),
            )
            if (delay != null) handler.postDelayed(colourModesSyncRunnable, delay)
        } catch (e: Exception) {
            Log.e(TAG, "syncColourModes failed", e)
        }
    }

    /**
     * Foreground change for the colour scope (Dechainer's
     * `colorFilterForegroundPackage` tracking): the system UI, input
     * methods and Azm's own windows never reach this call (the event
     * handler returns early for them), so the package here is always a
     * real foreground app. A sync runs only when the scope depends on
     * the foreground app and the modes actually changed.
     */
    private fun onColourModesForegroundChanged(packageName: String) {
        if (packageName == colourModesForegroundPackage) return
        colourModesForegroundPackage = packageName
        val settings = ColourModesSettings.load()
        if (!ColourModesSettings.dependsOnForegroundApp(settings)) return
        val modes = ColourModesSettings.modesToApply(
            settings,
            packageName,
            focusPhase = FocusSessionStore.isFocusPhase(),
        )
        if (modes != colourModesAppliedModes) syncColourModes()
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
        SettingsStore.PREFS_VISUAL_BLOCKING,
        SettingsStore.PREFS_COLOUR_MODES,
        SettingsStore.PREFS_FOCUS,
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
                    // The colour filters re-sync here too (the original's
                    // syncColorFilters() call in the same branch).
                    lastForegroundPackage?.let {
                        currentPackage = it
                        sessionStartElapsed = SystemClock.elapsedRealtime()
                        checkDateReset()
                        startTracking(it)
                    }
                    syncColourModes()
                }
                Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED -> checkDateReset()
            }
        }
    }

    companion object {
        const val MAX_SCREEN_TEXT = 64_000

        private const val TAG = "AzmA11y"

        /** The original's warning re-check cadence (DechainerAccessibilityService.kt:403). */
        private const val USAGE_WARNING_TICK_INTERVAL_MS = 2000L

        /** The original's visual-scan throttle (DechainerAccessibilityService.kt:401). */
        private const val VISUAL_SCAN_INTERVAL_MS = 2000L

        // Media-region heuristics, the original's constants and
        // signals (DechainerAccessibilityService.kt:405-450): class-name
        // substrings, PT/EN accessibility vocabulary, Reddit post-card
        // description patterns, then a geometric fallback (large leaf
        // node with no text at all and a plausible photo/video aspect).
        private val VISUAL_MEDIA_CLASS_KEYWORDS = listOf(
            "Image", "Photo", "Video", "Media", "Player", "Gif", "TextureView", "SurfaceView", "WebView",
        )
        private val VISUAL_MEDIA_KEYWORDS = listOf(
            "imagem", "image", "picture", "foto", "photo", "vídeo", "video", "gif", "media", "mídia",
        )
        private val VISUAL_MEDIA_DESCRIPTION_PATTERNS = listOf(
            Regex("""^\d{1,2}\+,"""),
            Regex("postado (no|em)", RegexOption.IGNORE_CASE),
            Regex("posted (in|to)", RegexOption.IGNORE_CASE),
        )
        private const val VISUAL_FALLBACK_MIN_ASPECT = 0.4f
        private const val VISUAL_FALLBACK_MAX_ASPECT = 3.0f
        private const val VISUAL_FALLBACK_MAX_CANDIDATES = 5
        private const val VISUAL_MIN_MEDIA_SIZE_DP = 96

        data class ActivityLog(
            val packageName: String,
            val className: String,
            val timestamp: Long = System.currentTimeMillis(),
        )

        /** In-memory seen-activities log (F18), as in the original's companion object. */
        val accessedActivities: MutableList<ActivityLog> = mutableListOf()

        @Volatile var instance: AzmAccessibilityService? = null

        fun disableService() {
            instance?.let { s ->
                try {
                    s.disableSelf()
                } catch (e: Exception) {
                    Log.w(TAG, "disableSelf failed: ${e.message}")
                }
            }
        }

        /**
         * Asks the running service instance to re-sync colour modes
         * now (Batch C, C3 — the channel's `syncColourModes` method).
         * Returns false when the service is not running, so the caller
         * can say so honestly instead of pretending a sync happened.
         */
        fun requestColourModesSync(): Boolean {
            val service = instance ?: return false
            service.handler.post { service.syncColourModes() }
            return true
        }

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
        if (SettingsStore.isProtectionTornDown()) {
            disableSelf()
            return
        }
        instance = this
        AzmState.accessibilityServiceRunning = true
        SettingsStore.init(applicationContext)
        lastCheckDate = LocalDate.now().toString()
        SettingsStore.resetUsageIfNewDay(lastCheckDate)

        watchedPrefs.forEach {
            SettingsStore.prefs(it).registerOnSharedPreferenceChangeListener(prefsListener)
        }
        updateForbiddenPatterns()
        updateUsageWarningSettings()
        updateVisualBlockingSettings()
        restoreVisualSuspensions()

        // Colour modes (Batch C, C3): observe the seven secure keys so
        // an external change (another app, adb, the system itself)
        // re-enforces within a frame, then sync once now.
        colourModesObserver = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean) = syncColourModes()
        }.also { observer ->
            ColourModesController.observedUris.forEach { uri ->
                contentResolver.registerContentObserver(uri, false, observer)
            }
        }
        syncColourModes()

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
                val admin = ComponentName(appContext, AzmDeviceAdminReceiver::class.java)
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
        if (instance === this) instance = null
        runCatching { unregisterReceiver(screenReceiver) }
        watchedPrefs.forEach {
            runCatching {
                SettingsStore.prefs(it).unregisterOnSharedPreferenceChangeListener(prefsListener)
            }
        }
        stopTrackingAndSave()
        // Visual blocking teardown: pending escalation releases are
        // cancelled (their deadlines stay persisted, so
        // restoreVisualSuspensions() picks them up on reconnect), and
        // the detector is closed on its own executor thread, which is
        // then shut down — the interpreter is thread-confined.
        visualReleases.values.forEach { handler.removeCallbacks(it) }
        visualReleases.clear()
        val detectorToClose = visualDetector
        visualDetector = null
        val executorToStop = visualExecutor
        visualExecutor = null
        if (executorToStop != null) {
            if (detectorToClose != null) {
                executorToStop.execute { runCatching { detectorToClose.close() } }
            }
            executorToStop.shutdown()
        }
        // Colour-modes teardown (Batch C, C3): the observer comes off
        // FIRST, then the boundary timer, then the release — in this
        // order, or restoring a key would re-trigger the observer and
        // re-enforce the modes being released. The overlay hides last.
        // Releasing here is safe in every path: after a removal
        // teardown the saved set is already empty (a no-op), and on an
        // intentional accessibility disable the filter must come off
        // with the service, or the phone would stay grey with nothing
        // left to switch it off.
        colourModesObserver?.let { runCatching { contentResolver.unregisterContentObserver(it) } }
        colourModesObserver = null
        handler.removeCallbacks(colourModesSyncRunnable)
        ColourModesController.release(applicationContext)
        nightLightOverlay?.hide()
        nightLightOverlay = null
        AzmState.accessibilityServiceRunning = false

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
        // The admin-active check (v1.0.5 audit FIX-2): once Device Owner
        // has been removed, the admin component is inactive and every
        // lockdown effect below is a no-op anyway (suspendPackages is
        // admin-gated internally; the restriction add is guarded) — the
        // only live effect would be a stray AccessibilityRequestActivity
        // launch during the post-removal uninstall. With the admin
        // inactive there is no enforcement left to protect, so the whole
        // lockdown is skipped.
        val dpmForAdminCheck = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(this, AzmDeviceAdminReceiver::class.java)
        if (!SettingsStore.isProtectionTornDown() &&
            !SettingsStore.isRemovalInProgress() &&
            !SettingsStore.consumeIntentionalAccessibilityDisable() &&
            dpmForAdminCheck.isAdminActive(adminComponent)
        ) {
            val controlled = SettingsStore.controlledPackages()
            if (controlled.isNotEmpty()) {
                suspendPackages(
                    controlled.toTypedArray(),
                    suspend = true,
                    reason = SuspensionReason.ACCESSIBILITY_DISABLED,
                )
            }
            try {
                dpmForAdminCheck.addUserRestriction(
                    adminComponent,
                    UserManager.DISALLOW_INSTALL_APPS,
                )
            } catch (_: Exception) { /* not owner — lockdown is best-effort without it */ }
            AzmState.eventSink?.invoke(
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

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onInterrupt() {
        handler.removeCallbacks(blockRunnable)
        handler.removeCallbacks(windowEndRunnable)
        handler.removeCallbacks(warnTickRunnable)
        handler.removeCallbacks(colourModesSyncRunnable)
    }

    private fun emitState() {
        AzmState.eventSink?.invoke(
            "accessibilityStateChanged",
            mapOf(
                "isEnabled" to AzmState.accessibilityServiceRunning,
                "isServiceRunning" to AzmState.accessibilityServiceRunning,
            ),
        )
    }

    // ---------------------------------------------------------------- events

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (SettingsStore.isProtectionTornDown() || SettingsStore.isRemovalInProgress()) return
        if (event.packageName == packageName) return

        if (event.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        ) {
            checkActiveBlocking()
        }

        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            // Visual blocking (F16): scan the media on screen of a
            // target app (throttled + region-gated inside).
            val pkg = currentPackage
            if (pkg != null && visualConfig.enabled && pkg in visualConfig.targetPackages) {
                maybeScanVisualContent(pkg)
            }
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

                if (visualConfig.enabled && newPackage in visualConfig.targetPackages) {
                    warmUpVisualDetector()
                }
            }
            onColourModesForegroundChanged(newPackage)

            if (className.contains("Activity", ignoreCase = true)) {
                addLog(newPackage, className)
                if (SettingsStore.blockedActivities().contains(className) &&
                    !SettingsStore.isProtectedActivity(newPackage, className)
                ) {
                    // BACK first; if the activity swallows it (or has no
                    // back stack), HOME is the fallback — never leave the
                    // user staring at a blocked activity with no way out.
                    if (!performGlobalAction(GLOBAL_ACTION_BACK)) {
                        startActivity(
                            Intent(Intent.ACTION_MAIN)
                                .addCategory(Intent.CATEGORY_HOME)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                    }
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
                    // Seal rules (Phase D): a banned-word detection is
                    // recorded natively at detection time.
                    SealRules.recordEvent(SealRules.Trigger.BANNED_WORD, pkg)
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
        // Seal rules (Phase D): recorded natively at detection time.
        SealRules.recordEvent(SealRules.Trigger.BANNED_WORD, pkg)
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

    // ---------------------------------------------------------------- visual blocking (F16/F17)

    private fun updateVisualBlockingSettings() {
        visualConfig = VisualBlockingSettings.load()
    }

    /** The detector's executor, created lazily and confined to one thread. */
    private fun visualExecutor(): ExecutorService =
        visualExecutor ?: Executors.newSingleThreadExecutor { r ->
            Thread(r, "NsfwDetector")
        }.also { visualExecutor = it }

    private fun warmUpVisualDetector() {
        if (visualDetector != null) return
        val appContext = applicationContext
        visualExecutor().execute {
            if (visualDetector == null) {
                visualDetector = runCatching { NsfwContentDetector(appContext) }
                    .onFailure { Log.w(TAG, "NSFW detector init failed: ${it.message}") }
                    .getOrNull()
            }
        }
    }

    /**
     * Classifies the media currently on screen, throttled to at most
     * once every [VISUAL_SCAN_INTERVAL_MS] and never overlapping a scan
     * already in flight — target apps fire content-changed events
     * continuously while scrolling. A screenshot is only taken when
     * [findVisualMediaRegions] finds at least one candidate region,
     * since most content-changed events (text, votes, comments) have
     * nothing to classify. Mirrors the original's scan
     * (DechainerAccessibilityService.kt:806-895).
     */
    private fun maybeScanVisualContent(pkg: String) {
        if (SettingsStore.isProtectionTornDown() || SettingsStore.isRemovalInProgress()) return // disarmed during teardown
        if (visualScanInFlight) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastVisualScanElapsedMs < VISUAL_SCAN_INTERVAL_MS) return
        lastVisualScanElapsedMs = now
        visualScanInFlight = true

        // The tree walk makes many cross-process node calls — too slow
        // for the main thread — so the whole scan runs off it; only
        // the blocking reaction returns to main.
        Thread {
            val mediaRegions = findVisualMediaRegions()
            if (mediaRegions.isEmpty()) {
                visualScanInFlight = false
                return@Thread
            }
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(result: ScreenshotResult) {
                        val hardwareBitmap = Bitmap.wrapHardwareBuffer(
                            result.hardwareBuffer, result.colorSpace,
                        )
                        result.hardwareBuffer.close()
                        if (hardwareBitmap == null) {
                            Log.w(TAG, "NSFW scan: failed to wrap screenshot hardware buffer")
                            visualScanInFlight = false
                            return
                        }
                        val appContext = applicationContext
                        visualExecutor().execute {
                            try {
                                val softwareBitmap = hardwareBitmap.copy(
                                    Bitmap.Config.ARGB_8888, false,
                                )
                                hardwareBitmap.recycle()
                                val detector = visualDetector
                                    ?: runCatching { NsfwContentDetector(appContext) }
                                        .getOrNull()?.also { visualDetector = it }
                                if (detector == null || softwareBitmap == null) {
                                    softwareBitmap?.recycle()
                                    return@execute
                                }
                                val config = visualConfig
                                var maxUnsafeScore = 0f
                                for (region in mediaRegions) {
                                    val crop = cropToBitmap(softwareBitmap, region)
                                        ?: continue
                                    val scores = detector.predict(crop)
                                    crop.recycle()
                                    val unsafe = detector.unsafeScore(
                                        scores, config.categories,
                                    )
                                    if (unsafe > maxUnsafeScore) maxUnsafeScore = unsafe
                                    if (unsafe > config.threshold) break
                                }
                                softwareBitmap.recycle()
                                if (maxUnsafeScore > config.threshold) {
                                    handler.post {
                                        if (currentPackage == pkg &&
                                            pkg in visualConfig.targetPackages
                                        ) {
                                            executeVisualBlocking(pkg)
                                        }
                                    }
                                }
                            } catch (e: Exception) {
                                Log.w(TAG, "NSFW scan failed: ${e.message}")
                            } finally {
                                visualScanInFlight = false
                            }
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        Log.w(TAG, "NSFW scan: takeScreenshot failed, errorCode=$errorCode")
                        visualScanInFlight = false
                    }
                },
            )
        }.start()
    }

    /**
     * Walks the current window's accessibility tree looking for views
     * likely rendering an image/gif/video, so the classifier only ever
     * looks at actual media instead of the whole screen (the model
     * expects its subject to fill the frame). Signals, most specific
     * first: class name, accessibility text/description vocabulary,
     * Reddit's post-card pattern — then, only if none found anything,
     * the geometric fallback. Ported from the original's
     * findNsfwMediaRegions with its constants.
     */
    private fun findVisualMediaRegions(): List<Rect> {
        val root = rootInActiveWindow ?: return emptyList()
        val minSizePx = (VISUAL_MIN_MEDIA_SIZE_DP * resources.displayMetrics.density).toInt()
        val regions = mutableListOf<Rect>()
        val fallbackCandidates = mutableListOf<Rect>()

        fun traverse(node: AccessibilityNodeInfo?) {
            node ?: return
            val className = node.className?.toString().orEmpty()
            val description = node.contentDescription?.toString().orEmpty()
            val text = node.text?.toString().orEmpty()
            val rect = Rect()
            node.getBoundsInScreen(rect)
            val bigEnough = rect.width() >= minSizePx && rect.height() >= minSizePx

            val matchesClass = VISUAL_MEDIA_CLASS_KEYWORDS.any {
                className.contains(it, ignoreCase = true)
            }
            val matchesDescription = description.isNotEmpty() && (
                VISUAL_MEDIA_KEYWORDS.any { description.contains(it, ignoreCase = true) } ||
                    VISUAL_MEDIA_DESCRIPTION_PATTERNS.any { it.containsMatchIn(description) }
                )
            val matchesText = VISUAL_MEDIA_KEYWORDS.any {
                text.startsWith(it, ignoreCase = true)
            }

            if ((matchesClass || matchesDescription || matchesText) && bigEnough &&
                regions.none { it == rect }
            ) {
                regions.add(rect)
            } else if (node.childCount == 0 && description.isEmpty() && text.isEmpty() &&
                bigEnough
            ) {
                val aspect = rect.width().toFloat() / rect.height().toFloat()
                if (aspect in VISUAL_FALLBACK_MIN_ASPECT..VISUAL_FALLBACK_MAX_ASPECT &&
                    fallbackCandidates.none { it == rect }
                ) {
                    fallbackCandidates.add(rect)
                }
            }

            for (i in 0 until node.childCount) {
                val child = node.getChild(i)
                traverse(child)
                child?.recycle()
            }
        }
        traverse(root)
        root.recycle()

        if (regions.isEmpty() && fallbackCandidates.isNotEmpty()) {
            regions.addAll(
                fallbackCandidates
                    .sortedByDescending { it.width().toLong() * it.height() }
                    .take(VISUAL_FALLBACK_MAX_CANDIDATES),
            )
        }
        return regions
    }

    private fun cropToBitmap(source: Bitmap, rect: Rect): Bitmap? {
        val left = rect.left.coerceIn(0, source.width)
        val top = rect.top.coerceIn(0, source.height)
        val right = rect.right.coerceIn(left, source.width)
        val bottom = rect.bottom.coerceIn(top, source.height)
        val width = right - left
        val height = bottom - top
        if (width <= 0 || height <= 0) return null
        return try {
            Bitmap.createBitmap(source, left, top, width, height)
        } catch (e: Exception) {
            Log.w(TAG, "NSFW scan: failed to crop region $rect: ${e.message}")
            null
        }
    }

    /**
     * Reaction to the classifier flagging [pkg]'s screen (the
     * original's executeNsfwBlocking). Default: suspend and
     * immediately un-suspend the package — suspending force-closes
     * the app, un-suspending right after leaves the user free to
     * reopen it. With escalation on, once [pkg] has been blocked
     * `suspendBlockCount` times within `suspendWindowMinutes`, the
     * suspension is instead held for `suspendDurationMinutes`.
     */
    private fun executeVisualBlocking(pkg: String) {
        if (SettingsStore.isProtectionTornDown() || SettingsStore.isRemovalInProgress()) return // disarmed during teardown
        // A held escalation suspension swallows repeat detections:
        // suspending doesn't tear the window down instantly, and each
        // content-changed event would otherwise count as a fresh
        // block (and the default path would cut the suspension short).
        if (VisualBlockingSettings.isSuspended(pkg)) return

        // Seal rules (Phase D): the detection is recorded natively at
        // detection time, whatever the reaction below does.
        SealRules.recordEvent(SealRules.Trigger.VISUAL_DETECTION, pkg)

        val config = visualConfig
        if (config.suspendEnabled) {
            val shouldSuspend = VisualBlockingSettings.registerBlock(
                pkg, config.suspendBlockCount, config.suspendWindowMinutes,
            )
            if (shouldSuspend) {
                val until = VisualBlockingSettings.startSuspension(
                    pkg, config.suspendDurationMinutes,
                )
                suspendPackages(
                    arrayOf(pkg), suspend = true, reason = SuspensionReason.VISUAL_BLOCKING,
                )
                scheduleVisualRelease(pkg, until)
                showContentBlockedActivity(pkg, config.suspendDurationMinutes)
                return
            }
        }

        suspendPackages(arrayOf(pkg), suspend = true, reason = SuspensionReason.VISUAL_BLOCKING)
        suspendPackages(arrayOf(pkg), suspend = false)
        showContentBlockedActivity(pkg, 0)
    }

    /** Queues the automatic release of a held visual suspension. */
    private fun scheduleVisualRelease(pkg: String, untilMs: Long) {
        visualReleases.remove(pkg)?.let { handler.removeCallbacks(it) }
        val release = Runnable {
            visualReleases.remove(pkg)
            VisualBlockingSettings.endSuspension(pkg)
            if (!isHeldByOtherBlock(pkg)) {
                suspendPackages(arrayOf(pkg), suspend = false)
            }
        }
        visualReleases[pkg] = release
        handler.postDelayed(
            release,
            (untilMs - System.currentTimeMillis()).coerceAtLeast(0L),
        )
    }

    /**
     * Re-applies (or lifts) recorded visual suspensions after the
     * service is recreated — without this, a suspension whose release
     * timer died with the previous process would never be lifted.
     */
    private fun restoreVisualSuspensions() {
        if (SettingsStore.isProtectionTornDown() || SettingsStore.isRemovalInProgress()) return
        val now = System.currentTimeMillis()
        for ((pkg, until) in VisualBlockingSettings.activeSuspensions()) {
            if (until <= now) {
                VisualBlockingSettings.endSuspension(pkg)
                if (!isHeldByOtherBlock(pkg)) {
                    suspendPackages(arrayOf(pkg), suspend = false)
                }
            } else {
                suspendPackages(
                    arrayOf(pkg), suspend = true, reason = SuspensionReason.VISUAL_BLOCKING,
                )
                scheduleVisualRelease(pkg, until)
            }
        }
    }

    /**
     * Whether another native engine currently holds [pkg] suspended.
     * In this architecture the only other native holder is a focus
     * session's claim set (impulse suspensions are driven from the
     * Dart layer, which re-asserts its own recorded state — see
     * docs/FEATURE_v1.0.6.md for the documented edge).
     */
    private fun isHeldByOtherBlock(pkg: String): Boolean =
        FocusSessionStore.isActive() && pkg in FocusSessionStore.getApps()

    private fun showContentBlockedActivity(pkg: String, suspendedMinutes: Int) {
        startActivity(
            Intent(this, BlockActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                putExtra(BlockActivity.EXTRA_VARIANT, BlockActivity.VARIANT_CONTENT)
                putExtra(BlockActivity.EXTRA_APP_NAME, appLabel(pkg))
                putExtra(BlockActivity.EXTRA_SUSPENDED_MINUTES, suspendedMinutes)
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
        // Removal disarm (v1.0.5 field-failure fix): while a Device
        // Owner teardown runs, the tracking/blocking/warning engines
        // must be fully inert — no re-suspension after the teardown's
        // unsuspend step and no new warning notifications after its
        // notification-cancellation step.
        if (SettingsStore.isProtectionTornDown() || SettingsStore.isRemovalInProgress()) return
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
        if (SettingsStore.isProtectionTornDown() || SettingsStore.isRemovalInProgress()) return // disarmed during teardown
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
        if (SettingsStore.isProtectionTornDown() || SettingsStore.isRemovalInProgress()) return // disarmed during teardown
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
        if (suspend && (SettingsStore.isProtectionTornDown() || SettingsStore.isRemovalInProgress())) return
        val dpm = applicationContext.getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(applicationContext, AzmDeviceAdminReceiver::class.java)
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
