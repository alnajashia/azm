package io.github.alnajashia.dominanter.deviceowner

import android.app.admin.DevicePolicyManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.RestrictionEntry
import android.content.RestrictionsManager
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.UserManager
import io.github.alnajashia.dominanter.channel.ErrorCodes
import io.github.alnajashia.dominanter.channel.PrivException
import io.github.alnajashia.dominanter.data.SettingsStore
import io.github.alnajashia.dominanter.data.SuspensionReason
import io.github.alnajashia.dominanter.focus.FocusService
import io.github.alnajashia.dominanter.focus.FocusSessionStore
import io.github.alnajashia.dominanter.focus.FocusStatusNotifier
import io.github.alnajashia.dominanter.shizuku.ShizukuGateway

/**
 * Runtime Device Owner operations (`docs/ARCHITECTURE.md` §3): everything the
 * app does with `DevicePolicyManager` **after** provisioning.
 *
 * This class contains **no Shizuku import** — by design (§1.3), runtime
 * enforcement must keep working when Shizuku is stopped or revoked.
 *
 * Every mutation verifies by re-reading the authoritative DPM state before
 * reporting success (§1.4); a mismatch is a `DPM_FAILED`, never a fake success.
 * Ported from the original `data/AppRepository.kt`,
 * `data/DeviceOwnerRepository.kt` (DPM parts) and `data/SystemRestrictions.kt`.
 */
object DeviceOwnerManager {
    fun adminComponent(context: Context): ComponentName =
        ComponentName(context.applicationContext, DominanterDeviceAdminReceiver::class.java)

    /** The receiver name as used in the `dpm set-device-owner` shell argument. */
    fun adminReceiverShortName(): String = ".deviceowner.DominanterDeviceAdminReceiver"

    fun dpm(context: Context): DevicePolicyManager =
        context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    // ------------------------------------------------------------ owner state

    fun isDeviceOwner(context: Context): Boolean =
        dpm(context).isDeviceOwnerApp(context.packageName)

    fun isAdminActive(context: Context): Boolean =
        dpm(context).isAdminActive(adminComponent(context))

    fun requireOwner(context: Context) {
        if (!isDeviceOwner(context)) {
            throw PrivException(ErrorCodes.DPM_NOT_OWNER, "App is not Device Owner")
        }
    }

    /** One teardown step's outcome (v1.0.5 fix #6). */
    data class TeardownStep(val id: String, val ok: Boolean, val detail: String) {
        fun toMap(): Map<String, Any?> = mapOf("id" to id, "ok" to ok, "detail" to detail)
    }

    /** The full removal outcome: ordered per-step results + the verified owner state. */
    data class RemovalReport(val isDeviceOwner: Boolean, val steps: List<TeardownStep>) {
        fun toMap(): Map<String, Any?> = mapOf(
            "isDeviceOwner" to isDeviceOwner,
            "steps" to steps.map { it.toMap() },
        )
    }

