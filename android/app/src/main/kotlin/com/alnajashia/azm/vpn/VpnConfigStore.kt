package com.alnajashia.azm.vpn

import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.UserManager
import android.util.Log
import com.alnajashia.azm.data.SettingsStore
import com.alnajashia.azm.deviceowner.DeviceOwnerManager

/**
 * Internet blocking + VPN-based DNS filtering (user order 2026-11-19).
 *
 * One local, no-configuration VpnService serves both features:
 *  - DNS filtering over DoH (port 443) — works on networks that
 *    block port 853, where system Private DNS cannot activate.
 *  - Internet blocking per app, per group, or for the whole phone
 *    (packets dropped inside the TUN; the app itself still runs).
 *
 * As Device Owner the service is pinned with
 * [DevicePolicyManager.setAlwaysOnVpnPackage] (lockdown) and
 * [UserManager.DISALLOW_CONFIG_VPN], so it cannot be switched off
 * casually; loosening from the UI is recovery-code-gated in Dart.
 *
 * This store is the single source of truth for the feature's
 * config. It is deliberately independent of every other feature:
 * nothing else reads or writes these prefs.
 */
object VpnConfigStore {
    private const val TAG = "AzmVpn"
    private const val PREFS = "azm_vpn"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_LEVEL = "level"
    private const val KEY_PACKAGES = "packages"
    private const val KEY_GROUP_IDS = "group_ids"
    private const val KEY_DOH_PROVIDER = "doh_provider"
    private const val KEY_CUSTOM_DOH_URL = "custom_doh_url"

    const val LEVEL_OFF = "off"
    const val LEVEL_APPS = "apps"
    const val LEVEL_GROUPS = "groups"
    const val LEVEL_PHONE = "phone"

    data class Config(
        val enabled: Boolean = false,
        val level: String = LEVEL_OFF,
        val packages: Set<String> = emptySet(),
        val groupIds: Set<String> = emptySet(),
        val dohProvider: String = DohClient.PROVIDER_CLEANBROWSING,
        val customDohUrl: String = "",
    ) {
        /** True when the VPN should run at all. */
        val active: Boolean get() = enabled

        /** True when packets are dropped rather than DNS-filtered. */
        val blocking: Boolean get() = level != LEVEL_OFF

        fun toMap(): Map<String, Any?> = mapOf(
            "enabled" to enabled,
            "level" to level,
            "packages" to packages.toList(),
            "groupIds" to groupIds.toList(),
            "dohProvider" to dohProvider,
            "customDohUrl" to customDohUrl,
        )

        companion object {
            fun fromMap(m: Map<*, *>): Config = Config(
                enabled = m["enabled"] as? Boolean ?: false,
                level = (m["level"] as? String)?.takeIf {
                    it == LEVEL_OFF || it == LEVEL_APPS ||
                        it == LEVEL_GROUPS || it == LEVEL_PHONE
                } ?: LEVEL_OFF,
                packages = (m["packages"] as? List<*>)
                    ?.mapNotNull { it as? String }?.toSet() ?: emptySet(),
                groupIds = (m["groupIds"] as? List<*>)
                    ?.mapNotNull { it as? String }?.toSet() ?: emptySet(),
                dohProvider = (m["dohProvider"] as? String)
                    ?.takeIf { DohClient.isKnownProvider(it) }
                    ?: DohClient.PROVIDER_CLEANBROWSING,
                customDohUrl = m["customDohUrl"] as? String ?: "",
            )
        }
    }

    fun read(context: Context): Config {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return Config(
            enabled = prefs.getBoolean(KEY_ENABLED, false),
            level = prefs.getString(KEY_LEVEL, LEVEL_OFF) ?: LEVEL_OFF,
            packages = prefs.getStringSet(KEY_PACKAGES, emptySet()) ?: emptySet(),
            groupIds = prefs.getStringSet(KEY_GROUP_IDS, emptySet()) ?: emptySet(),
            dohProvider = prefs.getString(
                KEY_DOH_PROVIDER,
                DohClient.PROVIDER_CLEANBROWSING,
            ) ?: DohClient.PROVIDER_CLEANBROWSING,
            customDohUrl = prefs.getString(KEY_CUSTOM_DOH_URL, "") ?: "",
        )
    }

