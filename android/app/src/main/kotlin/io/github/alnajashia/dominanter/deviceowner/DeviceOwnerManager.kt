package io.github.alnajashia.dominanter.deviceowner

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.RestrictionsManager
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.UserManager
import android.util.Log
import io.github.alnajashia.dominanter.channel.ErrorCodes
import io.github.alnajashia.dominanter.channel.PrivException
import io.github.alnajashia.dominanter.data.SettingsStore
import io.github.alnajashia.dominanter.data.SuspensionReason

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
    private const val TAG = "DeviceOwnerManager"

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

    /** F2: immediate removal. Success requires the re-read to say "not owner". */
    fun removeDeviceOwner(context: Context): Boolean {
        requireOwner(context)
        try {
            dpm(context).clearDeviceOwnerApp(context.packageName)
        } catch (e: Exception) {
            throw PrivException.dpmFailed("clearDeviceOwnerApp failed", e)
        }
        val stillOwner = isDeviceOwner(context)
        if (stillOwner) throw PrivException.dpmFailed("Still Device Owner after clearDeviceOwnerApp")
        return false
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

    /** Every DISALLOW_*/ALLOW_*/ENSURE_* key discoverable by reflection over UserManager, plus OEM extras. */
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
        if (resultCode != DevicePolicyManager.PRIVATE_DNS_SET_SUCCESS) {
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

    internal fun logTag(): String = TAG.also { Log.d(TAG, "DeviceOwnerManager ready") }
}