    /**
     * F2: immediate removal — since v1.0.5 (fix #6) an ordered,
     * idempotent, failure-tolerant TEARDOWN, not a bare
     * `clearDeviceOwnerApp`.
     *
     * Why: removal used to clear the owner and nothing else. The live
     * accessibility service still held its enforcement configuration,
     * and when the system tore components down — above all during the
     * uninstall that follows — its accessibility-loss lockdown fired
     * from the main thread inside the package manager's own removal
     * operation: synchronously suspending every controlled package and
     * adding DISALLOW_INSTALL_APPS mid-uninstall. Devices froze
     * (system UI stuck) until the watchdog rebooted them, after which
     * the uninstall succeeded.
     *
     * Order (each step isolated: a failure is recorded in the report
     * and never aborts the remaining steps):
     *  1. `flag` — persist "removal in progress" FIRST: disarms the
     *     accessibility-loss lockdown and policy re-application for the
     *     whole teardown (the intentional-disable guard is armed too,
     *     as a second line of defence).
     *  2. `focus` — stop the focus service, end any focus session
     *     (releases its suspensions/restrictions and cancels its
     *     alarm), cancel the focus notification.
     *  3. `unsuspend` — release every package that is actually
     *     suspended (authoritative per-package probes, chunked).
     *  4. `restrictions` — clear every user restriction currently set.
     *  5. `unhide` — unhide every hidden package; drop the local
     *     hidden records so nothing re-hides them later.
     *  6. `uninstallBlocks` — lift every uninstall block.
     *  7. `appRestrictions` — clear the per-app restriction bundles
     *     this app applied (the browser URL blocklists).
     *  8. `clearOwner` — only now `clearDeviceOwnerApp`, verified by
     *     re-reading the owner state.
     *  9. `flagClear` — clear the removal flag LAST, whatever happened
     *     above: a failed removal must re-arm protection, and every
     *     step is idempotent, so a retry is safe.
     *
     * Threading: the channel handler dispatches on a background
     * executor, so none of this runs on the main thread; the
     * per-package work is probe-driven and the suspension calls are
     * chunked (50 packages per binder call).
     */
    fun removeDeviceOwner(context: Context): RemovalReport {
        requireOwner(context)
        val dpm = dpm(context)
        val admin = adminComponent(context)
        val steps = mutableListOf<TeardownStep>()

        fun step(id: String, block: () -> String) {
            steps += try {
                TeardownStep(id, true, block())
            } catch (e: Exception) {
                TeardownStep(id, false, e.message ?: e.javaClass.simpleName)
            }
        }

        // (1) Disarm first — before anything stops or changes state.
        step("flag") {
            SettingsStore.setRemovalInProgress(true)
            SettingsStore.armIntentionalAccessibilityDisable()
            "lockdown and policy re-application disarmed"
        }

        // (2) Focus service + session + alarm + notification.
        step("focus") {
            if (FocusSessionStore.isActive()) {
                FocusSessionStore.stop(context)
            }
            FocusService.stop(context)
            FocusStatusNotifier.cancel(context)
            "focus service and session stopped"
        }

        // Authoritative package census for the probe-driven steps.
        @Suppress("DEPRECATION")
        val installedNames = context.packageManager.getInstalledApplications(
            PackageManager.GET_META_DATA or PackageManager.MATCH_UNINSTALLED_PACKAGES,
        ).map { it.packageName }.filter { it != context.packageName }

        // (3) Unsuspend everything that is actually suspended.
        step("unsuspend") {
            val suspended = installedNames.filter { pkg ->
                try { dpm.isPackageSuspended(admin, pkg) } catch (_: Exception) { false }
            }
            val failed = mutableListOf<String>()
            for (chunk in suspended.chunked(50)) {
                try {
                    dpm.setPackagesSuspended(admin, chunk.toTypedArray(), false)
                } catch (_: Exception) { /* per-package verification below records the truth */ }
                chunk.filterTo(failed) { pkg ->
                    try { dpm.isPackageSuspended(admin, pkg) } catch (_: Exception) { true }
                }
            }
            if (failed.isNotEmpty()) {
                throw PrivException.dpmFailed(
                    "${failed.size} package(s) could not be unsuspended: " +
                        failed.take(5).joinToString(", "),
                )
            }
            "${suspended.size} suspended package(s) released"
        }

        // (4) Clear every user restriction currently in force.
        step("restrictions") {
            val active = dpm.getUserRestrictions(admin).let { bundle ->
                bundle.keySet().filter { bundle.getBoolean(it, false) }
            }
            val failed = mutableListOf<String>()
            for (key in active) {
                try {
                    dpm.clearUserRestriction(admin, key)
                } catch (_: Exception) { /* verification below records the truth */ }
                val still = try {
                    dpm.getUserRestrictions(admin).getBoolean(key, false)
                } catch (_: Exception) {
                    true
                }
                if (still) failed += key
            }
            if (failed.isNotEmpty()) {
                throw PrivException.dpmFailed(
                    "Restriction(s) could not be cleared: ${failed.joinToString(", ")}",
                )
            }
            "${active.size} user restriction(s) cleared"
        }

        // (5) Unhide everything hidden (probes ∪ our persisted records).
        step("unhide") {
            val hidden = (installedNames.filter { pkg ->
                try { dpm.isApplicationHidden(admin, pkg) } catch (_: Exception) { false }
            } + SettingsStore.hiddenPackages()).distinct()
            val failed = mutableListOf<String>()
            for (pkg in hidden) {
                try {
                    dpm.setApplicationHidden(admin, pkg, false)
                } catch (_: Exception) { /* verification below records the truth */ }
                val still = try {
                    dpm.isApplicationHidden(admin, pkg)
                } catch (_: Exception) {
                    false // package gone entirely — nothing left hidden
                }
                if (still) failed += pkg else SettingsStore.setHiddenPackage(pkg, false)
            }
            if (failed.isNotEmpty()) {
                throw PrivException.dpmFailed(
                    "${failed.size} package(s) could not be unhidden: " +
                        failed.take(5).joinToString(", "),
                )
            }
            "${hidden.size} hidden package(s) restored"
        }

        // (6) Lift every uninstall block.
        step("uninstallBlocks") {
            val blocked = installedNames.filter { pkg ->
                try { dpm.isUninstallBlocked(admin, pkg) } catch (_: Exception) { false }
            }
            val failed = mutableListOf<String>()
            for (pkg in blocked) {
                try {
                    dpm.setUninstallBlocked(admin, pkg, false)
                } catch (_: Exception) { /* verification below records the truth */ }
                val still = try {
                    dpm.isUninstallBlocked(admin, pkg)
                } catch (_: Exception) {
                    true
                }
                if (still) failed += pkg
            }
            if (failed.isNotEmpty()) {
                throw PrivException.dpmFailed(
                    "${failed.size} uninstall block(s) could not be lifted: " +
                        failed.take(5).joinToString(", "),
                )
            }
            "${blocked.size} uninstall block(s) lifted"
        }

        // (7) Clear the per-app restriction bundles we applied
        // (browser URL blocklists live on the URLBlocklist-declaring apps).
        step("appRestrictions") {
            val capable = listRestrictionCapableApps(context, listOf("URLBlocklist"))
                .map { it["packageName"] as String }
            var cleared = 0
            val failed = mutableListOf<String>()
            for (pkg in capable) {
                val current = try {
                    dpm.getApplicationRestrictions(admin, pkg)
                } catch (_: Exception) {
                    null
                }
                if (current == null || current.isEmpty) continue
                try {
                    dpm.setApplicationRestrictions(admin, pkg, Bundle())
                    cleared++
                } catch (_: Exception) { /* verification below records the truth */ }
                val still = try {
                    !dpm.getApplicationRestrictions(admin, pkg).isEmpty
                } catch (_: Exception) {
                    true
                }
                if (still) failed += pkg
            }
            if (failed.isNotEmpty()) {
                throw PrivException.dpmFailed(
                    "Restriction bundle(s) could not be cleared: ${failed.joinToString(", ")}",
                )
            }
            "$cleared per-app restriction bundle(s) cleared"
        }

        // (8) Only now clear the owner itself — verified by re-read.
        var ownerAfter = true
        step("clearOwner") {
            dpm.clearDeviceOwnerApp(context.packageName)
            ownerAfter = isDeviceOwner(context)
            if (ownerAfter) {
                throw PrivException.dpmFailed("Still Device Owner after clearDeviceOwnerApp")
            }
            "device owner cleared and verified"
        }

        // (9) Clear the flag last, whatever happened above.
        step("flagClear") {
            SettingsStore.setRemovalInProgress(false)
            "removal flag cleared"
        }

        return RemovalReport(ownerAfter, steps)
    }

