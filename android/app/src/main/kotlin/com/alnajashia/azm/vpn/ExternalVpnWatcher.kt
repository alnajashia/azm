package com.alnajashia.azm.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.util.Log
import com.alnajashia.azm.deviceowner.DeviceOwnerManager
import java.util.concurrent.Executors

/**
 * "DNS via VPN" for external VPN apps (user request 2026-11-22).
 *
 * Android allows exactly one active VPN at a time, so while another
 * app's VPN is up, Azm's own VPN cannot run and Azm cannot filter
 * DNS inside that app's tunnel — no app can. What Azm CAN do is
 * apply the user's chosen provider as system Private DNS (DoT)
 * while the external VPN is up: the DoT connection then travels
 * through the tunnel, where port 853 is usually reachable even on
 * networks that block it directly. Whether filtering truly takes
 * effect still depends on the external VPN app's own DNS handling;
 * this is the maximum the platform allows, and it is best-effort.
 *
 * [sync] is the single idempotent reconciler: it compares the
 * desired state (config's dnsAutoHost + an external VPN being up)
 * with what Azm last applied (tracked in prefs) and applies or
 * resets Private DNS only on a real transition. It runs on its own
 * thread because setPrivateDns performs a blocking TLS check.
 * Registered from the accessibility service (Azm's always-on
 * component) and also invoked from [VpnConfigStore.apply] so a
 * config change takes effect even when no network event fires.
 */
object ExternalVpnWatcher {
    private const val TAG = "AzmVpn"
    private const val PREFS = "azm_vpn"
    private const val KEY_DOT_APPLIED = "external_vpn_dot_applied"

    private val executor = Executors.newSingleThreadExecutor()

    @Volatile
    private var registered = false

    @Volatile
    private var appContext: Context? = null

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            appContext?.let { sync(it) }
        }

        override fun onLost(network: Network) {
            appContext?.let { sync(it) }
        }
    }

    /** Starts watching for VPN networks. Safe to call repeatedly. */
    fun register(context: Context) {
        val ctx = context.applicationContext
        appContext = ctx
        if (!registered) {
            val cm = ctx.getSystemService(ConnectivityManager::class.java)
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_VPN)
                .build()
            runCatching { cm.registerNetworkCallback(request, callback) }
                .onSuccess { registered = true }
                .onFailure { Log.w(TAG, "VPN watch register failed: ${it.message}") }
        }
        sync(ctx)
    }

    fun unregister(context: Context) {
        if (!registered) return
        val cm = context.applicationContext
            .getSystemService(ConnectivityManager::class.java)
        runCatching { cm.unregisterNetworkCallback(callback) }
        registered = false
    }

    /** Reconciles the applied Private DNS with the desired state. */
    fun sync(context: Context) {
        val ctx = context.applicationContext
        appContext = ctx
        executor.execute { runCatching { reconcile(ctx) } }
    }

    private fun reconcile(context: Context) {
        val config = VpnConfigStore.read(context)
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val applied = prefs.getBoolean(KEY_DOT_APPLIED, false)
        val wantApplied = config.dnsAutoHost.isNotBlank() && isExternalVpnUp(context)
        if (wantApplied && !applied) {
            // Best-effort: requires Device Owner; a failure (not
            // owner, host not serving through this tunnel) simply
            // leaves the flag unset and the next sync retries.
            runCatching {
                DeviceOwnerManager.setPrivateDns(context, config.dnsAutoHost)
            }.onSuccess {
                prefs.edit().putBoolean(KEY_DOT_APPLIED, true).apply()
                Log.i(TAG, "External VPN up: Private DNS set to ${config.dnsAutoHost}")
            }.onFailure {
                Log.w(TAG, "External VPN Private DNS apply failed: ${it.message}")
            }
        } else if (!wantApplied && applied) {
            // Only ever reset a host Azm itself applied (the flag
            // proves it) — a Private DNS the user set by hand is
            // never touched.
            runCatching { DeviceOwnerManager.resetPrivateDns(context) }
                .onSuccess {
                    prefs.edit().putBoolean(KEY_DOT_APPLIED, false).apply()
                    Log.i(TAG, "External VPN gone: Private DNS reset")
                }
                .onFailure {
                    Log.w(TAG, "External VPN Private DNS reset failed: ${it.message}")
                }
        }
    }

    /**
     * True when a VPN network exists that is not Azm's own. Android
     * runs one VPN at a time, so any VPN network while Azm's
     * service is not running belongs to another app.
     */
    private fun isExternalVpnUp(context: Context): Boolean {
        if (AzmVpnService.isRunning) return false
        val cm = context.getSystemService(ConnectivityManager::class.java)
        return cm.allNetworks.any { network ->
            cm.getNetworkCapabilities(network)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        }
    }
}
