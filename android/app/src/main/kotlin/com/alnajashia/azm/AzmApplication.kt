package com.alnajashia.azm

import android.app.Application
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.provider.Settings
import android.util.Log
import com.alnajashia.azm.accessibility.AzmAccessibilityService
import com.alnajashia.azm.data.AzmState
import com.alnajashia.azm.data.ColourModesController
import com.alnajashia.azm.data.SettingsStore
import com.alnajashia.azm.data.SuspensionReason
import com.alnajashia.azm.deviceowner.DeviceOwnerManager
import com.alnajashia.azm.shizuku.ShizukuProvisioning
import org.lsposed.hiddenapibypass.HiddenApiBypass

/**
 * Application duties, ported from the original `DechainerApplication`:
 * HiddenApiBypass exemptions (needed by the provisioning reflection path),
 * SettingsStore initialisation, the package-change receiver (→ `packageChanged`
 * event, invalidating the Dart app-list cache; and re-applying the hidden
 * state of a reinstalled/updated app — the original's
 * `AppRepository.reapplyHiddenIfNeeded`, whose trigger lived in the original
 * service's package receiver at DechainerAccessibilityService.kt:158-166),
 * and the cold-start `user_setup_complete` stuck-flag repair — which no-ops
 * safely without a granted Shizuku binder.
 *
 * Colour-filter orphan release (Batch C, C3) is implemented here, as
 * in the original's `DechainerApplication.releaseOrphanedColorFilters`:
 * on cold start, if colour keys are still enforced but the
 * accessibility service is not listed as enabled, the filter is an
 * orphan (the service died or was disabled without releasing) and is
 * released. FocusMode.sync from the original remains v1.1 (F25-Kotlin)
 * and intentionally absent here.
 */
class AzmApplication : Application() {

    companion object {
        private const val TAG = "AzmApplication"
    }