    // ------------------------------------------------------------ app enumeration

    data class AppInfo(
        val packageName: String,
        val label: String,
        val isSystem: Boolean,
        val isHidden: Boolean,
        val isSuspended: Boolean,
        val isUninstallBlocked: Boolean,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "packageName" to packageName,
            "label" to label,
            "isSystem" to isSystem,
            "isHidden" to isHidden,
            "isSuspended" to isSuspended,
            "isUninstallBlocked" to isUninstallBlocked,
            // F20 is not ported (ARCH §6.2); the field is reserved and always null in v1.
            "hasExplicitContentRating" to null,
        )
    }

    fun listInstalledApps(context: Context, includeSystem: Boolean): List<AppInfo> {
        val pm = context.packageManager
        val dpm = dpm(context)
        val admin = adminComponent(context)
        val owner = isDeviceOwner(context)
        @Suppress("DEPRECATION")
        val installed = pm.getInstalledApplications(
            PackageManager.GET_META_DATA or PackageManager.MATCH_UNINSTALLED_PACKAGES,
        )
        return installed.asSequence()
            .filter { it.packageName != context.packageName }
            .filter { includeSystem || (it.flags and ApplicationInfo.FLAG_SYSTEM) == 0 }
            .map { info ->
                val pkg = info.packageName
                // Per-package DPM probes degrade to false (as in the original) —
                // and are meaningless without owner status anyway.
                val hidden = owner && try { dpm.isApplicationHidden(admin, pkg) } catch (_: Exception) { false }
                val suspended = owner && try { dpm.isPackageSuspended(admin, pkg) } catch (_: Exception) { false }
                val uninstallBlocked = owner && try { dpm.isUninstallBlocked(admin, pkg) } catch (_: Exception) { false }
                AppInfo(
                    packageName = pkg,
                    label = info.loadLabel(pm).toString(),
                    isSystem = (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0,
                    isHidden = hidden,
                    isSuspended = suspended,
                    isUninstallBlocked = uninstallBlocked,
                )
            }
            .sortedBy { it.label.lowercase() }
            .toList()
    }

    private fun requirePackage(context: Context, packageName: String) {
        try {
            context.packageManager.getApplicationInfo(packageName, 0)
        } catch (_: PackageManager.NameNotFoundException) {
            // Hidden/uninstalled packages are still manageable via MATCH_UNINSTALLED_PACKAGES;
            // only treat as missing if the DPM probe below also cannot see it.
            try {
                context.packageManager.getApplicationInfo(
                    packageName, PackageManager.MATCH_UNINSTALLED_PACKAGES,
                )
            } catch (_: PackageManager.NameNotFoundException) {
                throw PrivException(ErrorCodes.PACKAGE_NOT_FOUND, "Package not found: $packageName")
            }
        }
    }

    // ------------------------------------------------------------ hide / suspend / uninstall-block (F8)

    /** Includes the original's Android 14+ false→true re-apply workaround. Verified by re-read. */
    fun setAppHidden(context: Context, packageName: String, hidden: Boolean): Boolean {
        requireOwner(context)
        requirePackage(context, packageName)
        val dpm = dpm(context)
        val admin = adminComponent(context)
        var success = try {
            dpm.setApplicationHidden(admin, packageName, hidden)
        } catch (e: Exception) {
            throw PrivException.dpmFailed("setApplicationHidden failed for $packageName", e)
        }
        if (!success && hidden) {
            // Android 14+: DevicePolicyEngine may retain a stale 'true' entry if the
            // app was uninstalled while hidden; toggling false→true re-applies it.
            try {
                dpm.setApplicationHidden(admin, packageName, false)
                success = dpm.setApplicationHidden(admin, packageName, true)
            } catch (e: Exception) {
                throw PrivException.dpmFailed("setApplicationHidden retry failed for $packageName", e)
            }
        }
        val verified = try { dpm.isApplicationHidden(admin, packageName) } catch (_: Exception) { false }
        if (!success || verified != hidden) {
            throw PrivException.dpmFailed(
                "setApplicationHidden verification failed for $packageName",
                verifiedState = verified,
            )
        }
        // Persist the local hidden set only on verified success (original semantics).
        SettingsStore.setHiddenPackage(packageName, hidden)
        return verified
    }

    /**
     * Suspends/unsuspends packages, logging each suspension at the moment of
     * the effect (F27). Partial success is reported as failure with the
     * per-package verified states — never as full success.
     */
    fun setPackagesSuspended(
        context: Context,
        packageNames: List<String>,
        suspended: Boolean,
        reason: SuspensionReason?,
    ): List<Map<String, Any?>> {
        requireOwner(context)
        if (packageNames.isEmpty()) throw PrivException.invalidArgument("packageNames must not be empty")
        packageNames.forEach { requirePackage(context, it) }
        val dpm = dpm(context)
        val admin = adminComponent(context)
        val failed = try {
            dpm.setPackagesSuspended(admin, packageNames.toTypedArray(), suspended)
        } catch (e: Exception) {
            throw PrivException.dpmFailed("setPackagesSuspended failed", e)
        }
        val results = packageNames.map { pkg ->
            val state = try { dpm.isPackageSuspended(admin, pkg) } catch (_: Exception) { !suspended }
            mapOf<String, Any?>("packageName" to pkg, "isSuspended" to state)
        }
        val mismatched = results.filter { it["isSuspended"] != suspended }.map { it["packageName"] }
        if (failed.isNotEmpty() || mismatched.isNotEmpty()) {
            throw PrivException(
                ErrorCodes.DPM_FAILED,
                "Some packages did not reach the requested suspension state",
                mapOf("failedPackages" to (failed.toList() + mismatched).distinct()),
            )
        }
        if (suspended && reason != null) {
            packageNames.forEach { SettingsStore.logSuspension(it, reason) }
        }
        return results
    }

    fun setUninstallBlocked(context: Context, packageName: String, blocked: Boolean): Boolean {
        requireOwner(context)
        requirePackage(context, packageName)
        val dpm = dpm(context)
        val admin = adminComponent(context)
        try {
            dpm.setUninstallBlocked(admin, packageName, blocked)
        } catch (e: Exception) {
            throw PrivException.dpmFailed("setUninstallBlocked failed for $packageName", e)
        }
        val verified = try { dpm.isUninstallBlocked(admin, packageName) } catch (_: Exception) { !blocked }
        if (verified != blocked) {
            throw PrivException.dpmFailed(
                "setUninstallBlocked verification failed for $packageName",
                verifiedState = verified,
            )
        }
        return verified
    }

    // ------------------------------------------------------------ user restrictions (F3)

    /** The original's recommended pre-selected set — four keys in code (README says three; code wins). */
    val recommendedRestrictionKeys: List<String> = listOf(
        UserManager.DISALLOW_CONFIG_VPN,
        UserManager.DISALLOW_CONFIG_PRIVATE_DNS,
        UserManager.DISALLOW_FACTORY_RESET,
        UserManager.DISALLOW_INSTALL_UNKNOWN_SOURCES_GLOBALLY,
    )

    /** OEM/Knox extras carried by the original's SystemRestrictions.additionalKeys. */
    val additionalRestrictionKeys: List<String> = listOf(
        "disallow_biometric",
        "no_camera",
        "no_wallpaper",
        "no_add_clone_profile",
        "no_config_wifi_private",
        "no_config_wifi_shared",
        "no_non_market_app_by_knox",
    )

    /** Every DISALLOW_/ALLOW_/ENSURE_ key discoverable by reflection over UserManager, plus OEM extras. */
    fun allRestrictionKeys(): List<String> {
        val keys = mutableSetOf<String>()
        val fields = UserManager::class.java.declaredFields + UserManager::class.java.fields
        fields.filter { field ->
            java.lang.reflect.Modifier.isStatic(field.modifiers) &&
                field.type == String::class.java &&
                (field.name.startsWith("DISALLOW_") || field.name.startsWith("ALLOW_") ||
                    field.name.startsWith("ENSURE_"))
        }.forEach { field ->
            try {
                field.isAccessible = true
                (field.get(null) as? String)?.let { keys.add(it) }
            } catch (_: Exception) { /* skip unreadable constants */ }
        }
        keys.addAll(additionalRestrictionKeys)
        return (recommendedRestrictionKeys + keys.sorted()).distinct()
    }

    fun isKnownRestrictionKey(key: String): Boolean = key in allRestrictionKeys()

    fun listUserRestrictions(context: Context): List<Map<String, Any?>> {
        requireOwner(context)
        val bundle: Bundle = dpm(context).getUserRestrictions(adminComponent(context))
        return allRestrictionKeys().map { key ->
            mapOf<String, Any?>(
                "key" to key,
                "active" to bundle.getBoolean(key, false),
                "recommended" to (key in recommendedRestrictionKeys),
            )
        }
    }

    fun applyUserRestriction(context: Context, key: String): Boolean {
        requireOwner(context)
        if (!isKnownRestrictionKey(key)) throw PrivException.invalidArgument("Unknown restriction key: $key")
        try {
            dpm(context).addUserRestriction(adminComponent(context), key)
        } catch (e: Exception) {
            throw PrivException.dpmFailed("addUserRestriction failed for $key", e)
        }
        val active = dpm(context).getUserRestrictions(adminComponent(context)).getBoolean(key, false)
        if (!active) throw PrivException.dpmFailed("Restriction $key not active after apply", verifiedState = false)
        return true
    }

    fun clearUserRestriction(context: Context, key: String): Boolean {
        requireOwner(context)
        if (!isKnownRestrictionKey(key)) throw PrivException.invalidArgument("Unknown restriction key: $key")
        try {
            dpm(context).clearUserRestriction(adminComponent(context), key)
        } catch (e: Exception) {
            throw PrivException.dpmFailed("clearUserRestriction failed for $key", e)
        }
        val active = dpm(context).getUserRestrictions(adminComponent(context)).getBoolean(key, false)
        if (active) throw PrivException.dpmFailed("Restriction $key still active after clear", verifiedState = true)
        return false
    }

    // ------------------------------------------------------------ application restrictions (F4/F5)

    fun getApplicationRestrictions(context: Context, packageName: String): Map<String, Any?> {
        requireOwner(context)
        requirePackage(context, packageName)
        val bundle = try {
            dpm(context).getApplicationRestrictions(adminComponent(context), packageName)
        } catch (e: Exception) {
            throw PrivException.dpmFailed("getApplicationRestrictions failed for $packageName", e)
        }
        return bundleToMap(bundle)
    }

    /**
     * Keys the original's editor deliberately hides from the declared-restrictions
     * list: `AppRestrictionsScreen.kt` filters them out
     * (`.filter { !it.key.equals("URLBlocklist", ignoreCase = true) }`, line 157)
     * and force-preserves their current value on save (lines 392-394), because
     * the browser-restriction flow owns them. The model flags them `hidden`
     * instead of dropping them, so the Dart UI can apply the same rule.
     */
    private val hiddenDeclaredRestrictionKeys: Set<String> = setOf("URLBlocklist")

    /**
     * The declared-restrictions model behind the original's
     * `AppRestrictionsScreen` — a port of `AppRepository.getAvailableRestrictions`
     * (original lines 228-240), exposed there via
     * `DeviceOwnerViewModel.getAvailableRestrictions`.
     *
     * Data source: the **target app's own** manifest-declared restrictions,
     * read through [RestrictionsManager.getManifestRestrictions] — NOT the
     * UserManager system-restriction constants. As in the original, a package
     * that does not exist, or whose application info carries no meta-data,
     * yields an empty list. Each entry carries its declared default (the
     * entry's selected value, populated from the target app's restrictions
     * XML) and, when this app is Device Owner, the currently applied value
     * from DPM — mirroring how the original's `ManagedRestrictionState` merged
     * the manifest entries with `getApplicationRestrictions`.
     *
     * Unlike [getApplicationRestrictions] this does not require Device Owner:
     * the declared model exists independently of ownership, so a non-owner
     * caller gets the entries with `currentValue = null` throughout.
     */
    fun getAvailableRestrictions(context: Context, packageName: String): List<Map<String, Any?>> {
        val pm = context.packageManager
        try {
            val appInfo = pm.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            if (appInfo.metaData == null) return emptyList()
        } catch (_: PackageManager.NameNotFoundException) {
            return emptyList()
        }
        val rm = context.getSystemService(Context.RESTRICTIONS_SERVICE) as RestrictionsManager
        val entries = rm.getManifestRestrictions(packageName) ?: return emptyList()
        val current = try {
            dpm(context).getApplicationRestrictions(adminComponent(context), packageName)
        } catch (_: Exception) {
            Bundle()
        }
        return entries.map { entry -> restrictionEntryToMap(entry, current) }
    }

    /**
     * Serialises one [RestrictionEntry] for the channel. Type mapping onto the
     * contract vocabulary: BOOLEAN→`bool`, INTEGER→`int`,
     * MULTI_SELECT→`stringList`, BUNDLE/BUNDLE_ARRAY→`bundle`,
     * CHOICE/STRING (and the value-less NULL)→`string`. Bundle entries carry
     * their child entries recursively under `children` (for BUNDLE_ARRAY the
     * children are the per-item template, so they carry defaults only).
     */
    private fun restrictionEntryToMap(entry: RestrictionEntry, current: Bundle): Map<String, Any?> {
        val key = entry.key
        val type = when (entry.type) {
            RestrictionEntry.TYPE_BOOLEAN -> "bool"
            RestrictionEntry.TYPE_INTEGER -> "int"
            RestrictionEntry.TYPE_MULTI_SELECT -> "stringList"
            RestrictionEntry.TYPE_BUNDLE, RestrictionEntry.TYPE_BUNDLE_ARRAY -> "bundle"
            else -> "string"
        }
        val defaultValue: Any? = when (entry.type) {
            RestrictionEntry.TYPE_BOOLEAN -> entry.selectedState
            RestrictionEntry.TYPE_INTEGER -> entry.intValue
            RestrictionEntry.TYPE_MULTI_SELECT -> entry.allSelectedStrings?.toList()
            RestrictionEntry.TYPE_BUNDLE, RestrictionEntry.TYPE_BUNDLE_ARRAY -> null
            else -> entry.selectedString
        }
        val currentValue: Any? = if (current.containsKey(key)) bundleToMap(current)[key] else null
        val children: List<Map<String, Any?>>? =
            if (entry.type == RestrictionEntry.TYPE_BUNDLE ||
                entry.type == RestrictionEntry.TYPE_BUNDLE_ARRAY
            ) {
                val childCurrent = if (entry.type == RestrictionEntry.TYPE_BUNDLE) {
                    current.getBundle(key) ?: Bundle()
                } else {
                    Bundle()
                }
                (entry.restrictions ?: emptyArray()).map { child ->
                    restrictionEntryToMap(child, childCurrent)
                }
            } else {
                null
            }
        return mapOf(
            "key" to key,
            "type" to type,
            "defaultValue" to defaultValue,
            "currentValue" to currentValue,
            "titleKey" to entry.title,
            "description" to entry.description,
            "hidden" to hiddenDeclaredRestrictionKeys.any { it.equals(key, ignoreCase = true) },
            "choices" to entry.choiceValues?.toList(),
            "children" to children,
        )
    }

    /**
     * Port of the original `DeviceOwnerRepository.installShizuku`
     * (original lines 42-53): opens Shizuku's Play Store page — the
     * `market://` intent first, the https Play Store URL as fallback — with
     * FLAG_ACTIVITY_NEW_TASK. The original wraps intent *construction* in the
     * try/catch (which can never throw ActivityNotFoundException); this port
     * wraps the `startActivity` calls instead, so the documented fallback
     * actually fires on devices with no market app, and reports whether any
     * intent was launched. References [ShizukuGateway.SHIZUKU_PACKAGE], a
     * compile-time constant — this class still has no runtime Shizuku
     * dependency (§1.3).
     */
    fun installShizuku(context: Context): Boolean {
        val marketIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("market://details?id=${ShizukuGateway.SHIZUKU_PACKAGE}"),
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
        try {
            context.startActivity(marketIntent)
            return true
        } catch (_: ActivityNotFoundException) {
            // fall through to the web URL, as the original intends
        }
        val webIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("https://play.google.com/store/apps/details?id=${ShizukuGateway.SHIZUKU_PACKAGE}"),
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
        return try {
            context.startActivity(webIntent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    fun setApplicationRestrictions(
        context: Context,
        packageName: String,
        restrictions: Map<String, Any?>,
        merge: Boolean,
    ): Map<String, Any?> {
        requireOwner(context)
        requirePackage(context, packageName)
        val dpm = dpm(context)
        val admin = adminComponent(context)
        val newBundle = mapToBundle(restrictions)
        val finalBundle = if (merge) {
            val current = dpm.getApplicationRestrictions(admin, packageName)
            current.putAll(newBundle)
            current
        } else {
            newBundle
        }
        try {
            dpm.setApplicationRestrictions(admin, packageName, finalBundle)
        } catch (e: Exception) {
            throw PrivException.dpmFailed("setApplicationRestrictions failed for $packageName", e)
        }
        val verified = bundleToMap(dpm.getApplicationRestrictions(admin, packageName))
        // Verify every requested key survived the round-trip with the same value.
        for ((key, value) in restrictions) {
            if (!valuesEqual(verified[key], value)) {
                throw PrivException.dpmFailed(
                    "Application restriction $key did not verify for $packageName",
                    verifiedState = verified,
                )
            }
        }
        return verified
    }

    /** Apps declaring managed restrictions (all, or only those declaring every required key). */
    fun listRestrictionCapableApps(context: Context, requiredKeys: List<String>): List<Map<String, Any?>> {
        val pm = context.packageManager
        val rm = context.getSystemService(Context.RESTRICTIONS_SERVICE) as RestrictionsManager
        @Suppress("DEPRECATION")
        val installed = pm.getInstalledApplications(PackageManager.GET_META_DATA)
        val result = mutableListOf<Map<String, Any?>>()
        for (info in installed) {
            val pkg = info.packageName
            if (pkg == context.packageName) continue
            val entries = try { rm.getManifestRestrictions(pkg) } catch (_: Exception) { null } ?: continue
            if (entries.isEmpty()) continue
            val declaredKeys = entries.map { it.key }
            if (requiredKeys.isNotEmpty() && !declaredKeys.containsAll(requiredKeys)) continue
            result.add(
                mapOf(
                    "packageName" to pkg,
                    "label" to info.loadLabel(pm).toString(),
                    "declaredKeys" to declaredKeys,
                ),
            )
        }
        return result.sortedBy { (it["label"] as String).lowercase() }
    }

    private fun valuesEqual(a: Any?, b: Any?): Boolean = when {
        a is List<*> && b is List<*> -> a.map { it.toString() } == b.map { it.toString() }
        a is Number && b is Number -> a.toLong() == b.toLong()
        else -> a == b
    }

    fun bundleToMap(bundle: Bundle): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        for (key in bundle.keySet()) {
            @Suppress("DEPRECATION")
            map[key] = when (val v = bundle.get(key)) {
                is Array<*> -> v.toList()
                is IntArray -> v.toList()
                is BooleanArray -> v.toList()
                is LongArray -> v.toList()
                is DoubleArray -> v.toList()
                is FloatArray -> v.toList()
                is Bundle -> bundleToMap(v)
                else -> v
            }
        }
        return map
    }

    fun mapToBundle(map: Map<String, Any?>): Bundle {
        val bundle = Bundle()
        for ((key, value) in map) {
            when (value) {
                null -> Unit
                is String -> bundle.putString(key, value)
                is Boolean -> bundle.putBoolean(key, value)
                is Int -> bundle.putInt(key, value)
                is Long -> bundle.putInt(key, value.toInt())
                is Double -> bundle.putInt(key, value.toInt())
                is List<*> -> {
                    if (value.all { it is String }) {
                        @Suppress("UNCHECKED_CAST")
                        bundle.putStringArray(key, (value as List<String>).toTypedArray())
                    } else {
                        throw PrivException.invalidArgument("Unsupported list element type for restriction $key")
                    }
                }
                is Map<*, *> -> {
                    @Suppress("UNCHECKED_CAST")
                    bundle.putBundle(key, mapToBundle(value as Map<String, Any?>))
                }
                else -> throw PrivException.invalidArgument(
                    "Unsupported value type for restriction $key: ${value.javaClass.name}",
                )
            }
        }
        return bundle
    }

    // ------------------------------------------------------------ private DNS (F7)

    fun setPrivateDns(context: Context, hostname: String): Map<String, Any?> {
        requireOwner(context)
        if (hostname.isBlank() || hostname.contains(" ") || hostname.contains("/")) {
            throw PrivException.invalidArgument("Malformed private DNS hostname: $hostname")
        }
        val dpm = dpm(context)
        val admin = adminComponent(context)
        val resultCode = try {
            dpm.setGlobalPrivateDnsModeSpecifiedHost(admin, hostname)
        } catch (e: Exception) {
            throw PrivException.dpmFailed("setGlobalPrivateDnsModeSpecifiedHost failed", e)
        }
        if (resultCode != DevicePolicyManager.PRIVATE_DNS_SET_NO_ERROR) {
            throw PrivException.dpmFailed(
                "Private DNS was not applied (DPM result code $resultCode)",
                verifiedState = resultCode,
            )
        }
        return getPrivateDns(context)
    }

    fun getPrivateDns(context: Context): Map<String, Any?> {
        requireOwner(context)
        val dpm = dpm(context)
        val admin = adminComponent(context)
        val mode = dpm.getGlobalPrivateDnsMode(admin)
        val modeName = when (mode) {
            DevicePolicyManager.PRIVATE_DNS_MODE_OFF -> "PRIVATE_DNS_MODE_OFF"
            DevicePolicyManager.PRIVATE_DNS_MODE_OPPORTUNISTIC -> "PRIVATE_DNS_MODE_OPPORTUNISTIC"
            DevicePolicyManager.PRIVATE_DNS_MODE_PROVIDER_HOSTNAME ->
                "PRIVATE_DNS_MODE_PROVIDER_HOSTNAME_SPECIFIED"
            else -> "UNKNOWN($mode)"
        }
        val host = if (mode == DevicePolicyManager.PRIVATE_DNS_MODE_PROVIDER_HOSTNAME) {
            dpm.getGlobalPrivateDnsHost(admin)
        } else {
            null
        }
        return mapOf("mode" to modeName, "hostname" to host)
    }
}
