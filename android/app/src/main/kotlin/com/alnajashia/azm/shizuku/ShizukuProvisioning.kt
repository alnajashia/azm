package com.alnajashia.azm.shizuku

import android.annotation.SuppressLint
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.IBinder
import android.os.IInterface
import android.os.Process
import android.util.Log
import com.alnajashia.azm.channel.ErrorCodes
import com.alnajashia.azm.channel.PrivException
import com.alnajashia.azm.data.SettingsStore
import com.alnajashia.azm.deviceowner.DeviceOwnerManager
import rikka.shizuku.ShizukuBinderWrapper

/**
 * The ONLY Shizuku consumer for privileged effects (`docs/ARCHITECTURE.md`
 * §1.3/§3): setup-time provisioning, diagnostics, the Accessibility toggle and
 * the `WRITE_SECURE_SETTINGS` grant.
 *
 * Ported from the original `data/DeviceOwnerRepository.kt` (Apache-2.0,
 * warleysr/dechainer) with the §5.4/§7.4 fixes: every shell command is
 * exit-code-checked, `user_setup_complete` is restored in a `finally`, and the
 * reflection path is serialised on a single executor (it mutates the shared
 * `DevicePolicyManager.mService` field, restored in a `finally`).
 *
 * The 13 original shell invocations are all here:
 *  #1–#5 settings get/put user_setup_complete + device_provisioned (argv exec)
 *  #6  pm grant … WRITE_SECURE_SETTINGS          #7  dpm set-device-owner
 *  #8  dumpsys account                           #9  dpm list-owners
 *  #10 pm list users                             #11–#13 accessibility settings put/get
 */
object ShizukuProvisioning {
    private const val TAG = "ShizukuProvisioning"

    /** Serialises every mService-swapping call (the field swap is not thread-safe). */
    private val provisioningLock = Any()

    fun userId(): Int = Process.myUid() / 100000

    // ------------------------------------------------------------ user_setup_complete (#1–#5)

    private fun getUserSetupComplete(userId: Int): String? =
        ShizukuRunner.exec("settings", "--user", "$userId", "get", "secure", "user_setup_complete")
            ?.takeIf { it.exitCode == 0 }?.output?.trim()

    /** #2: flips user_setup_complete 1 → 0 so provisioning works on a set-up device. */
    fun bypassUserSetupComplete(context: Context, userId: Int = userId()): Boolean {
        if (getUserSetupComplete(userId) != "1") return false
        val put = ShizukuRunner.exec(
            "settings", "--user", "$userId", "put", "secure", "user_setup_complete", "0",
        )
        if (put == null || put.exitCode != 0) return false
        refreshUserSetupComplete(context, userId)
        return true
    }

    /** #3: restores user_setup_complete to 1. Called in a finally after provisioning. */
    fun restoreUserSetupComplete(context: Context, userId: Int = userId()) {
        // The result is CHECKED (v1.0.5 audit A-H1): this restore used to
        // be the one provisioning shell call whose outcome was discarded
        // entirely — a failed restore leaves user_setup_complete at 0
        // (device stuck "not set up"), so a failure must at least be
        // visible in the log; the cold-start repair retries it.
        val result = ShizukuRunner.exec(
            "settings", "--user", "$userId", "put", "secure", "user_setup_complete", "1",
        )
        if (result == null || result.exitCode != 0) {
            Log.w(
                TAG,
                "restore user_setup_complete failed: " +
                    (result?.let { "exit ${it.exitCode}: ${it.error}" } ?: "command could not run"),
            )
        }
        refreshUserSetupComplete(context, userId)
    }

    fun refreshUserSetupComplete(context: Context, userId: Int = userId()) {
        runCatching {
            withShizukuDevicePolicyManager(context) { manager ->
                manager.forceUpdateUserSetupComplete(userId)
            }
        }.onFailure {
            Log.w(TAG, "forceUpdateUserSetupComplete failed (may not be supported on this Android version)", it)
        }
    }