    fun write(context: Context, config: Config) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_ENABLED, config.enabled)
            .putString(KEY_LEVEL, config.level)
            .putStringSet(KEY_PACKAGES, config.packages)
            .putStringSet(KEY_GROUP_IDS, config.groupIds)
            .putString(KEY_DOH_PROVIDER, config.dohProvider)
            .putString(KEY_CUSTOM_DOH_URL, config.customDohUrl)
            .apply()
    }

    /** Direct apps plus every member of the chosen groups. */
    fun effectivePackages(config: Config): Set<String> {
        val out = config.packages.toMutableSet()
        val byId = SettingsStore.groups().associateBy { it.id }
        for (id in config.groupIds) {
            byId[id]?.packageNames?.let { out += it }
        }
        return out
    }

    /**
     * Applies [config]: persists it, pins or unpins the always-on
     * VPN as Device Owner, and starts or stops the service.
     * Returns the stored config.
     */
    fun apply(context: Context, config: Config): Config {
        write(context, config)
        if (config.active) {
            pinAlwaysOn(context)
            startService(context)
        } else {
            stopService(context)
            unpinAlwaysOn(context)
        }
        return config
    }

    /**
     * Teardown path (Device Owner removal): stop the service and
     * clear the always-on pin while we are still owner, so the
     * phone is never left with a locked-down VPN pointing at Azm.
     */
    fun stopAndClear(context: Context) {
        runCatching { stopService(context) }
            .onFailure { Log.w(TAG, "stopService failed: ${it.message}") }
        runCatching { unpinAlwaysOn(context) }
            .onFailure { Log.w(TAG, "unpinAlwaysOn failed: ${it.message}") }
        write(context, read(context).copy(enabled = false))
    }

    private fun pinAlwaysOn(context: Context) {
        if (!DeviceOwnerManager.isDeviceOwner(context)) return
        val dpm = DeviceOwnerManager.dpm(context)
        val admin = DeviceOwnerManager.adminComponent(context)
        runCatching {
            dpm.setAlwaysOnVpnPackage(admin, context.packageName, true)
        }.onFailure { Log.w(TAG, "setAlwaysOnVpnPackage failed: ${it.message}") }
        runCatching {
            dpm.addUserRestriction(admin, UserManager.DISALLOW_CONFIG_VPN)
        }.onFailure { Log.w(TAG, "DISALLOW_CONFIG_VPN failed: ${it.message}") }
    }

    private fun unpinAlwaysOn(context: Context) {
        if (!DeviceOwnerManager.isDeviceOwner(context)) return
        val dpm = DeviceOwnerManager.dpm(context)
        val admin = DeviceOwnerManager.adminComponent(context)
        runCatching {
            dpm.setAlwaysOnVpnPackage(admin, null, false)
        }.onFailure { Log.w(TAG, "clear always-on failed: ${it.message}") }
        runCatching {
            dpm.clearUserRestriction(admin, UserManager.DISALLOW_CONFIG_VPN)
        }.onFailure { Log.w(TAG, "clear DISALLOW_CONFIG_VPN failed: ${it.message}") }
    }

    private fun startService(context: Context) {
        if (VpnService.prepare(context) == null) {
            context.startService(
                Intent(context, AzmVpnService::class.java)
                    .setAction(AzmVpnService.ACTION_START),
            )
        } else {
            // Consent not yet granted: the transparent activity
            // shows the system dialog, then starts the service.
            context.startActivity(
                Intent(context, VpnConsentActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    private fun stopService(context: Context) {
        context.startService(
            Intent(context, AzmVpnService::class.java)
                .setAction(AzmVpnService.ACTION_STOP),
        )
    }
}
