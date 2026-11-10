package io.github.alnajashia.dominanter

import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import io.github.alnajashia.dominanter.data.DominanterState
import io.github.alnajashia.dominanter.data.SettingsStore
import io.github.alnajashia.dominanter.deviceowner.DeviceOwnerManager
import io.github.alnajashia.dominanter.shizuku.ShizukuProvisioning
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
 * Colour-filter orphan release and FocusMode.sync from the original are v1.1
 * (F26/F25-Kotlin) and intentionally absent here.
 */
class DominanterApplication : Application() {

    companion object {
        private const val TAG = "DominanterApplication"
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
            DominanterState.eventSink?.invoke(
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
        if (packageName !in SettingsStore.hiddenPackages()) return
        try {
            val hidden = DeviceOwnerManager.setAppHidden(this, packageName, true)
            Log.d(TAG, "reapplyHiddenIfNeeded: package=$packageName reHidden=$hidden")
        } catch (e: Exception) {
            Log.w(TAG, "reapplyHiddenIfNeeded failed for $packageName", e)
        }
    }

    override fun onCreate() {
        super.onCreate()
        SettingsStore.init(this)

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
        }, "dominanter-cold-start").start()
    }
}