    /**
     * Cold-start repair (#4 + #5): if a previous provisioning attempt died
     * between bypass and restore, user_setup_complete is stuck at 0 while the
     * device is in fact provisioned — put it back. Ported from the original's
     * Application.onCreate duty. No-ops safely without a granted binder.
     */
    fun restoreStuckUserSetupComplete(context: Context) {
        if (!ShizukuGateway.isBinderAlive() || !ShizukuGateway.hasPermission()) return
        val uid = userId()
        if (getUserSetupComplete(uid) != "0") return
        val provisioned = ShizukuRunner.exec("settings", "--user", "$uid", "get", "global", "device_provisioned")
            ?.takeIf { it.exitCode == 0 }?.output?.trim()
        if (provisioned != "1") return
        restoreUserSetupComplete(context, uid)
    }

    // ------------------------------------------------------------ binder-wrapped DPM (reflection)

    /**
     * Swaps `DevicePolicyManager.mService` for a Shizuku-binder-wrapped proxy,
     * runs [action], and restores the original service in a finally — the
     * original's `withShizukuDevicePolicyManager`, verbatim in structure.
     * Calls are serialised: the swap mutates a shared framework object.
     */
    @SuppressLint("PrivateApi")
    fun <T> withShizukuDevicePolicyManager(context: Context, action: (DevicePolicyManager) -> T): T =
        synchronized(provisioningLock) {
            val manager = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val field = manager.javaClass.getDeclaredField("mService").apply { isAccessible = true }
            val originalService = field.get(manager) as IInterface
            val wrappedBinder = ShizukuBinderWrapper(originalService.asBinder())
            val stubClass = Class.forName("android.app.admin.IDevicePolicyManager\$Stub")
            val asInterface = stubClass.getMethod("asInterface", IBinder::class.java)
            val proxiedService = asInterface.invoke(null, wrappedBinder)

            field.set(manager, proxiedService)
            try {
                action(manager)
            } finally {
                try {
                    field.set(manager, originalService)
                } catch (e: Throwable) {
                    // Best effort, as in the original — but logged
                    // (v1.0.5 audit A-L3): a failed restore would leave
                    // the wrapped service in place.
                    Log.w(TAG, "failed to restore DevicePolicyManager.mService", e)
                }
            }
        }

    @SuppressLint("PrivateApi")
    private fun DevicePolicyManager.forceUpdateUserSetupComplete(userId: Int) {
        val clazz = this::class.java
        runCatching {
            clazz.getDeclaredMethod("forceUpdateUserSetupComplete", Int::class.javaPrimitiveType!!)
                .also { it.isAccessible = true }.invoke(this, userId)
        }.onFailure {
            runCatching {
                clazz.getDeclaredMethod("forceUpdateUserSetupComplete")
                    .also { it.isAccessible = true }.invoke(this)
            }
        }
    }

    @SuppressLint("PrivateApi")
    private fun DevicePolicyManager.setActiveAdminCompat(receiver: ComponentName, refreshing: Boolean, userId: Int) {
        val clazz = this::class.java
        val method3 = clazz.methods.firstOrNull {
            it.name == "setActiveAdmin" && it.parameterTypes.size == 3 &&
                it.parameterTypes[0] == ComponentName::class.java &&
                it.parameterTypes[1] == java.lang.Boolean.TYPE &&
                it.parameterTypes[2] == java.lang.Integer.TYPE
        } ?: clazz.declaredMethods.firstOrNull {
            it.name == "setActiveAdmin" && it.parameterTypes.size == 3 &&
                it.parameterTypes[0] == ComponentName::class.java &&
                it.parameterTypes[1] == java.lang.Boolean.TYPE &&
                it.parameterTypes[2] == java.lang.Integer.TYPE
        }
        if (method3 != null) {
            method3.isAccessible = true
            method3.invoke(this, receiver, refreshing, userId)
        } else {
            val method2 = clazz.methods.firstOrNull {
                it.name == "setActiveAdmin" && it.parameterTypes.size == 2 &&
                    it.parameterTypes[0] == ComponentName::class.java &&
                    it.parameterTypes[1] == java.lang.Boolean.TYPE
            } ?: clazz.declaredMethods.firstOrNull {
                it.name == "setActiveAdmin" && it.parameterTypes.size == 2 &&
                    it.parameterTypes[0] == ComponentName::class.java &&
                    it.parameterTypes[1] == java.lang.Boolean.TYPE
            }
            method2?.isAccessible = true
            method2?.invoke(this, receiver, refreshing)
        }
    }

