package io.github.alnajashia.dominanter.channel

import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.alnajashia.dominanter.NotificationPermissionBridge
import io.github.alnajashia.dominanter.accessibility.DominanterAccessibilityService
import io.github.alnajashia.dominanter.data.DominanterState
import io.github.alnajashia.dominanter.data.SettingsStore
import io.github.alnajashia.dominanter.data.SuspensionReason
import io.github.alnajashia.dominanter.deviceowner.DeviceOwnerManager
import io.github.alnajashia.dominanter.focus.FocusSessionStore
import io.github.alnajashia.dominanter.security.RecoveryStore
import io.github.alnajashia.dominanter.shizuku.ShizukuGateway
import io.github.alnajashia.dominanter.shizuku.ShizukuProvisioning
import java.time.LocalDate
import java.util.concurrent.Executors

/**
 * The single Kotlin endpoint of the platform contract
 * (`docs/ARCHITECTURE.md` §5): MethodChannel `dominanter/privileged`,
 * EventChannel `dominanter/privileged/events`, all 25 contract methods plus
 * the §8 enforcement-config extension methods (`get/setTimeLimit`,
 * `get/setTimeWindows`, `get/setGroups`, `get/setBlockedWords`,
 * `setPassiveWords`, `get/clearSuspensionLogs`, `get/setSetting`,
 * `generateRecoveryCode`) added when the Dart layer was built — §8.3 requires
 * channel-mediated SettingsStore writes, and the first Kotlin pass exposed
 * none of them, which made the Dart editors unable to persist anything.
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
        Thread(r, "dominanter-privileged").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    fun attach() {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    fun detach() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        ShizukuGateway.eventSink = null
        DominanterState.eventSink = null
    }

    // ------------------------------------------------------------ EventChannel

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val emit: (String, Map<String, Any?>) -> Unit = { type, payload -> emitEvent(type, payload) }
        ShizukuGateway.eventSink = ShizukuGateway.EventSink { type, payload -> emit(type, payload) }
        DominanterState.eventSink = emit
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        ShizukuGateway.eventSink = null
        DominanterState.eventSink = null
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
            val isOwner = DeviceOwnerManager.removeDeviceOwner(appContext)
            emitEvent("deviceOwnerChanged", mapOf("isDeviceOwner" to isOwner))
            mapOf("isDeviceOwner" to isOwner)
        }
        "isDeviceOwner" -> mapOf(
            "isDeviceOwner" to DeviceOwnerManager.isDeviceOwner(appContext),
            "isAdminActive" to DeviceOwnerManager.isAdminActive(appContext),
        )
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
        // Private DNS
        "setPrivateDns" -> DeviceOwnerManager.setPrivateDns(appContext, call.reqString("hostname"))
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
            "isServiceRunning" to DominanterState.accessibilityServiceRunning,
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
            val limit = io.github.alnajashia.dominanter.data.TimeLimit(
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
            val windows = io.github.alnajashia.dominanter.data.TimeWindows(
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
        val component = ComponentName(appContext, DominanterAccessibilityService::class.java)
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

    private fun windowToMap(w: io.github.alnajashia.dominanter.data.TimeWindow): Map<String, Any?> =
        mapOf("s" to w.startMinute, "e" to w.endMinute)

    private fun timeWindowsPayload(pkg: String): Map<String, Any?> {
        val windows = SettingsStore.timeWindowsFor(pkg)
        return mapOf(
            "packageName" to pkg,
            "dailyWindows" to windows.dailyWindows.map { windowToMap(it) },
            "weeklyWindows" to windows.weeklyWindows?.map { day -> day.map { windowToMap(it) } },
        )
    }

    private fun parseWindows(raw: Any?): List<io.github.alnajashia.dominanter.data.TimeWindow> {
        val list = raw as? List<*> ?: throw PrivException.invalidArgument("Windows must be a list of {s, e} maps")
        return list.map { item ->
            val m = item as? Map<*, *> ?: throw PrivException.invalidArgument("Window must be a {s, e} map")
            val s = (m["s"] as? Number)?.toInt() ?: throw PrivException.invalidArgument("Window needs int s")
            val e = (m["e"] as? Number)?.toInt() ?: throw PrivException.invalidArgument("Window needs int e")
            if (s !in 0..1439 || e !in 1..1440 || s == e) {
                throw PrivException.invalidArgument("Window minutes out of range: s=$s e=$e")
            }
            io.github.alnajashia.dominanter.data.TimeWindow(s, e)
        }
    }

    private fun groupToMap(g: io.github.alnajashia.dominanter.data.AppGroup): Map<String, Any?> = mapOf(
        "id" to g.id,
        "name" to g.name,
        "packages" to g.packageNames.toList(),
        "dailyMinutes" to g.timeLimit.dailyMinutes,
        "weeklyMinutes" to g.timeLimit.weeklyMinutes,
        "dailyWindows" to g.timeWindows.dailyWindows.map { windowToMap(it) },
        "weeklyWindows" to g.timeWindows.weeklyWindows?.map { day -> day.map { windowToMap(it) } },
    )

    private fun parseGroup(raw: Any?): io.github.alnajashia.dominanter.data.AppGroup {
        val m = raw as? Map<*, *> ?: throw PrivException.invalidArgument("Group must be a map")
        val id = m["id"] as? String ?: throw PrivException.invalidArgument("Group needs id")
        val name = m["name"] as? String ?: throw PrivException.invalidArgument("Group needs name")
        val packages = (m["packages"] as? List<*>)?.filterIsInstance<String>()?.toSet() ?: emptySet()
        val weeklyLimit = (m["weeklyMinutes"] as? List<*>)?.map { v ->
            (v as? Number)?.toInt() ?: throw PrivException.invalidArgument("weeklyMinutes must be ints")
        }
        val limit = if (weeklyLimit != null) {
            if (weeklyLimit.size != 7) throw PrivException.invalidArgument("weeklyMinutes must have 7 entries")
            io.github.alnajashia.dominanter.data.TimeLimit.perDay(weeklyLimit)
        } else {
            io.github.alnajashia.dominanter.data.TimeLimit.daily(((m["dailyMinutes"] as? Number)?.toInt() ?: 0))
        }
        val weeklyWindowsRaw = m["weeklyWindows"] as? List<*>
        val windows = if (weeklyWindowsRaw != null) {
            if (weeklyWindowsRaw.size != 7) throw PrivException.invalidArgument("weeklyWindows must have 7 day lists")
            io.github.alnajashia.dominanter.data.TimeWindows.perDay(weeklyWindowsRaw.map { parseWindows(it) })
        } else {
            io.github.alnajashia.dominanter.data.TimeWindows.daily(parseWindows(m["dailyWindows"] ?: emptyList<Any>()))
        }
        return io.github.alnajashia.dominanter.data.AppGroup(id, name, packages, limit, windows)
    }

    private fun blockedWordsPayload(): Map<String, Any?> = mapOf(
        "words" to SettingsStore.blockedWords().toList(),
        "targetPackages" to SettingsStore.wordTargetPackages().toList(),
        "passiveWords" to SettingsStore.passiveWordPackages()
            .associateWith { SettingsStore.passiveWordsFor(it).toList() },
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
        const val METHOD_CHANNEL = "dominanter/privileged"
        const val EVENT_CHANNEL = "dominanter/privileged/events"
    }
}