    private val packageChangeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val pkg = intent?.data?.schemeSpecificPart ?: return
            val change = when (intent.action) {
                Intent.ACTION_PACKAGE_ADDED -> "added"
                Intent.ACTION_PACKAGE_REMOVED, Intent.ACTION_PACKAGE_FULLY_REMOVED -> "removed"
                Intent.ACTION_PACKAGE_REPLACED -> "replaced"
                else -> return
            }
            if (change == "added" || change == "replaced") {
                reapplyHiddenIfNeeded(pkg)
            }
            if (change == "added") {
                suspendTorrentIfNeeded(pkg)
            }
            AzmState.eventSink?.invoke(
                "packageChanged",
                mapOf("packageName" to pkg, "change" to change),
            )
        }
    }

    /**
     * Port of the original `AppRepository.reapplyHiddenIfNeeded`
     * (data/AppRepository.kt:147-165): a fresh install comes back VISIBLE even
     * when the package is still in our persisted hidden set (the app was
     * uninstalled while hidden, then reinstalled), so re-apply the hidden
     * state. The original fired this from its package receiver on
     * `ACTION_PACKAGE_ADDED` for non-replacing installs; firing on updates
     * (`replaced`) as well is harmless because
     * [DeviceOwnerManager.setAppHidden] — which already carries the original's
     * false→true retry, verify-by-reread, and persist-only-on-success
     * semantics — is idempotent. Failures (not Device Owner yet, package
     * mid-install) are logged, never faked.
     *
     * Suspended state needs no equivalent: suspension is not persisted as a
     * set anywhere in our store (it is applied imperatively via the channel
     * and re-derived from configuration by the lockdown path), so there is no
     * recorded suspended state to re-apply.
     */
    private fun reapplyHiddenIfNeeded(packageName: String) {
        if (packageName == this.packageName) return
        // v1.0.5 fix #6: never re-apply policy while a removal teardown
        // is in progress — removal is dismantling exactly this state.
        if (SettingsStore.isRemovalInProgress()) return
        if (packageName !in SettingsStore.hiddenPackages()) return
        // This receiver runs on the main thread inside the package
        // manager's broadcast; the DPM round-trip moves to a background
        // thread so package operations are never blocked on it.
        val appContext = this
        Thread {
            try {
                val hidden = DeviceOwnerManager.setAppHidden(appContext, packageName, true)
                Log.d(TAG, "reapplyHiddenIfNeeded: package=$packageName reHidden=$hidden")
            } catch (e: Exception) {
                Log.w(TAG, "reapplyHiddenIfNeeded failed for $packageName", e)
            }
        }.start()
    }

    /**
     * Batch F, item 4: port of DeChainer's install-time torrent block
     * (`DechainerAccessibilityService.kt:181-183`) — a freshly
     * installed torrent client is suspended at once while
     * block-torrents is on. Runs off the main thread like
     * [reapplyHiddenIfNeeded]; failures are logged, never faked.
     * (The `setPackagesSuspended` call also applies item 6's auto
     * uninstall-block, so a new torrent app cannot be uninstalled to
     * escape either.)
     */
    private fun suspendTorrentIfNeeded(packageName: String) {
        if (packageName == this.packageName) return
        // v1.0.5 fix #6: never apply policy while a removal teardown
        // is in progress.
        if (SettingsStore.isRemovalInProgress()) return
        if (!SettingsStore.isBlockTorrentsEnabled()) return
        val appContext = this
        Thread {
            try {
                if (!DeviceOwnerManager.isTorrentApp(appContext, packageName)) return@Thread
                DeviceOwnerManager.setPackagesSuspended(
                    appContext,
                    listOf(packageName),
                    true,
                    SuspensionReason.TORRENT_APP,
                )
                Log.d(TAG, "suspendTorrentIfNeeded: suspended $packageName")
            } catch (e: Exception) {
                Log.w(TAG, "suspendTorrentIfNeeded failed for $packageName", e)
            }
        }.start()
    }

    override fun onCreate() {
        super.onCreate()
        SettingsStore.init(this)

        // Batch I-B, item 14: a lockdown that outlives a reboot or a
        // force-stop re-applies here (LockdownStore.sync is
        // idempotent and returns early during a removal teardown).
        // Runs off the main thread like the colour-filter orphan
        // release below; a no-op when no lockdown is active.
        Thread({
            try {
                com.alnajashia.azm.lockdown.LockdownStore.sync(this)
            } catch (e: Throwable) {
                Log.w(TAG, "Cold-start lockdown sync failed", e)
            }
        }, "azm-cold-start-lockdown").start()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                HiddenApiBypass.addHiddenApiExemptions("")
            } catch (e: Throwable) {
                Log.e(TAG, "Failed to add hidden api exemptions", e)
            }
        }

        // Shizuku listeners are owned by MainActivity's engine lifecycle
        // (registered in configureFlutterEngine, removed in cleanUpFlutterEngine)
        // so they are never leaked across engine restarts.

        registerReceiver(packageChangeReceiver, IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_FULLY_REMOVED)
            addAction(Intent.ACTION_PACKAGE_REPLACED)
            addDataScheme("package")
        })

        // Cold-start repair of a stuck user_setup_complete flag (see
        // ShizukuProvisioning.restoreStuckUserSetupComplete). Runs off the
        // main thread; silently no-ops without a binder, as in the original's
        // unit-tested contract.
        Thread({
            try {
                ShizukuProvisioning.restoreStuckUserSetupComplete(this)
            } catch (e: Throwable) {
                Log.w(TAG, "Cold-start user_setup_complete repair failed", e)
            }
        }, "azm-cold-start").start()

        // Colour-filter orphan release (Batch C, C3), ported from the
        // original's DechainerApplication.releaseOrphanedColorFilters:
        // if colour keys are still enforced but the accessibility
        // service is not listed as enabled, the filter is an orphan —
        // the service died or was disabled without releasing — and the
        // phone would stay grey with nothing left to switch it off.
        // Runs off the main thread; a no-op when nothing is enforced.
        Thread({
            try {
                releaseOrphanedColourModes()
            } catch (e: Throwable) {
                Log.w(TAG, "Cold-start orphaned colour-modes release failed", e)
            }
        }, "azm-orphan-colour").start()
    }

    /**
     * Releases enforced colour modes when the accessibility service
     * is not in `ENABLED_ACCESSIBILITY_SERVICES` (component match).
     * A no-op when nothing is enforced or the service is enabled.
     */
    private fun releaseOrphanedColourModes() {
        if (!ColourModesController.isApplied(this)) return
        val flat = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: ""
        val component = ComponentName(this, AzmAccessibilityService::class.java)
        val serviceEnabled = flat.split(':')
            .any { ComponentName.unflattenFromString(it) == component }
        if (!serviceEnabled) {
            val released = ColourModesController.release(this)
            Log.i(TAG, "Released orphaned colour modes: $released")
        }
    }
}