    // A null reflective result reads as FAILURE, never success
    // (v1.0.5 audit A-H3): reading it as success used to suppress the
    // `dpm` shell fallback on exactly the devices where the reflective
    // path silently did nothing. The caller still re-verifies with
    // isDeviceOwner afterwards.
    @SuppressLint("PrivateApi")
    private fun DevicePolicyManager.setDeviceOwnerCompat(who: ComponentName, ownerName: String?, userId: Int): Boolean {
        val clazz = this::class.java
        val method2 = clazz.methods.firstOrNull {
            it.name == "setDeviceOwner" && it.parameterTypes.size == 2 &&
                it.parameterTypes[0] == ComponentName::class.java &&
                it.parameterTypes[1] == java.lang.Integer.TYPE
        } ?: clazz.declaredMethods.firstOrNull {
            it.name == "setDeviceOwner" && it.parameterTypes.size == 2 &&
                it.parameterTypes[0] == ComponentName::class.java &&
                it.parameterTypes[1] == java.lang.Integer.TYPE
        }
        if (method2 != null) {
            method2.isAccessible = true
            return (method2.invoke(this, who, userId) as? Boolean) ?: false
        }
        val method3 = clazz.methods.firstOrNull {
            it.name == "setDeviceOwner" && it.parameterTypes.size == 3 &&
                it.parameterTypes[0] == ComponentName::class.java &&
                it.parameterTypes[1] == String::class.java &&
                it.parameterTypes[2] == java.lang.Integer.TYPE
        } ?: clazz.declaredMethods.firstOrNull {
            it.name == "setDeviceOwner" && it.parameterTypes.size == 3 &&
                it.parameterTypes[0] == ComponentName::class.java &&
                it.parameterTypes[1] == String::class.java &&
                it.parameterTypes[2] == java.lang.Integer.TYPE
        }
        if (method3 != null) {
            method3.isAccessible = true
            return (method3.invoke(this, who, ownerName, userId) as? Boolean) ?: false
        }
        val methodLegacy = clazz.methods.firstOrNull {
            it.name == "setDeviceOwner" && it.parameterTypes.size == 2 &&
                it.parameterTypes[0] == String::class.java &&
                it.parameterTypes[1] == String::class.java
        } ?: clazz.declaredMethods.firstOrNull {
            it.name == "setDeviceOwner" && it.parameterTypes.size == 2 &&
                it.parameterTypes[0] == String::class.java &&
                it.parameterTypes[1] == String::class.java
        }
        if (methodLegacy != null) {
            methodLegacy.isAccessible = true
            return (methodLegacy.invoke(this, who.packageName, ownerName) as? Boolean) ?: false
        }
        return false
    }

    // ------------------------------------------------------------ provisioning (F1)

    data class ProvisionResult(val isDeviceOwner: Boolean, val pathUsed: String, val commandOutput: String)

