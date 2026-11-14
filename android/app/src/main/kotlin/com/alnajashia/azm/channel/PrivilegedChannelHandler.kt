package com.alnajashia.azm.channel

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.alnajashia.azm.NotificationPermissionBridge
import com.alnajashia.azm.WindowSecurityBridge
import com.alnajashia.azm.accessibility.AzmAccessibilityService
import com.alnajashia.azm.data.AzmState
import com.alnajashia.azm.data.ColourMode
import com.alnajashia.azm.data.ColourModesController
import com.alnajashia.azm.data.ColourModesSettings
import com.alnajashia.azm.data.SealRules
import com.alnajashia.azm.data.SettingsStore
import com.alnajashia.azm.data.VisualBlockingSettings
import com.alnajashia.azm.data.SuspensionReason
import com.alnajashia.azm.deviceowner.DeviceOwnerManager
import com.alnajashia.azm.focus.FocusSchedule
import com.alnajashia.azm.focus.FocusScheduleManager
import com.alnajashia.azm.focus.FocusScheduleStorage
import com.alnajashia.azm.focus.FocusSessionStore
import com.alnajashia.azm.lockdown.LockdownStore
import com.alnajashia.azm.security.RecoveryStore
import com.alnajashia.azm.shizuku.ShizukuGateway
import com.alnajashia.azm.shizuku.ShizukuProvisioning
import java.time.LocalDate
import java.util.concurrent.Executors

/**
 * The single Kotlin endpoint of the platform contract
 * (`docs/ARCHITECTURE.md` §5): MethodChannel `azm/privileged`,
 * EventChannel `azm/privileged/events`, all 25 contract methods plus
 * the §8 enforcement-config extension methods (`get/setTimeLimit`,
 * `get/setTimeWindows`, `get/setGroups`, `get/setBlockedWords`,
 * `setPassiveWords`, `setWordAssignments` (Batch H merged write),
 * `generateRecoveryCode`) added when the Dart layer was built — §8.3 requires
 * channel-mediated SettingsStore writes, and the first Kotlin pass exposed
 * none of them, which made the Dart editors unable to persist anything.
 * Batch C adds `listInstalledBrowsers`, `get/setBlockedActivities`,
 * `getAccessedActivities` and `get/setColourModesConfig`,
 * `getColourModesStatus`, `syncColourModes`.
 *
 * This class contains no business logic: it validates arguments, dispatches
 * to [ShizukuProvisioning] / [DeviceOwnerManager] / [SettingsStore] /
 * [RecoveryStore] on a background executor (shell, DPM and PBKDF2 work never
 * block the platform thread), and maps every failure to the §5.4 taxonomy.
 */
