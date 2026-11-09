package io.github.alnajashia.dominanter.deviceowner

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

/**
 * Device Admin receiver — port of the original `DechainerDeviceAdminReceiver`.
 * The callbacks are intentionally empty, as in the original: the app's power
 * comes from Device Owner status, not from the legacy admin policies declared
 * in `res/xml/device_admin_policies.xml`.
 */
class DominanterDeviceAdminReceiver : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
    }
}

/** Fires on device-policy changes; the channel handler reads owner state live, so this stays a no-op anchor. */
class DominanterPolicyUpdateReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Policy state is always re-read authoritatively via DeviceOwnerManager;
        // nothing is cached from this callback (never fake success, ARCH §1.4).
    }
}