    /**
     * The fixed provisioning sequence of ARCH §5.3 `provisionDeviceOwner`:
     * bypass → binder-wrapped DPM attempt → `dpm` shell fallback (#7) →
     * restore in finally → re-check. On success also tries the
     * WRITE_SECURE_SETTINGS grant (its failure does not un-provision).
     */
    fun provisionDeviceOwner(context: Context): ProvisionResult {
        ShizukuGateway.requireGranted(context)
        if (DeviceOwnerManager.isDeviceOwner(context)) {
            return ProvisionResult(true, "alreadyOwner", "")
        }
        val uid = userId()
        val bypassed = bypassUserSetupComplete(context, uid)
        var commandOutput = ""
        var pathUsed = "binderDpm"
        try {
            var success = false
            runCatching {
                withShizukuDevicePolicyManager(context) { wrappedDpm ->
                    wrappedDpm.setActiveAdminCompat(DeviceOwnerManager.adminComponent(context), true, uid)
                    success = wrappedDpm.setDeviceOwnerCompat(DeviceOwnerManager.adminComponent(context), null, uid)
                }
            }.onFailure {
                Log.w(TAG, "Direct binder setDeviceOwner failed, trying shell command", it)
            }

            if (!success && !DeviceOwnerManager.isDeviceOwner(context)) {
                pathUsed = "shellFallback"
                // #7 — fallback only. Exit code IS checked here (original did not).
                val result = ShizukuRunner.execShell(
                    "dpm set-device-owner ${context.packageName}/${DeviceOwnerManager.adminReceiverShortName()}",
                ) ?: throw ShizukuGateway.unavailableException()
                commandOutput = listOf(result.output, result.error).filter { it.isNotBlank() }.joinToString("\n")
                if (result.exitCode != 0 && !DeviceOwnerManager.isDeviceOwner(context)) {
                    throw PrivException.shellFailed(
                        "dpm set-device-owner", result.exitCode, result.output, result.error,
                    )
                }
            }
        } finally {
            if (bypassed) restoreUserSetupComplete(context, uid)
        }

        val granted = DeviceOwnerManager.isDeviceOwner(context)
        if (!granted) {
            throw PrivException(
                ErrorCodes.PROVISIONING_FAILED,
                "Device Owner provisioning failed via both the binder and shell paths",
                mapOf("pathUsed" to pathUsed, "commandOutput" to commandOutput),
            )
        }
        SettingsStore.setProtectionTornDown(false)
        SettingsStore.setRemovalInProgress(false)
        // Grant WRITE_SECURE_SETTINGS too (as the original did on success); a
        // grant failure is reported in commandOutput, not treated as un-provisioning.
        runCatching { grantWriteSecureSettings(context) }
            .onFailure { commandOutput += "\nWRITE_SECURE_SETTINGS grant failed: ${it.message}" }
        return ProvisionResult(true, pathUsed, commandOutput.trim())
    }

    // ------------------------------------------------------------ WRITE_SECURE_SETTINGS (#6)

    /** #6: `pm grant <applicationId> android.permission.WRITE_SECURE_SETTINGS`, verified by re-check. */
    fun grantWriteSecureSettings(context: Context): Boolean {
        if (hasWriteSecureSettings(context)) return true
        ShizukuGateway.requireGranted(context)
        ShizukuRunner.execShellChecked(
            "pm grant ${context.packageName} ${android.Manifest.permission.WRITE_SECURE_SETTINGS}",
        )
        return hasWriteSecureSettings(context)
    }

    fun hasWriteSecureSettings(context: Context): Boolean =
        context.checkSelfPermission(android.Manifest.permission.WRITE_SECURE_SETTINGS) ==
            PackageManager.PERMISSION_GRANTED

    // ------------------------------------------------------------ diagnostics (#8, #9, #10)

    data class Diagnostics(
        val accounts: List<Map<String, Any?>>,
        val extraUsers: List<Map<String, Any?>>,
        val currentOwner: Map<String, Any?>?,
    )