class PrivilegedChannelHandler(
    private val appContext: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val executor = Executors.newCachedThreadPool { r ->
        Thread(r, "azm-privileged").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    // Tetris sounds (Batch I-C): one SoundPool for the challenge's
    // lifetime; created on first load, released by the view's dispose.
    private var tetrisSounds: com.alnajashia.azm.challenges.TetrisSounds? = null

    fun attach() {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    fun detach() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        ShizukuGateway.eventSink = null
        AzmState.eventSink = null
    }

    // ------------------------------------------------------------ EventChannel

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val emit: (String, Map<String, Any?>) -> Unit = { type, payload -> emitEvent(type, payload) }
        ShizukuGateway.eventSink = ShizukuGateway.EventSink { type, payload -> emit(type, payload) }
        AzmState.eventSink = emit
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        ShizukuGateway.eventSink = null
        AzmState.eventSink = null
    }

    private fun emitEvent(type: String, payload: Map<String, Any?>) {
        val sink = eventSink ?: return
        val event = mutableMapOf<String, Any?>("type" to type)
        event.putAll(payload)
        mainHandler.post { sink.success(event) }
    }

    // ------------------------------------------------------------ MethodChannel plumbing

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            try {
                val value = dispatch(call)
                mainHandler.post { result.success(value) }
            } catch (e: PrivException) {
                mainHandler.post { e.sendTo(result) }
            } catch (e: Exception) {
                val wrapped = PrivException.internal(e)
                mainHandler.post { wrapped.sendTo(result) }
            }
        }
    }

    private fun dispatch(call: MethodCall): Any? = when (call.method) {
        // Shizuku state & permission (provisioning layer)
        "getShizukuState" -> getShizukuState()
        "requestShizukuPermission" -> {
            ShizukuGateway.requestPermission(appContext)
            mapOf("requested" to true)
        }
        "installShizuku" -> mapOf("launched" to DeviceOwnerManager.installShizuku(appContext))
        // Device Owner provisioning & removal
        "provisionDeviceOwner" -> {
            val r = ShizukuProvisioning.provisionDeviceOwner(appContext)
            emitEvent("deviceOwnerChanged", mapOf("isDeviceOwner" to r.isDeviceOwner))
            mapOf(
                "isDeviceOwner" to r.isDeviceOwner,
                "pathUsed" to r.pathUsed,
                "commandOutput" to r.commandOutput,
            )
        }
        "removeDeviceOwner" -> {
            // SEAL refusal (v1.0.6 Phase D): while any user-defined
            // seal is active, removal refuses — evaluated natively
            // from live probes at attempt time. Batch C (C4) priority
            // order: the paper recovery code opens every lock, so a
            // live recovery session (correct code verified < 10 min
            // ago on both clocks — see RecoveryStore) bypasses the
            // seal entirely. Batch E review finding F-E2-1: a filed
            // forced removal whose 24-hour countdown is COMPLETE
            // bypasses it too — the 24-hour wait is itself the
            // anti-impulse proof, so a fresh seal (e.g. a focus session
            // started in the countdown's last minutes) must not strand
            // the user at the finish line. Without a session AND
            // without a due countdown, the seal still refuses.
            if (!RecoveryStore.isRecoverySessionActive(appContext) &&
                !RecoveryStore.isForcedRemovalDue(appContext)
            ) {
                SealRules.firstActiveSeal(appContext)?.let { throw PrivException.sealed(it) }
            }
            // v1.0.5 fix #6: the ordered teardown report (runs here, on
            // this handler's background executor — never the main thread).
            val report = DeviceOwnerManager.removeDeviceOwner(appContext)
            emitEvent("deviceOwnerChanged", mapOf("isDeviceOwner" to report.isDeviceOwner))
            report.toMap()
        }
        "isDeviceOwner" -> mapOf(
            "isDeviceOwner" to DeviceOwnerManager.isDeviceOwner(appContext),
            "isAdminActive" to DeviceOwnerManager.isAdminActive(appContext),
            // The forced-removal delay's single source of truth lives
            // natively (RecoveryStore.FORCED_REMOVAL_DELAY_HOURS); the
            // Dart side reads it from this state map.
            "forcedRemovalDelayHours" to RecoveryStore.FORCED_REMOVAL_DELAY_HOURS,
        )
        "setWindowSecure" -> {
            val enabled = call.argument<Boolean>("enabled") ?: false
            WindowSecurityBridge.setSecure(enabled)
            mapOf("secure" to enabled)
        }
        "getVisualBlockingConfig" -> VisualBlockingSettings.load().toMap()
        // The detector's last init failure (if any) — the settings UI
        // shows it as a warning instead of letting visual blocking
        // fail silently when the bundled model cannot load.
        "getVisualDetectorError" -> mapOf(
            "error" to VisualBlockingSettings.detectorError(),
        )
        "setVisualBlockingConfig" -> {
            val config = VisualBlockingSettings.configFromMap(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
            VisualBlockingSettings.save(config)
            VisualBlockingSettings.load().toMap()
        }
        // Colour modes (Batch C, C3 — GRAYSCALE_RESEARCH.md §6.1/§9.3):
        // the ONLY read/write path for colour_modes_prefs. The store
        // is deliberately NOT in GENERIC_SETTING_STORES, so no generic
        // get/setSetting call can bypass the lock check in
        // setColourModesConfig. A refused (locked) change returns
        // {ok: false, locked: true, lockedModes: [...] } and writes
        // NOTHING — it is not an exception, so the UI can offer the
        // recovery gate as the way through.
        "getColourModesConfig" -> ColourModesSettings.configToMap(ColourModesSettings.load())
        "setColourModesConfig" -> {
            val proposed = try {
                ColourModesSettings.configFromMap(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
            } catch (e: IllegalArgumentException) {
                throw PrivException.invalidArgument(e.message ?: "Invalid colour modes config")
            }
            val old = ColourModesSettings.load()
            val locked = ColourModesSettings.lockedModesForChange(
                old = old,
                new = proposed,
                minuteOfDay = ColourModesSettings.currentMinuteOfDay(),
                focusPhase = FocusSessionStore.isFocusPhase(),
                sessionActive = RecoveryStore.isRecoverySessionActive(appContext),
            )
            if (locked.isNotEmpty()) {
                mapOf<String, Any?>(
                    "ok" to false,
                    "locked" to true,
                    "lockedModes" to locked.map { it.name },
                )
            } else {
                ColourModesSettings.save(proposed)
                mapOf<String, Any?>("ok" to true, "locked" to false, "lockedModes" to emptyList<String>())
            }
        }
        "getColourModesStatus" -> colourModesStatus()
        "syncColourModes" -> {
            val running = AzmAccessibilityService.requestColourModesSync()
            mapOf("ok" to running)
        }
        "getSealRules" -> mapOf(
            "rules" to SealRules.loadRules().map { it.toMap() },
            "activeSeals" to SealRules.activeSeals(appContext).map { it.toMap() },
            "isDeviceOwner" to DeviceOwnerManager.isDeviceOwner(appContext),
        )
        "setSealRules" -> {
            val raw = (call.arguments as? Map<*, *>)?.get("rules") as? List<*>
                ?: throw PrivException.invalidArgument("setSealRules needs a rules list")
            val rules = raw.mapNotNull { (it as? Map<*, *>)?.let { m -> SealRules.Rule.fromMap(m) } }
            SealRules.saveRules(rules)
            mapOf(
                "rules" to SealRules.loadRules().map { it.toMap() },
                "activeSeals" to SealRules.activeSeals(appContext).map { it.toMap() },
            )
        }
        "getActiveSeals" -> mapOf(
            "activeSeals" to SealRules.activeSeals(appContext).map { it.toMap() },
        )
        "getUserRestrictionResidue" -> mapOf(
            // No owner required by design: this is the post-removal
            // residue probe (UserManager read, works unprivileged).
            "keys" to DeviceOwnerManager.getUserRestrictionResidue(appContext),
        )
        "verifyRemovalComplete" -> DeviceOwnerManager.verifyRemovalComplete(appContext)
        "getProvisioningDiagnostics" -> {
            val d = ShizukuProvisioning.diagnostics(appContext)
            mapOf(
                "accounts" to d.accounts,
                "extraUsers" to d.extraUsers,
                "currentOwner" to d.currentOwner,
            )
        }
        // App management (Device Owner)
        "listInstalledApps" -> {
            val includeSystem = call.argument<Boolean>("includeSystem") ?: false
            DeviceOwnerManager.listInstalledApps(appContext, includeSystem).map { it.toMap() }
        }
        "setAppHidden" -> {
            val pkg = call.reqString("packageName")
            val hidden = call.reqBool("hidden")
            mapOf(
                "packageName" to pkg,
                "isHidden" to DeviceOwnerManager.setAppHidden(appContext, pkg, hidden),
            )
        }
        "setAppSuspended" -> {
            val packages = call.reqStringList("packageNames")
            val suspended = call.reqBool("suspended")
            val reasonName = call.argument<String>("reason")
            val reason = if (reasonName != null) SuspensionReason.fromName(reasonName) else null
            mapOf("results" to DeviceOwnerManager.setPackagesSuspended(appContext, packages, suspended, reason))
        }
        "setUninstallBlocked" -> {
            val pkg = call.reqString("packageName")
            val blocked = call.reqBool("blocked")
            mapOf(
                "packageName" to pkg,
                "isUninstallBlocked" to DeviceOwnerManager.setUninstallBlocked(appContext, pkg, blocked),
            )
        }
        // User restrictions
        "listUserRestrictions" -> mapOf(
            "restrictions" to DeviceOwnerManager.listUserRestrictions(appContext),
        )
        "applyUserRestriction" -> {
            val key = call.reqString("key")
            mapOf("key" to key, "active" to DeviceOwnerManager.applyUserRestriction(appContext, key))
        }
        "clearUserRestriction" -> {
            val key = call.reqString("key")
            mapOf("key" to key, "active" to DeviceOwnerManager.clearUserRestriction(appContext, key))
        }
        // Application restrictions
        "getApplicationRestrictions" -> {
            val pkg = call.reqString("packageName")
            mapOf(
                "packageName" to pkg,
                "restrictions" to DeviceOwnerManager.getApplicationRestrictions(appContext, pkg),
            )
        }
        "getAvailableRestrictions" -> {
            val pkg = call.reqString("packageName")
            mapOf(
                "packageName" to pkg,
                "restrictions" to DeviceOwnerManager.getAvailableRestrictions(appContext, pkg),
            )
        }
        "setApplicationRestrictions" -> {
            val pkg = call.reqString("packageName")
            val restrictions = call.reqMap("restrictions")
            val merge = call.argument<Boolean>("merge") ?: false
            mapOf(
                "packageName" to pkg,
                "restrictions" to DeviceOwnerManager.setApplicationRestrictions(
                    appContext, pkg, restrictions, merge,
                ),
            )
        }
        "listRestrictionCapableApps" -> {
            val requiredKeys = call.argument<List<String>>("requiredKeys") ?: emptyList()
            DeviceOwnerManager.listRestrictionCapableApps(appContext, requiredKeys)
        }
        // All installed browsers (Batch C, C1): the discovery port of
        // DeChainer's BrowserRestrictionsManager.getPossibleBrowsers.
        "listInstalledBrowsers" -> DeviceOwnerManager.listInstalledBrowsers(appContext)
        // Torrent clients (Batch F, item 4): the discovery port of
        // DeChainer's BrowserRestrictionsManager.getPossibleTorrentApps,
        // plus the block_torrents flag (DeChainer's SecurityManager).
        "getTorrentApps" -> DeviceOwnerManager.getPossibleTorrentApps(appContext)
        "isBlockTorrentsEnabled" -> SettingsStore.isBlockTorrentsEnabled()
        "setBlockTorrents" -> {
            val enabled = call.reqBool("enabled")
            SettingsStore.setBlockTorrentsEnabled(enabled)
            enabled
        }
        // Auto uninstall-block for suspended apps (Batch F, item 6):
        // the Settings switch. The setter applies/releases the rule
        // for currently-suspended apps and returns the verified flag.
        "isAutoBlockUninstallSuspended" ->
            SettingsStore.isAutoBlockUninstallSuspended()
        "setAutoBlockUninstallSuspended" -> {
            val enabled = call.reqBool("enabled")
            DeviceOwnerManager.setAutoBlockUninstallSuspended(appContext, enabled)
        }
        // Private DNS
        "setPrivateDns" -> DeviceOwnerManager.setPrivateDns(appContext, call.reqString("hostname"))
        "resetPrivateDns" -> DeviceOwnerManager.resetPrivateDns(appContext)
        "getPrivateDns" -> DeviceOwnerManager.getPrivateDns(appContext)
        // Secure-settings grant & Accessibility (provisioning layer)
        "grantWriteSecureSettings" -> {
            val granted = ShizukuProvisioning.grantWriteSecureSettings(appContext)
            if (!granted) {
                throw PrivException(
                    ErrorCodes.PERMISSION_DENIED,
                    "WRITE_SECURE_SETTINGS still not granted after pm grant",
                )
            }
            mapOf("granted" to true)
        }
        "isWriteSecureSettingsGranted" -> mapOf(
            "granted" to ShizukuProvisioning.hasWriteSecureSettings(appContext),
        )
        "setAccessibilityEnabled" -> {
            val enabled = call.reqBool("enabled")
            mapOf("isEnabled" to ShizukuProvisioning.setAccessibilityEnabled(appContext, enabled))
        }
        "isAccessibilityEnabled" -> mapOf(
            "isEnabled" to isAccessibilityListed(),
            "isServiceRunning" to AzmState.accessibilityServiceRunning,
        )
        // Usage
        "getUsageToday" -> getUsageToday(call.argument<String>("packageName"))
        // Focus mode native runtime (F25) — the persisted session in
        // FocusSessionStore; Dart's FocusSession is a view over this state.
        "startFocusSession" -> {
            FocusSessionStore.startSession(
                context = appContext,
                focusMinutes = call.reqInt("focusMinutes"),
                breakMinutes = call.reqInt("breakMinutes"),
                longBreakMinutes = call.reqInt("longBreakMinutes"),
                cycles = call.reqInt("cycles"),
                autoStartFocus = call.reqBool("autoStartFocus"),
                soundEnabled = call.reqBool("soundEnabled"),
                vibrationEnabled = call.reqBool("vibrationEnabled"),
            )
            FocusSessionStore.stateMap(appContext)
        }
        "getFocusSession" -> {
            FocusSessionStore.syncIfDue(appContext)
            FocusSessionStore.stateMap(appContext)
        }
        "pauseFocusSession" -> {
            FocusSessionStore.pause(appContext, call.argument<Boolean>("releaseApps") ?: false)
            FocusSessionStore.stateMap(appContext)
        }
        "resumeFocusSession" -> {
            FocusSessionStore.resume(appContext)
            FocusSessionStore.stateMap(appContext)
        }
        "skipFocusSession" -> {
            FocusSessionStore.skipBreak(appContext)
            FocusSessionStore.stateMap(appContext)
        }
        "stopFocusSession" -> {
            FocusSessionStore.stop(appContext)
            null
        }
        // Focus schedules (Batch I-A, item 13) — the whole list is
        // the unit of write, like setGroups. Saving re-arms the alarm
        // via FocusScheduleStorage.
        "getFocusSchedules" -> mapOf(
            "schedules" to FocusScheduleStorage.getSchedules(appContext).map { it.toMap() },
            "canScheduleExactAlarms" to FocusScheduleManager.canScheduleExactAlarms(appContext),
        )
        "setFocusSchedules" -> {
            val raw = call.argument<List<Map<String, Any?>>>("schedules")
                ?: throw IllegalArgumentException("schedules is required")
            val schedules = raw.mapNotNull { FocusSchedule.fromMap(it) }
            FocusScheduleStorage.saveSchedules(appContext, schedules)
            mapOf(
                "schedules" to FocusScheduleStorage.getSchedules(appContext).map { it.toMap() },
                "canScheduleExactAlarms" to
                    FocusScheduleManager.canScheduleExactAlarms(appContext),
            )
        }
        "openExactAlarmSettings" -> {
            FocusScheduleManager.openExactAlarmSettings(appContext)
            null
        }
        // Full-phone lockdown (Batch I-B, item 14). The config list
        // is the unit of write, like setGroups/setFocusSchedules.
        // startLockdown takes the full lockdown map (one-shots are
        // transient and are NOT saved in the config list); endLockdown
        // is idempotent. Both return the fresh state.
        "getLockdownState" -> LockdownStore.stateMap(appContext)
        "setLockdowns" -> {
            val raw = call.argument<List<Map<String, Any?>>>("lockdowns")
                ?: throw IllegalArgumentException("lockdowns is required")
            val lockdowns = raw.mapNotNull { LockdownStore.Lockdown.fromMap(it) }
            LockdownStore.saveLockdowns(appContext, lockdowns)
            LockdownStore.stateMap(appContext)
        }
        "startLockdown" -> {
            val raw = call.argument<Map<String, Any?>>("lockdown")
                ?: throw IllegalArgumentException("lockdown is required")
            val lockdown = LockdownStore.Lockdown.fromMap(raw)
                ?: throw IllegalArgumentException("lockdown is invalid")
            LockdownStore.start(appContext, lockdown)
            LockdownStore.stateMap(appContext)
        }
        "endLockdown" -> {
            LockdownStore.end(appContext)
            LockdownStore.stateMap(appContext)
        }
        // Notification permission (F12/F25 notifications)
        "hasNotificationPermission" -> mapOf(
            "granted" to FocusSessionStore.hasNotificationPermission(appContext),
        )
        "requestNotificationPermission" -> mapOf(
            "granted" to requestNotificationPermission(),
        )
        // Recovery code (Kotlin only — ARCH §7.1)
        "setRecoveryCode" -> {
            val code = call.reqString("code")
            if (!RecoveryStore.isValidFormat(code)) {
                throw PrivException.invalidArgument("Recovery code must be 16 letters A-Z")
            }
            RecoveryStore.setCode(appContext, code)
            mapOf("isSet" to true)
        }
        "verifyRecoveryCode" -> mapOf(
            "matches" to RecoveryStore.verifyCode(appContext, call.reqString("code")),
        )
        "isRecoveryCodeSet" -> mapOf("isSet" to RecoveryStore.isSet(appContext))
        // Tetris sounds (Batch I-C): a SoundPool player, ported from
        // Dechainer's TetrisSounds — the ringer-mode check lives in
        // play(), like the original.
        "loadTetrisSounds" -> {
            if (tetrisSounds == null) {
                tetrisSounds = com.alnajashia.azm.challenges.TetrisSounds(appContext)
            }
            tetrisSounds!!.load()
            mapOf("loaded" to true)
        }
        "playTetrisSound" -> {
            val sound = runCatching {
                com.alnajashia.azm.challenges.TetrisSound.valueOf(
                    call.reqString("name").uppercase(),
                )
            }.getOrNull()
            if (sound != null) tetrisSounds?.play(sound)
            mapOf("played" to (sound != null))
        }
        "releaseTetrisSounds" -> {
            tetrisSounds?.release()
            tetrisSounds = null
            mapOf("released" to true)
        }
        "generateRecoveryCode" -> mapOf("code" to RecoveryStore.generateCode())
        // Enforcement config (ARCH §8) — SettingsStore, read by the Accessibility Service.
        // These methods were missing from the first Kotlin pass although §8.3
        // requires channel-mediated SettingsStore writes; without them the Dart
        // editors for F9/F10/F13/F14/F15/F27 could not persist anything.
        "getTimeLimit" -> timeLimitPayload(call.reqString("packageName"))
        "setTimeLimit" -> {
            val pkg = call.reqString("packageName")
            val weekly = call.argument<List<*>>("weeklyMinutes")?.map { v ->
                (v as? Number)?.toInt() ?: throw PrivException.invalidArgument("weeklyMinutes must be ints")
            }
            val daily = call.argument<Number>("dailyMinutes")?.toInt()
            if (weekly == null && daily == null) {
                throw PrivException.invalidArgument("setTimeLimit needs dailyMinutes or weeklyMinutes")
            }
            if (weekly != null && weekly.size != 7) {
                throw PrivException.invalidArgument("weeklyMinutes must have 7 entries")
            }
            // Dual storage: one call may carry BOTH components at once. The
            // combined model goes to SettingsStore, whose write follows the
            // original AppTimeLimits.write exactly (weekly wins when set and
            // the other prefs file is cleared, so a package is never in both).
            val limit = com.alnajashia.azm.data.TimeLimit(
                dailyMinutes = daily ?: 0,
                weeklyMinutes = weekly,
            )
            SettingsStore.setTimeLimit(pkg, limit)
            call.argument<Number>("reopenSeconds")?.toInt()?.let { SettingsStore.setReopenSeconds(pkg, it) }
            timeLimitPayload(pkg)
        }
        "getTimeWindows" -> timeWindowsPayload(call.reqString("packageName"))
        "setTimeWindows" -> {
            val pkg = call.reqString("packageName")
            val weeklyRaw = call.argument<List<*>>("weeklyWindows")
            val dailyRaw = call.argument<List<*>>("dailyWindows")
            if (weeklyRaw == null && dailyRaw == null) {
                throw PrivException.invalidArgument("setTimeWindows needs dailyWindows or weeklyWindows")
            }
            if (weeklyRaw != null && weeklyRaw.size != 7) {
                throw PrivException.invalidArgument("weeklyWindows must have 7 day lists")
            }
            // Dual storage: one call may carry BOTH components at once; the
            // combined model goes to SettingsStore, whose write follows the
            // original AppTimeWindows.write exactly (weekly wins when set and
            // the other prefs file is cleared).
            val windows = com.alnajashia.azm.data.TimeWindows(
                dailyWindows = dailyRaw?.let { parseWindows(it) } ?: emptyList(),
                weeklyWindows = weeklyRaw?.map { day -> parseWindows(day) },
            )
            SettingsStore.setTimeWindows(pkg, windows)
            timeWindowsPayload(pkg)
        }
        "getGroups" -> mapOf("groups" to SettingsStore.groups().map { groupToMap(it) })
        "setGroups" -> {
            val raw = call.argument<List<*>>("groups")
                ?: throw PrivException.invalidArgument("Missing or invalid argument: groups")
            SettingsStore.saveGroups(raw.map { parseGroup(it) })
            mapOf("groups" to SettingsStore.groups().map { groupToMap(it) })
        }
        "getBlockedWords" -> blockedWordsPayload()
        "setBlockedWords" -> {
            SettingsStore.setBlockedWords(
                call.reqStringList("words").toSet(),
                call.reqStringList("targetPackages").toSet(),
            )
            blockedWordsPayload()
        }
        "setPassiveWords" -> {
            SettingsStore.setPassiveWords(
                call.reqString("packageName"),
                call.reqStringList("words").toSet(),
            )
            blockedWordsPayload()
        }
        // Batch H, item 10: the merged write — one assignment list
        // replaces the two parallel writers above (kept as adapters).
        // Batch J: one row per word — targets are packageNames and/or
        // groupIds, modes is a list. The old Batch H shape (single
        // packageName / mode strings) is still accepted.
        "setWordAssignments" -> {
            val raw = call.argument<List<*>>("assignments")
                ?: throw PrivException.invalidArgument("Missing or invalid argument: assignments")
            val assignments = raw.mapNotNull { entry ->
                val m = entry as? Map<*, *> ?: return@mapNotNull null
                val word = (m["word"] as? String)?.trim().orEmpty()
                if (word.isEmpty()) return@mapNotNull null
                val pkgs = when (val p = m["packageNames"] ?: m["packageName"]) {
                    is List<*> -> p.mapNotNull { (it as? String)?.trim()?.takeIf { s -> s.isNotEmpty() } }
                    is String -> listOf(p.trim()).filter { it.isNotEmpty() }
                    else -> emptyList()
                }
                val groups = when (val g = m["groupIds"] ?: m["groupId"]) {
                    is List<*> -> g.mapNotNull { (it as? String)?.trim()?.takeIf { s -> s.isNotEmpty() } }
                    is String -> listOf(g.trim()).filter { it.isNotEmpty() }
                    else -> emptyList()
                }
                val modeStrings = when (val mo = m["modes"] ?: m["mode"]) {
                    is List<*> -> mo.mapNotNull { it as? String }
                    is String -> listOf(mo)
                    else -> emptyList()
                }
                if (modeStrings.any { it != "active" && it != "passive" }) {
                    throw PrivException.invalidArgument("Word assignment mode must be active or passive")
                }
                val modes = modeStrings.toSet()
                if (pkgs.isEmpty() && groups.isEmpty()) return@mapNotNull null
                if (modes.isEmpty()) return@mapNotNull null
                SettingsStore.WordAssignment(word, pkgs, groups, modes)
            }
            SettingsStore.setWordAssignments(assignments)
            blockedWordsPayload()
        }
        // Activity blocker (Batch C, C2 — audit item 7): the store
        // holds bare activity class names. The native side is the
        // authority on what may be blocked: a protected entry
        // (launcher, system UI, Settings, in-call UI, Azm itself) is
        // refused with INVALID_ARGUMENT and NOTHING is written.
        "getBlockedActivities" -> mapOf(
            "activities" to SettingsStore.blockedActivities().toList(),
        )
        "setBlockedActivities" -> {
            val activities = call.reqStringList("activities").toSet()
            val protected = activities.filter { entry ->
                val pkg = entry.substringBeforeLast('.', "")
                SettingsStore.isProtectedActivity(pkg.ifEmpty { null }, entry)
            }
            if (protected.isNotEmpty()) {
                throw PrivException.invalidArgument(
                    "Cannot block protected activities: ${protected.joinToString(", ")}",
                )
            }
            SettingsStore.setBlockedActivities(activities)
            mapOf("activities" to SettingsStore.blockedActivities().toList())
        }
        "getAccessedActivities" -> {
            val pm = appContext.packageManager
            val snapshot = synchronized(AzmAccessibilityService.accessedActivities) {
                AzmAccessibilityService.accessedActivities.toList()
            }
            mapOf(
                "activities" to snapshot.map { entry ->
                    val appName = runCatching {
                        pm.getApplicationInfo(entry.packageName, 0)
                            ?.let { pm.getApplicationLabel(it).toString() }
                    }.getOrNull() ?: entry.packageName
                    mapOf<String, Any?>(
                        "packageName" to entry.packageName,
                        "className" to entry.className,
                        "appName" to appName,
                        "timestamp" to entry.timestamp,
                    )
                },
            )
        }
        "getAppActivities" -> {
            // v1.0.1: every activity an app declares, for "block the
            // whole app" (the seen-activities log only knows activities
            // the service already watched). The caller filters the
            // protected ones client-side before saving.
            val pkg = call.reqString("packageName")
            @Suppress("DEPRECATION")
            val info = appContext.packageManager.getPackageInfo(
                pkg,
                PackageManager.GET_ACTIVITIES,
            )
            mapOf(
                "activities" to
                    (info.activities?.map { it.name } ?: emptyList<String>()),
            )
        }
        "getSuspensionLogs" -> mapOf(
            "logs" to SettingsStore.readLogs().map { entry ->
                mapOf<String, Any?>(
                    "id" to entry.optString("id"),
                    "packageName" to entry.optString("packageName"),
                    "appName" to entry.optString("appName"),
                    "timestamp" to entry.optLong("timestamp"),
                    "reason" to entry.optString("reason"),
                    "details" to if (entry.has("details")) entry.optString("details") else null,
                )
            },
        )
        "clearSuspensionLogs" -> {
            SettingsStore.clearLogs()
            mapOf("cleared" to true)
        }
        // Generic Dart-domain config (ARCH §8.2 stores), allowlisted in SettingsStore.
        "getSetting" -> {
            val store = call.reqString("store")
            requireGenericStore(store)
            mapOf("value" to SettingsStore.genericGet(store, call.reqString("key")))
        }
        "setSetting" -> {
            val store = call.reqString("store")
            requireGenericStore(store)
            val key = call.reqString("key")
            // Batch C (C4) priority order, replacing the v1.0.6 Phase D
            // seal refusal that used to sit here: FILING the delayed
            // forced removal (activating the countdown in the recovery
            // state store) is NEVER seal-evaluated. The paper code is
            // priority 1 and starting forced removal is priority 2 —
            // both must be able to break a seal, even mid-focus, or the
            // user has no way out. (A countdown filed BEFORE a seal
            // engaged was already untouched; ticks/cancels of an
            // already-active countdown pass through as before.)
            try {
                SettingsStore.genericSet(store, key, call.argument<Any>("value"))
            } catch (e: IllegalArgumentException) {
                throw PrivException.invalidArgument(e.message ?: "Unsupported setting value")
            }
            mapOf("value" to SettingsStore.genericGet(store, key))
        }
        else -> throw PrivException(
            ErrorCodes.NOT_IMPLEMENTED,
            "Unknown method: ${call.method}",
        )
    }

    // ------------------------------------------------------------ method helpers

    /** State reporting must not throw (contract §5.3): internal failures degrade to notRunning. */
    private fun getShizukuState(): Map<String, Any?> =
        try {
            ShizukuGateway.statePayload(appContext)
        } catch (e: Exception) {
            mapOf(
                "state" to "notRunning",
                "serverVersion" to null,
                "serverUid" to null,
                "isPreV11" to false,
                "diagnostic" to "${e.javaClass.name}: ${e.message}",
            )
        }

    private fun isAccessibilityListed(): Boolean {
        val flat = Settings.Secure.getString(
            appContext.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val component = ComponentName(appContext, AzmAccessibilityService::class.java)
        return flat.split(':').any { ComponentName.unflattenFromString(it) == component }
    }

    /**
     * `requestNotificationPermission` resolution order: already granted →
     * the original's device-owner policy grant (no UI) → the host Activity's
     * runtime prompt via [NotificationPermissionBridge]. Runs on the
     * dispatch executor; the bridge wait is bounded and reports the real
     * state afterwards. Pre-Android-13 there is no runtime permission, so
     * the answer is simply whether notifications are enabled.
     */
    private fun requestNotificationPermission(): Boolean {
        if (FocusSessionStore.hasNotificationPermission(appContext)) return true
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        if (FocusSessionStore.tryGrantNotificationPermissionViaDpm(appContext)) return true
        val activity = NotificationPermissionBridge.currentActivity() ?: return false
        return NotificationPermissionBridge.request(activity)
    }

    private fun getUsageToday(packageName: String?): Map<String, Any?> {
        val today = LocalDate.now().toString()
        // If the service has not run yet today, stored usage still belongs to
        // the recorded date; report it with its real date, honestly.
        val date = SettingsStore.usageDate() ?: today
        val packages = SettingsStore.allUsage()
            .filter { (pkg, _) -> packageName == null || pkg == packageName }
            .map { (pkg, usedMs) -> mapOf<String, Any?>("packageName" to pkg, "usedMs" to usedMs) }
        val groups = SettingsStore.allGroupUsage()
            .map { (groupId, usedMs) -> mapOf<String, Any?>("groupId" to groupId, "usedMs" to usedMs) }
        return mapOf("date" to date, "packages" to packages, "groups" to groups)
    }

    // ------------------------------------------- enforcement-config helpers

    private fun requireGenericStore(store: String) {
        if (store !in SettingsStore.GENERIC_SETTING_STORES) {
            throw PrivException.invalidArgument("Store not available via get/setSetting: $store")
        }
    }

    private fun timeLimitPayload(pkg: String): Map<String, Any?> {
        val limit = SettingsStore.timeLimitFor(pkg)
        return mapOf(
            "packageName" to pkg,
            "dailyMinutes" to limit.dailyMinutes,
            "weeklyMinutes" to limit.weeklyMinutes,
            "reopenSeconds" to SettingsStore.reopenSeconds(pkg),
        )
    }

    private fun windowToMap(w: com.alnajashia.azm.data.TimeWindow): Map<String, Any?> =
        mapOf("s" to w.startMinute, "e" to w.endMinute)

    private fun timeWindowsPayload(pkg: String): Map<String, Any?> {
        val windows = SettingsStore.timeWindowsFor(pkg)
        return mapOf(
            "packageName" to pkg,
            "dailyWindows" to windows.dailyWindows.map { windowToMap(it) },
            "weeklyWindows" to windows.weeklyWindows?.map { day -> day.map { windowToMap(it) } },
        )
    }

    /**
     * Colour-modes status (Batch C, C3): everything the screen needs
     * to render — what is on, what is actually enforced on the device,
     * which modes are currently locked against loosening, the windows
     * active right now, and whether the device can apply the keys at
     * all. `grayscaleSupported` is the permission plus the last
     * read-back verification: false when the grant is missing, or when
     * the last enforce could not read the daltonizer keys back as
     * written (a vendor that silently drops them).
     */
    private fun colourModesStatus(): Map<String, Any?> {
        val config = ColourModesSettings.load()
        val minute = ColourModesSettings.currentMinuteOfDay()
        val focusPhase = FocusSessionStore.isFocusPhase()
        val locked = ColourModesSettings.lockedModesNow(config, minute, focusPhase)
        val activeWindows = ColourMode.entries.flatMap { mode ->
            val windows = config.windowsFor(mode)
            if (windows.isEmpty()) emptyList()
            else ColourModesSettings.activeWindows(windows, minute)
                .map { w ->
                    mapOf<String, Any?>("mode" to mode.name, "s" to w.startMinute, "e" to w.endMinute)
                }
        }
        val failed = ColourModesController.lastVerifyFailed
        val grayscaleSupported = ColourModesController.hasPermission(appContext) &&
            ColourModesController.DALTONIZER_ENABLED !in failed &&
            ColourModesController.DALTONIZER !in failed
        return mapOf<String, Any?>(
            "enabled" to config.enabled,
            "appliedModes" to ColourModesController.appliedModes(appContext).map { it.name },
            "writeSecureSettingsGranted" to ShizukuProvisioning.hasWriteSecureSettings(appContext),
            "accessibilityServiceEnabled" to isAccessibilityListed(),
            "locked" to ColourMode.entries.associate { it.name to (it in locked) },
            "activeWindows" to activeWindows,
            "platformNightLight" to ColourModesController.platformNightLight,
            "extraDimAvailable" to ColourMode.EXTRA_DIM.isAvailable,
            "grayscaleSupported" to grayscaleSupported,
            // Batch G, item 4: the keys the last enforce could not
            // verify as written — the UI shows them instead of
            // claiming the mode applied.
            "failedKeys" to failed.toList(),
        )
    }

    private fun parseWindows(raw: Any?): List<com.alnajashia.azm.data.TimeWindow> {
        val list = raw as? List<*> ?: throw PrivException.invalidArgument("Windows must be a list of {s, e} maps")
        return list.map { item ->
            val m = item as? Map<*, *> ?: throw PrivException.invalidArgument("Window must be a {s, e} map")
            val s = (m["s"] as? Number)?.toInt() ?: throw PrivException.invalidArgument("Window needs int s")
            val e = (m["e"] as? Number)?.toInt() ?: throw PrivException.invalidArgument("Window needs int e")
            if (s !in 0..1439 || e !in 1..1440 || s == e) {
                throw PrivException.invalidArgument("Window minutes out of range: s=$s e=$e")
            }
            com.alnajashia.azm.data.TimeWindow(s, e)
        }
    }

    private fun groupToMap(g: com.alnajashia.azm.data.AppGroup): Map<String, Any?> = mapOf(
        "id" to g.id,
        "name" to g.name,
        "packages" to g.packageNames.toList(),
        "dailyMinutes" to g.timeLimit.dailyMinutes,
        "weeklyMinutes" to g.timeLimit.weeklyMinutes,
        "reopenSeconds" to g.reopenSeconds,
        "dailyWindows" to g.timeWindows.dailyWindows.map { windowToMap(it) },
        "weeklyWindows" to g.timeWindows.weeklyWindows?.map { day -> day.map { windowToMap(it) } },
    )

    private fun parseGroup(raw: Any?): com.alnajashia.azm.data.AppGroup {
        val m = raw as? Map<*, *> ?: throw PrivException.invalidArgument("Group must be a map")
        val id = m["id"] as? String ?: throw PrivException.invalidArgument("Group needs id")
        val name = m["name"] as? String ?: throw PrivException.invalidArgument("Group needs name")
        val packages = (m["packages"] as? List<*>)?.filterIsInstance<String>()?.toSet() ?: emptySet()
        val weeklyLimit = (m["weeklyMinutes"] as? List<*>)?.map { v ->
            (v as? Number)?.toInt() ?: throw PrivException.invalidArgument("weeklyMinutes must be ints")
        }
        val limit = if (weeklyLimit != null) {
            if (weeklyLimit.size != 7) throw PrivException.invalidArgument("weeklyMinutes must have 7 entries")
            com.alnajashia.azm.data.TimeLimit.perDay(weeklyLimit)
        } else {
            com.alnajashia.azm.data.TimeLimit.daily(((m["dailyMinutes"] as? Number)?.toInt() ?: 0))
        }
        val weeklyWindowsRaw = m["weeklyWindows"] as? List<*>
        val windows = if (weeklyWindowsRaw != null) {
            if (weeklyWindowsRaw.size != 7) throw PrivException.invalidArgument("weeklyWindows must have 7 day lists")
            com.alnajashia.azm.data.TimeWindows.perDay(weeklyWindowsRaw.map { parseWindows(it) })
        } else {
            com.alnajashia.azm.data.TimeWindows.daily(parseWindows(m["dailyWindows"] ?: emptyList<Any>()))
        }
        // reopenSeconds round-trips like the per-app value (it is stored
        // in SettingsStore and gate-relevant in Dart); dropping it here
        // silently zeroed every group's cooldown on save.
        val reopenSeconds = ((m["reopenSeconds"] as? Number)?.toInt() ?: 0).coerceAtLeast(0)
        return com.alnajashia.azm.data.AppGroup(id, name, packages, limit, windows, reopenSeconds)
    }

    private fun blockedWordsPayload(): Map<String, Any?> = mapOf(
        "words" to SettingsStore.blockedWords().toList(),
        "targetPackages" to SettingsStore.wordTargetPackages().toList(),
        "passiveWords" to SettingsStore.passiveWordPackages()
            .associateWith { SettingsStore.passiveWordsFor(it).toList() },
        // Batch H, item 10: the merged assignment table — the one
        // canonical store both views read. Batch J: one row per word,
        // with its apps, groups, and modes.
        "assignments" to SettingsStore.wordAssignments().map {
            mapOf(
                "word" to it.word,
                "packageNames" to it.packageNames,
                "groupIds" to it.groupIds,
                "modes" to it.modes.sorted(),
            )
        },
    )

    // ------------------------------------------------------------ argument validation

    private fun MethodCall.reqString(key: String): String =
        argument<String>(key)?.takeIf { it.isNotBlank() }
            ?: throw PrivException.invalidArgument("Missing or invalid argument: $key")

    private fun MethodCall.reqBool(key: String): Boolean =
        argument<Boolean>(key) ?: throw PrivException.invalidArgument("Missing or invalid argument: $key")

    private fun MethodCall.reqInt(key: String): Int =
        (argument<Number>(key))?.toInt()
            ?: throw PrivException.invalidArgument("Missing or invalid argument: $key")

    private fun MethodCall.reqStringList(key: String): List<String> {
        val value = argument<List<*>>(key)
            ?: throw PrivException.invalidArgument("Missing or invalid argument: $key")
        if (value.any { it !is String }) {
            throw PrivException.invalidArgument("Argument $key must be a list of strings")
        }
        @Suppress("UNCHECKED_CAST")
        return value as List<String>
    }

    private fun MethodCall.reqMap(key: String): Map<String, Any?> {
        val value = argument<Map<*, *>>(key)
            ?: throw PrivException.invalidArgument("Missing or invalid argument: $key")
        val result = mutableMapOf<String, Any?>()
        for ((k, v) in value) {
            if (k !is String) throw PrivException.invalidArgument("Argument $key must have string keys")
            result[k] = v
        }
        return result
    }

    companion object {
        const val METHOD_CHANNEL = "azm/privileged"
        const val EVENT_CHANNEL = "azm/privileged/events"
    }
}
