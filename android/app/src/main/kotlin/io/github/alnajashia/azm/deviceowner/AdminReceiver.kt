package io.github.alnajashia.azm.deviceowner

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyIdentifiers
import android.app.admin.PolicyUpdateReceiver
import android.app.admin.PolicyUpdateResult
import android.app.admin.TargetUser
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.annotation.RequiresApi
import io.github.alnajashia.azm.data.AzmState
import io.github.alnajashia.azm.data.SettingsStore

/**
 * Device Admin receiver — port of the original `DechainerDeviceAdminReceiver`.
 * The callbacks are intentionally empty, as in the original: the app's power
 * comes from Device Owner status, not from the legacy admin policies declared
 * in `res/xml/device_admin_policies.xml`.
 */
class AzmDeviceAdminReceiver : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        SettingsStore.setProtectionTornDown(false)
        SettingsStore.setRemovalInProgress(false)
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
    }
}

/**
 * Policy-update receiver — port of the original `DechainerPolicyUpdateReceiver`
 * (parity audit D-36: an earlier build of ours reduced this to a plain no-op
 * BroadcastReceiver, losing the authoritative-result reporting entirely).
 *
 * Only delivered on API 34+ (UPSIDE_DOWN_CAKE). Reports the FINAL,
 * authoritative result of policy changes (e.g. setApplicationHidden), which
 * can differ from the boolean those DevicePolicyManager calls return
 * synchronously (that return value just means "request accepted", not
 * "policy applied").
 *
 * API-level safety mirrors the original exactly: the class is annotated
 * [RequiresApi] and the manifest declares the receiver with NO
 * `android:minSdkVersion` gate — the two intent actions
 * (DEVICE_POLICY_SET_RESULT / DEVICE_POLICY_CHANGED) are only ever sent by
 * the system on API 34+, where the PolicyUpdateReceiver mechanism exists,
 * so the class is never instantiated on API 30–33 despite minSdk 30.
 */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
class AzmPolicyUpdateReceiver : PolicyUpdateReceiver() {

    override fun onPolicySetResult(
        context: Context,
        policyIdentifier: String,
        additionalPolicyParams: Bundle,
        targetUser: TargetUser,
        policyUpdateResult: PolicyUpdateResult
    ) {
        log("onPolicySetResult", policyIdentifier, additionalPolicyParams, targetUser, policyUpdateResult)
    }

    override fun onPolicyChanged(
        context: Context,
        policyIdentifier: String,
        additionalPolicyParams: Bundle,
        targetUser: TargetUser,
        policyUpdateResult: PolicyUpdateResult
    ) {
        log("onPolicyChanged", policyIdentifier, additionalPolicyParams, targetUser, policyUpdateResult)
    }

    private fun log(
        callback: String,
        policyIdentifier: String,
        additionalPolicyParams: Bundle,
        targetUser: TargetUser,
        policyUpdateResult: PolicyUpdateResult
    ) {
        val packageName = additionalPolicyParams.getString(EXTRA_PACKAGE_NAME)
        Log.d(
            "AzmPolicyUpdate",
            "$callback: policy=$policyIdentifier package=$packageName " +
                "user=${describeTargetUser(targetUser)} result=${describeResult(policyUpdateResult)}"
        )

        // The final/authoritative result can disagree with what
        // setApplicationHidden() returned synchronously (e.g. another admin
        // overriding it later). The original dropped its cache here
        // (AppRepository.invalidateCache()) so the next read reflected real
        // PackageManager state. Our Kotlin layer keeps no app cache — state
        // is re-read authoritatively via DeviceOwnerManager — and the one
        // cache that does exist, the Dart app list, is invalidated through
        // the `packageChanged` event, the same bridge
        // AzmApplication's package receiver uses for exactly that
        // purpose. Emit it (when a UI engine is attached; the sink is null
        // otherwise and the event is advisory) so the next read reflects
        // the real state instead of whatever the UI last assumed.
        if (policyIdentifier == DevicePolicyIdentifiers.APPLICATION_HIDDEN_POLICY &&
            packageName != null
        ) {
            AzmState.eventSink?.invoke(
                "packageChanged",
                mapOf("packageName" to packageName, "change" to "policyResult"),
            )
        }
    }

    private fun describeResult(result: PolicyUpdateResult): String = when (result.resultCode) {
        PolicyUpdateResult.RESULT_POLICY_SET -> "RESULT_POLICY_SET"
        PolicyUpdateResult.RESULT_POLICY_CLEARED -> "RESULT_POLICY_CLEARED"
        PolicyUpdateResult.RESULT_FAILURE_CONFLICTING_ADMIN_POLICY -> "RESULT_FAILURE_CONFLICTING_ADMIN_POLICY"
        PolicyUpdateResult.RESULT_FAILURE_STORAGE_LIMIT_REACHED -> "RESULT_FAILURE_STORAGE_LIMIT_REACHED"
        PolicyUpdateResult.RESULT_FAILURE_HARDWARE_LIMITATION -> "RESULT_FAILURE_HARDWARE_LIMITATION"
        else -> "RESULT_FAILURE_UNKNOWN(${result.resultCode})"
    }

    private fun describeTargetUser(targetUser: TargetUser): String = when (targetUser) {
        TargetUser.GLOBAL -> "GLOBAL"
        TargetUser.LOCAL_USER -> "LOCAL_USER"
        TargetUser.PARENT_USER -> "PARENT_USER"
        TargetUser.UNKNOWN_USER -> "UNKNOWN_USER"
        else -> targetUser.toString()
    }
}
