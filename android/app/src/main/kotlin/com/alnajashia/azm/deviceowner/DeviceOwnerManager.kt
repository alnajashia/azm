package com.alnajashia.azm.deviceowner

import android.Manifest
import android.app.NotificationManager
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
import android.os.Build
import android.os.Bundle
import android.os.UserManager
import com.alnajashia.azm.accessibility.AzmAccessibilityService
import com.alnajashia.azm.channel.ErrorCodes
import com.alnajashia.azm.channel.PrivException
import com.alnajashia.azm.data.ColourModesController
import com.alnajashia.azm.data.SealRules
import com.alnajashia.azm.data.SettingsStore
import com.alnajashia.azm.data.SuspensionReason
import com.alnajashia.azm.focus.FocusService
import com.alnajashia.azm.focus.FocusSessionStore
import com.alnajashia.azm.focus.FocusStatusNotifier
import com.alnajashia.azm.notifications.UsageWarningNotifier
import com.alnajashia.azm.shizuku.ShizukuGateway

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
        ComponentName(context.applicationContext, AzmDeviceAdminReceiver::class.java)

    /** The receiver name as used in the `dpm set-device-owner` shell argument. */
    fun adminReceiverShortName(): String = ".deviceowner.AzmDeviceAdminReceiver"

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

    /**
     * Residue detection (v1.0.5 field-failure follow-up): the app's own
     * restriction keys that are STILL in force for the calling user,
     * read from [UserManager] — a read that needs no admin rights and
     * therefore works after ownership was surrendered. Used by the
     * Config tab to warn honestly that leftover restrictions can only
     * be cleared by an administrator: cleanup requires re-provisioning
     * as Device Owner first. Keys set by the system or another admin
     * that our code never applies are not in [SystemRestrictions]'s
     * list and are never reported here.
     */
    fun getUserRestrictionResidue(context: Context): List<String> {
        val userManager = context.getSystemService(Context.USER_SERVICE) as UserManager
        val bundle = runCatching { userManager.userRestrictions }.getOrNull()
            ?: return emptyList()
        return allRestrictionKeys()
            .filter { key -> bundle.getBoolean(key, false) }
    }

    /**
     * Post-confirmation verification probe (Batch D Addendum):
     * Lightweight check used by the post-confirmation loading flow to
     * verify that Device Owner and Admin are dropped, key user restrictions
     * cleared, and screen capture allowed. Works unprivileged.
     */
    fun verifyRemovalComplete(context: Context): Map<String, Any?> {
        val isOwner = isDeviceOwner(context)
        val isAdmin = isAdminActive(context)
        val residue = getUserRestrictionResidue(context)
        val admin = adminComponent(context)
        val dpm = dpm(context)
        val captureStillDisabled = runCatching {
            dpm.getScreenCaptureDisabled(null)
        }.getOrNull() ?: runCatching {
            dpm.getScreenCaptureDisabled(admin)
        }.getOrNull() ?: false

        val verified = !isOwner && !isAdmin && residue.isEmpty() && !captureStillDisabled

        return mapOf(
            "verified" to verified,
            "isDeviceOwner" to isOwner,
            "isAdminActive" to isAdmin,
            "restrictionsResidue" to residue,
            "screenCaptureDisabled" to captureStillDisabled,
        )
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
     *  3. `policies` — zero the dedicated DPM device policies (screen
     *     capture, camera, status bar, keyguard features) and the
     *     notification-permission grant state, each verified by its
     *     getter (v1.0.5 field-failure fix: these surfaces are NOT in
     *     the user-restriction bundle, so the shipped teardown — which
     *     only cleared bundle state — never touched them).
     *  4. `privateDns` — if a specified-host global private DNS was
     *     set by this app, reset it to the platform default
     *     (opportunistic) and verify.
     *  5. `unsuspend` — release every package that is actually
     *     suspended (authoritative per-package probes, chunked).
     *  6. `restrictions` — clear every user restriction in the app's
     *     complete key list (NOT only the keys the live bundle happens
     *     to read back as true — the shipped read-back-only step is
     *     the field failure's second root cause), then verify the
     *     admin bundle holds no true key at all. The set that was in
     *     force is remembered for the post-removal residue check.
     *  7. `unhide` — unhide every hidden package; drop the local
     *     hidden records so nothing re-hides them later.
     *  8. `uninstallBlocks` — lift every uninstall block.
     *  9. `appRestrictions` — clear the per-app restriction bundles
     *     this app applied (the browser URL blocklists).
     *  10. `notifications` — cancel ALL of this app's notifications
     *     (focus, usage warnings, any channel) and reset the
     *     usage-warning notifier's shown/dismissed state. The shipped
     *     teardown never did this: a 5-minute usage-warning
     *     notification survived a "complete" removal in the shade.
     *  11. `clearOwner` — only now `clearDeviceOwnerApp`, verified by
     *     re-reading the owner state.
     *  12. `removeAdmin` — drop Device Admin immediately after
     *     clearing owner (Batch D root cause 1: `clearDeviceOwnerApp`
     *     alone leaves the admin active, and an active admin blocks
     *     uninstall for ~3 minutes).
     *  13. `tornDown` — re-assert the permanent torn-down flag.
     *  14. `stopAccessibility` — stop the accessibility service
     *     cleanly (its `onUnbind` lockdown is already disarmed by
     *     step 1, so nothing fires while the system tears down).
     *  14b. `colourModes` — release any enforced colour modes and
     *     verify every daltonizer key came back to its pre-filter
     *     value (Batch C: a filter left enforced after removal would
     *     leave the phone grey with no app left to switch it off).
     *  15. `verify` — POST-removal verification with reads that work
     *     without admin rights: owner still gone, admin inactive,
     *     none of the restriction keys that were in force at teardown
     *     start still true in the CALLING USER's effective restriction
     *     bundle (UserManager, no admin needed), screen capture
     *     allowed, and no app notification still posted. Any residue
     *     fails this step, so the result dialog can never print a
     *     clean success while a surface persists. (Once ownership is
     *     surrendered the app can no longer clear residue itself —
     *     the dialog says so, and the Config tab's residue check says
     *     re-provisioning is the route back to clearing power.)
     *  16. `flagClear` — a no-op by design (Batch D): the removal
     *     disarm is PERMANENT. The flag is never cleared in the
     *     teardown — clearing it here would re-arm the accessibility
     *     lockdown while the system is still tearing down (Batch D
     *     root cause 2). The flags are reset only by a fresh
     *     provisioning (`AdminReceiver.onEnabled`,
     *     `ShizukuProvisioning.verifyProvisioning`). Every step is
     *     idempotent, so a retry is safe.
     *
     * Threading: the channel handler dispatches on a background
     * executor, so none of this runs on the main thread; the
     * per-package work is probe-driven and the suspension calls are
     * chunked (50 packages per binder call).
     */
    // @Synchronized (v1.0.5 audit FIX-1): two overlapping teardowns
    // (e.g. a double-invoked removal) could otherwise interleave —
    // one run's disarm/verify steps could race the other's, and the
    // per-step report would mix two runs. Serialised, each run is
    // atomic start-to-end; a second invocation simply re-runs the
    // (idempotent) teardown.
    @Synchronized
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
            SettingsStore.setProtectionTornDown(true)
            SettingsStore.setRemovalInProgress(true)
            SettingsStore.armIntentionalAccessibilityDisable()
            "lockdown and policy re-application disarmed"
        }

        // (2) Focus service + session + alarm + notification + impulse + seals.
        step("focus") {
            if (FocusSessionStore.isActive()) {
                FocusSessionStore.stop(context)
            }
            FocusService.stop(context)
            FocusStatusNotifier.cancel(context)
            SettingsStore.genericSet(SettingsStore.PREFS_SECURITY, "impulse_lock", null)
            SealRules.clearEventDeadlines()
            "focus service, session, impulse lock and seals stopped"
        }

        // (3) Dedicated DPM device policies — the surfaces that do NOT
        // live in the user-restriction bundle (field-failure fix).
        // Zeroed explicitly and verified by their getters while we
        // still have owner power; after clearDeviceOwnerApp they could
        // no longer be changed from inside the app at all.
        step("policies") {
            val failed = mutableListOf<String>()
            runCatching { dpm.setScreenCaptureDisabled(admin, false) }
            if (runCatching { dpm.getScreenCaptureDisabled(admin) }.getOrDefault(true)) {
                failed += "screenCapture"
            }
            runCatching { dpm.setCameraDisabled(admin, false) }
            if (runCatching { dpm.getCameraDisabled(admin) }.getOrDefault(true)) {
                failed += "camera"
            }
            runCatching { dpm.setStatusBarDisabled(admin, false) }
            if (runCatching { dpm.isStatusBarDisabled() }.getOrDefault(true)) {
                failed += "statusBar"
            }
            runCatching {
                dpm.setKeyguardDisabledFeatures(
                    admin,
                    DevicePolicyManager.KEYGUARD_DISABLE_FEATURES_NONE,
                )
            }
            if (runCatching {
                    dpm.getKeyguardDisabledFeatures(admin)
                }.getOrDefault(-1) != DevicePolicyManager.KEYGUARD_DISABLE_FEATURES_NONE
            ) {
                failed += "keyguardFeatures"
            }
            // The focus engine's POST_NOTIFICATIONS grant ends in the
            // DEFAULT grant state by construction; set it explicitly so
            // no policy grant state outlives the removal.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                runCatching {
                    dpm.setPermissionGrantState(
                        admin,
                        context.packageName,
                        Manifest.permission.POST_NOTIFICATIONS,
                        DevicePolicyManager.PERMISSION_GRANT_STATE_DEFAULT,
                    )
                }
            }
            if (failed.isNotEmpty()) {
                throw PrivException.dpmFailed(
                    "Device polic(ies) could not be reset: ${failed.joinToString(", ")}",
                )
            }
            "dedicated device policies reset and verified"
        }

        // (4) Global private DNS (F7): a specified host set by this app
        // is written to global settings and is NOT rescinded by
        // clearing the owner — reset it to the platform default while
        // we still can.
        step("privateDns") {
            val mode = runCatching { dpm.getGlobalPrivateDnsMode(admin) }.getOrNull()
            if (mode == DevicePolicyManager.PRIVATE_DNS_MODE_PROVIDER_HOSTNAME) {
                runCatching { dpm.setGlobalPrivateDnsModeOpportunistic(admin) }
                val after = runCatching { dpm.getGlobalPrivateDnsMode(admin) }.getOrNull()
                if (after == DevicePolicyManager.PRIVATE_DNS_MODE_PROVIDER_HOSTNAME) {
                    throw PrivException.dpmFailed(
                        "Private DNS is still in specified-host mode after reset",
                    )
                }
                "private DNS reset to platform default"
            } else {
                "no app-set private DNS to reset"
            }
        }

        // Authoritative package census for the probe-driven steps.
        @Suppress("DEPRECATION")
        val installedNames = context.packageManager.getInstalledApplications(
            PackageManager.GET_META_DATA or PackageManager.MATCH_UNINSTALLED_PACKAGES,
        ).map { it.packageName }.filter { it != context.packageName }

        // (5) Unsuspend everything that is actually suspended.
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

        // (6) Clear every user restriction. The set in force here is
        // remembered for the post-removal residue check (step 12), and
        // the sweep covers the app's COMPLETE key list — not only the
        // keys this read-back reports as true (the shipped teardown
        // trusted the read-back alone; a key it missed was never
        // cleared). Clearing a key that is not set is a harmless
        // no-op, and every actually-set key is then verified gone.
        var residueKeys = emptyList<String>()
        step("restrictions") {
            val active = dpm.getUserRestrictions(admin).let { bundle ->
                bundle.keySet().filter { bundle.getBoolean(it, false) }
            }
            residueKeys = active
            val toClear = (allRestrictionKeys() + active).distinct()
            for (key in toClear) {
                try {
                    dpm.clearUserRestriction(admin, key)
                } catch (_: Exception) { /* verification below records the truth */ }
            }
            val failed = mutableListOf<String>()
            val afterBundle = try {
                dpm.getUserRestrictions(admin)
            } catch (_: Exception) {
                null
            }
            if (afterBundle == null) {
                failed += "(could not re-read restrictions after clearing)"
            } else {
                for (key in afterBundle.keySet()) {
                    if (afterBundle.getBoolean(key, false)) failed += key
                }
            }
            if (failed.isNotEmpty()) {
                throw PrivException.dpmFailed(
                    "Restriction(s) could not be cleared: ${failed.joinToString(", ")}",
                )
            }
            "${active.size} user restriction(s) cleared (full key list swept)"
        }

        // (7) Unhide everything hidden (probes ∪ our persisted records).
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

        // (8) Lift every uninstall block.
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

        // (9) Clear the per-app restriction bundles we applied
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

        // (10) Cancel EVERY notification this app posted and reset the
        // usage-warning notifier's state (field-failure fix: the
        // shipped teardown cancelled only the focus notification, so
        // a usage-warning notification survived a "complete" removal).
        step("notifications") {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            nm.cancelAll()
            UsageWarningNotifier.resetAll(context)
            val still = try {
                nm.activeNotifications.size
            } catch (_: Exception) {
                0
            }
            if (still > 0) {
                throw PrivException.dpmFailed(
                    "$still notification(s) still posted after cancelAll",
                )
            }
            "all notifications cancelled; usage-warning state reset"
        }

        // (11) Only now clear the owner itself — verified by re-read.
        var ownerAfter = true
        step("clearOwner") {
            dpm.clearDeviceOwnerApp(context.packageName)
            ownerAfter = isDeviceOwner(context)
            if (ownerAfter) {
                throw PrivException.dpmFailed("Still Device Owner after clearDeviceOwnerApp")
            }
            "device owner cleared and verified"
        }

        // (12) Drop Device Admin immediately after clearing owner (Batch D root cause 1).
        step("removeAdmin") {
            dpm.removeActiveAdmin(admin)
            android.util.Log.i("DeviceOwnerManager", "removeActiveAdmin ok")
            "active admin removed"
        }

        // (13) Permanent torn-down flag (Batch D root causes 2 & 4).
        step("tornDown") {
            SettingsStore.setProtectionTornDown(true)
            "protection torn down flag permanent"
        }

        // (14) Stop the accessibility service cleanly.
        step("stopAccessibility") {
            AzmAccessibilityService.disableService()
            "accessibility service disabled"
        }

        // (14b) Release any enforced colour modes and verify the device
        // keys came back to their pre-filter values (Batch C). A filter
        // left enforced after removal would leave the phone grey with
        // no app left to switch it off. The release runs while the
        // WRITE_SECURE_SETTINGS grant (via Shizuku) still stands.
        step("colourModes") {
            val expected = ColourModesController.savedPreviousValues(context)
            ColourModesController.release(context)
            val residue = mutableListOf<String>()
            val resolver = context.contentResolver
            for ((key, previous) in expected) {
                val current = android.provider.Settings.Secure.getString(resolver, key)
                if (current != previous) residue += "colour key not restored: $key"
            }
            if (residue.isNotEmpty()) {
                throw PrivException.dpmFailed(residue.joinToString("; "))
            }
            if (expected.isEmpty()) "no colour modes were enforced"
            else "colour modes released and verified"
        }

        // (15) POST-removal verification using ONLY reads that work
        // without admin rights — the app is no longer owner here, so
        // this is the last chance to catch residue before the result
        // is shown. Any residue fails the step and the dialog reports
        // a partial removal, never a clean success.
        step("verify") {
            val residue = mutableListOf<String>()
            if (isDeviceOwner(context)) residue += "deviceOwner still active"
            if (isAdminActive(context)) residue += "admin still active"
            // The calling user's EFFECTIVE restrictions (UserManager
            // needs no admin): none of the keys that were in force at
            // teardown start may still be true. Keys the system or
            // another administrator set that we never applied are not
            // ours to report.
            val userManager = context.getSystemService(Context.USER_SERVICE)
                as UserManager
            val userBundle = runCatching { userManager.userRestrictions }.getOrNull()
            if (userBundle == null) {
                residue += "could not re-read the user's restrictions"
            } else {
                for (key in residueKeys) {
                    if (userBundle.getBoolean(key, false)) {
                        residue += "restriction still in force: $key"
                    }
                }
            }
            // Screen capture policy: readable post-removal on many
            // builds; if it reads back as still disabled, that is
            // residue. An unreadable probe is not treated as failure.
            val captureStillDisabled = runCatching {
                dpm.getScreenCaptureDisabled(admin)
            }.getOrNull()
            if (captureStillDisabled == true) {
                residue += "screen capture still disabled"
            }
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            val activeNotifs = runCatching { nm.activeNotifications.size }.getOrDefault(0)
            if (activeNotifs > 0) {
                residue += "$activeNotifs notification(s) still posted"
            }
            if (residue.isNotEmpty()) {
                throw PrivException.dpmFailed(
                    "Post-removal residue: ${residue.joinToString("; ")}",
                )
            }
            "post-removal verification clean"
        }

        // (16) Removal disarm preserved permanently (do NOT clear removalInProgress).
        step("flagClear") {
            "removal disarm preserved permanently"
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
        // Batch F, item 6: a suspended app must not be uninstallable —
        // uninstalling is the obvious escape from a suspension. The
        // block is recorded as AUTO-applied, so unsuspending clears only
        // blocks Azm itself set, never a manual block from the app
        // sheet. Best-effort per package: a failed block is logged and
        // left unrecorded (never faked), and never fails the suspension
        // itself; a failed unblock stays recorded so the next unsuspend
        // retries it. The whole coupling is armed by the item-6
        // Settings switch (default ON).
        if (SettingsStore.isAutoBlockUninstallSuspended()) {
            if (suspended) {
                packageNames.forEach { pkg ->
                    try {
                        dpm.setUninstallBlocked(admin, pkg, true)
                        SettingsStore.setAutoUninstallBlocked(pkg, true)
                    } catch (e: Exception) {
                        android.util.Log.w(
                            "DeviceOwnerManager",
                            "auto uninstall-block failed for $pkg",
                            e,
                        )
                    }
                }
            } else {
                packageNames.forEach { pkg ->
                    if (pkg !in SettingsStore.autoUninstallBlockedPackages()) return@forEach
                    try {
                        dpm.setUninstallBlocked(admin, pkg, false)
                        SettingsStore.setAutoUninstallBlocked(pkg, false)
                    } catch (e: Exception) {
                        android.util.Log.w(
                            "DeviceOwnerManager",
                            "auto uninstall-unblock failed for $pkg",
                            e,
                        )
                    }
                }
            }
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

    /**
     * The item-6 Settings switch: turning it ON blocks uninstall for
     * every currently-suspended app (and arms the coupling in
     * [setPackagesSuspended] for future suspensions); turning it OFF
     * releases exactly the AUTO-applied blocks and clears the record.
     * Manual blocks are never touched in either direction. Returns the
     * verified flag.
     */
    fun setAutoBlockUninstallSuspended(context: Context, enabled: Boolean): Boolean {
        requireOwner(context)
        val dpm = dpm(context)
        val admin = adminComponent(context)
        SettingsStore.setAutoBlockUninstallSuspended(enabled)
        if (enabled) {
            val pm = context.packageManager
            val installed = try {
                pm.getInstalledApplications(PackageManager.GET_META_DATA)
            } catch (_: Exception) {
                emptyList()
            }
            installed.forEach { info ->
                val pkg = info.packageName
                if (pkg == context.packageName) return@forEach
                val suspended = try {
                    dpm.isPackageSuspended(admin, pkg)
                } catch (_: Exception) {
                    false
                }
                if (!suspended) return@forEach
                try {
                    dpm.setUninstallBlocked(admin, pkg, true)
                    SettingsStore.setAutoUninstallBlocked(pkg, true)
                } catch (e: Exception) {
                    android.util.Log.w(
                        "DeviceOwnerManager",
                        "auto uninstall-block failed for $pkg",
                        e,
                    )
                }
            }
        } else {
            SettingsStore.autoUninstallBlockedPackages().toList().forEach { pkg ->
                try {
                    dpm.setUninstallBlocked(admin, pkg, false)
                    SettingsStore.setAutoUninstallBlocked(pkg, false)
                } catch (e: Exception) {
                    android.util.Log.w(
                        "DeviceOwnerManager",
                        "auto uninstall-unblock failed for $pkg",
                        e,
                    )
                }
            }
        }
        return SettingsStore.isAutoBlockUninstallSuspended()
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

    /**
     * All installed browsers (Batch C, C1), ported in structure from
     * DeChainer's `BrowserRestrictionsManager.getPossibleBrowsers`
     * (Apache-2.0, warleysr/dechainer) with Azm naming.
     *
     * Two discovery passes, de-duplicated by package:
     *  1. `ACTION_MAIN` + `CATEGORY_APP_BROWSER` (declared browsers);
     *  2. `ACTION_VIEW` http/https + `CATEGORY_BROWSABLE` (anything
     *     that opens web links), excluding deep-link-only apps: an
     *     app whose resolved filter declares data authorities that are
     *     ALL concrete hosts handles only its own links, not the web.
     *
     * Each entry carries `packageName`, `label`,
     * `supportsRestrictions` (declares BOTH `URLBlocklist` and
     * `ForceGoogleSafeSearch` in its manifest restrictions),
     * `isSuspended` (only meaningful while Device Owner), and `icon`
     * (the app icon downscaled to 96px, Base64 PNG; null when it
     * cannot be read). Azm itself is never listed.
     */
    fun listInstalledBrowsers(context: Context): List<Map<String, Any?>> {
        val pm = context.packageManager
        val rm = context.getSystemService(Context.RESTRICTIONS_SERVICE) as RestrictionsManager
        val dpm = dpm(context)
        val admin = adminComponent(context)
        val owner = isDeviceOwner(context)
        val candidates = linkedMapOf<String, android.content.pm.ResolveInfo>()
        val browserIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_APP_BROWSER)
        pm.queryIntentActivities(browserIntent, PackageManager.MATCH_ALL)
            .forEach { candidates[it.activityInfo.packageName] = it }
        for (scheme in listOf("http", "https")) {
            val viewIntent = Intent(Intent.ACTION_VIEW, Uri.parse("$scheme://www.google.com"))
                .addCategory(Intent.CATEGORY_BROWSABLE)
            pm.queryIntentActivities(
                viewIntent,
                PackageManager.MATCH_ALL or PackageManager.GET_RESOLVED_FILTER,
            ).forEach { ri ->
                val filter = ri.filter ?: return@forEach
                if (filter.countDataAuthorities() > 0) {
                    val allConcrete = (0 until filter.countDataAuthorities()).all { i ->
                        val host = filter.getDataAuthority(i)?.host
                        host != null && host != "*" && host.isNotEmpty()
                    }
                    if (allConcrete) return@forEach
                }
                candidates[ri.activityInfo.packageName] = ri
            }
        }
        val result = mutableListOf<Map<String, Any?>>()
        for ((pkg, ri) in candidates) {
            if (pkg == context.packageName) continue
            val label = try {
                ri.loadLabel(pm).toString()
            } catch (_: Exception) {
                pkg
            }
            val entries = try { rm.getManifestRestrictions(pkg) } catch (_: Exception) { null }
            val declaredKeys = entries?.map { it.key } ?: emptyList()
            val supportsRestrictions = "URLBlocklist" in declaredKeys &&
                "ForceGoogleSafeSearch" in declaredKeys
            val suspended = owner && try {
                dpm.isPackageSuspended(admin, pkg)
            } catch (_: Exception) {
                false
            }
            result.add(
                mapOf(
                    "packageName" to pkg,
                    "label" to label,
                    "supportsRestrictions" to supportsRestrictions,
                    "isSuspended" to suspended,
                    "icon" to iconBase64(pm, pkg),
                ),
            )
        }
        return result.sortedBy { (it["label"] as String).lowercase() }
    }

    /**
     * All installed torrent clients (Batch F, item 4), ported in
     * structure from DeChainer's `BrowserRestrictionsManager.getPossibleTorrentApps`
     * (Apache-2.0, warleysr/dechainer) with Azm naming.
     *
     * Two discovery passes, de-duplicated by package:
     *  1. Magnet links: the `magnet:` scheme is uniquely used by
     *     torrent clients;
     *  2. Torrent files: an activity that handles
     *     `application/x-bittorrent` or a `.torrent` data path — with
     *     the original's strictness: generic file handlers that merely
     *     declare wildcards are excluded, so a file manager or a
     *     browser that opens any file is never mistaken for a torrent
     *     client.
     *
     * Each entry carries `packageName` and `label` (no icon — the
     * torrent card lists names only). Azm itself is never listed.
     */
    fun getPossibleTorrentApps(context: Context): List<Map<String, Any?>> {
        val pm = context.packageManager

        // 1. Magnet links: magnet scheme is uniquely used by torrent clients
        val magnetIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("magnet:?xt=urn:btih:1234567890ABCDEF"),
        )
        val magnetHandlers = pm.queryIntentActivities(
            magnetIntent,
            PackageManager.MATCH_ALL or PackageManager.GET_RESOLVED_FILTER,
        ).mapNotNull { it.activityInfo?.packageName }

        // 2. Torrent files: must specifically handle
        // "application/x-bittorrent" or the ".torrent" extension.
        val torrentIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(
                Uri.parse("content://dummy/file.torrent"),
                "application/x-bittorrent",
            )
        }
        val torrentHandlers = pm.queryIntentActivities(
            torrentIntent,
            PackageManager.MATCH_ALL or PackageManager.GET_RESOLVED_FILTER,
        ).filter { resolveInfo ->
            val filter = resolveInfo.filter ?: return@filter false

            // Explicit MIME type application/x-bittorrent (not */* or application/*)
            val hasExplicitMime = filter.typesIterator()?.asSequence()?.any { type ->
                type.equals("application/x-bittorrent", ignoreCase = true)
            } == true

            // Explicit .torrent file extension in data path
            val hasTorrentPath = (0 until filter.countDataPaths()).any { i ->
                val path = filter.getDataPath(i)
                path.path.endsWith(".torrent", ignoreCase = true)
            }

            val hasMagnetScheme = filter.hasDataScheme("magnet")

            hasExplicitMime || hasTorrentPath || hasMagnetScheme
        }.mapNotNull { it.activityInfo?.packageName }

        val packages = (magnetHandlers + torrentHandlers).toSet()
        return packages
            .filter { it != context.packageName }
            .map { pkg ->
                val label = try {
                    pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
                } catch (_: Exception) {
                    pkg
                }
                mapOf<String, Any?>("packageName" to pkg, "label" to label)
            }
            .sortedBy { (it["label"] as String).lowercase() }
    }

    /** Membership check against [getPossibleTorrentApps]. */
    fun isTorrentApp(context: Context, packageName: String): Boolean =
        getPossibleTorrentApps(context).any { it["packageName"] == packageName }

    private fun iconBase64(pm: PackageManager, packageName: String): String? = try {
        val drawable = pm.getApplicationIcon(packageName)
        val size = 96
        val bitmap = android.graphics.Bitmap.createBitmap(
            size, size, android.graphics.Bitmap.Config.ARGB_8888,
        )
        val canvas = android.graphics.Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        val out = java.io.ByteArrayOutputStream()
        bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
        android.util.Base64.encodeToString(out.toByteArray(), android.util.Base64.NO_WRAP)
    } catch (_: Exception) {
        null
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

    /** Clears any specified-host Private DNS (Batch DNS "off" side):
     * back to opportunistic, verified by re-reading the mode. */
    fun resetPrivateDns(context: Context): Map<String, Any?> {
        requireOwner(context)
        val dpm = dpm(context)
        val admin = adminComponent(context)
        try {
            dpm.setGlobalPrivateDnsModeOpportunistic(admin)
        } catch (e: Exception) {
            throw PrivException.dpmFailed("setGlobalPrivateDnsModeOpportunistic failed", e)
        }
        val after = getPrivateDns(context)
        if (after["mode"] == "PRIVATE_DNS_MODE_PROVIDER_HOSTNAME_SPECIFIED") {
            throw PrivException.dpmFailed(
                "Private DNS is still in specified-host mode after reset",
            )
        }
        return after
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