    fun diagnostics(context: Context): Diagnostics {
        ShizukuGateway.requireGranted(context)
        // #8 dumpsys account
        val accountResult = ShizukuRunner.execShellChecked("dumpsys account")
        val accountRegex = " {4}Account \\{name=(.*?), type=(.*?)\\}".toRegex()
        val accounts = accountResult.output.lines().mapNotNull { line ->
            accountRegex.find(line)?.let { m ->
                mapOf<String, Any?>("type" to m.groupValues[2], "name" to m.groupValues[1])
            }
        }
        // #10 pm list users
        val usersResult = ShizukuRunner.execShellChecked("pm list users")
        val userRegex = Regex("""UserInfo\{(\d+):([^:]+):""")
        val extraUsers = userRegex.findAll(usersResult.output).mapNotNull { m ->
            val id = m.groupValues[1].toInt()
            if (id == 0) null else mapOf<String, Any?>("id" to id, "name" to m.groupValues[2])
        }.toList()
        // #9 dpm list-owners
        val ownersResult = ShizukuRunner.execShellChecked("dpm list-owners")
        val componentPath = ownersResult.output.substringAfter("admin=", "").substringBefore(",", "")
        val currentOwner = if (componentPath.contains("/")) {
            val parts = componentPath.split("/")
            val pkg = parts[0].trim()
            var receiver = parts[1].trim()
            if (receiver.startsWith(".")) receiver = "$pkg/$receiver"
            mapOf<String, Any?>("packageName" to pkg, "receiver" to receiver)
        } else {
            null
        }
        return Diagnostics(accounts, extraUsers, currentOwner)
    }

    // ------------------------------------------------------------ accessibility toggle (#11–#13)

    private fun accessibilityComponent(context: Context): String =
        "${context.packageName}/.accessibility.AzmAccessibilityService"

    /** #11: reads the current enabled_accessibility_services list. */
    fun getEnabledAccessibilityServices(): String {
        val result = ShizukuRunner.execShellChecked("settings get secure enabled_accessibility_services")
        return result.output.replace("\n", "").trim()
    }

    fun isAccessibilityServiceListed(context: Context): Boolean =
        try {
            getEnabledAccessibilityServices().contains(".AzmAccessibilityService")
        } catch (_: Exception) {
            false
        }

    /**
     * #12/#13: appends/removes this app's Accessibility component in
     * `enabled_accessibility_services` and sets `accessibility_enabled 1`,
     * preserving other services; writes 'null' only if the list becomes
     * empty — the original's semantics, with exit codes checked and the
     * result verified by re-reading the setting.
     */
    fun setAccessibilityEnabled(context: Context, enabled: Boolean): Boolean {
        ShizukuGateway.requireGranted(context)
        if (!enabled) {
            // Arm the F28 intentional-disable guard BEFORE the service unbinds,
            // the equivalent of the original's prepareServiceDisable().
            SettingsStore.armIntentionalAccessibilityDisable()
        }
        val component = accessibilityComponent(context)
        val currentRaw = getEnabledAccessibilityServices()
        val current = currentRaw.split(":").filter { it.isNotBlank() && it != "null" }.toMutableList()
        val listed = current.any { it.contains(".AzmAccessibilityService") }
        if (enabled && !listed) current.add(component)
        if (!enabled && listed) current.removeAll { it.contains(".AzmAccessibilityService") }

        val newValue = if (current.isEmpty()) "'null'" else current.joinToString(":")
        ShizukuRunner.execShellChecked("settings put secure enabled_accessibility_services $newValue")
        ShizukuRunner.execShellChecked("settings put secure accessibility_enabled 1")

        // Verified by re-read, never assumed. The verification read is
        // STRICT (v1.0.5 audit A-M6): if the settings read itself fails,
        // the toggle is reported as failed — the lenient
        // isAccessibilityServiceListed (catch-all → false) could
        // otherwise "verify" a disable that never happened.
        val verified = try {
            getEnabledAccessibilityServices().contains(".AzmAccessibilityService")
        } catch (e: Exception) {
            throw PrivException.dpmFailed(
                "Could not verify the accessibility toggle state",
                cause = e,
            )
        }
        if (verified != enabled) {
            throw PrivException.dpmFailed(
                "Accessibility toggle did not take effect",
                verifiedState = mapOf("isEnabled" to verified),
            )
        }
        if (enabled) {
            // The original also granted WRITE_SECURE_SETTINGS on accessibility enable.
            runCatching { grantWriteSecureSettings(context) }
                .onFailure {
                    Log.w(TAG, "WRITE_SECURE_SETTINGS grant on accessibility enable failed", it)
                }
        }
        return verified
    }
}
