package io.github.alnajashia.dominanter.shizuku

import android.content.Context
import android.content.pm.PackageManager
import io.github.alnajashia.dominanter.channel.ErrorCodes
import io.github.alnajashia.dominanter.channel.PrivException
import rikka.shizuku.Shizuku

/**
 * Shizuku state machine + permission flow (`docs/ARCHITECTURE.md` §5.3).
 *
 * Improvements over the original, all documented in the architecture:
 *  - pre-V11 is a **distinct state**, not silently "no permission";
 *  - the permission-result listener **verifies request code 911** and is
 *    registered/unregistered with the lifecycle (the original ignored the
 *    code and leaked the listener);
 *  - binder liveness comes from `addBinderReceivedListener` /
 *    `addBinderDeadListener`, not the original's 500 ms polling loop.
 *
 * Events are forwarded to the Flutter EventChannel through [EventSink],
 * installed by the channel handler while an engine is attached.
 */
object ShizukuGateway {

    const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"
    const val REQUEST_CODE = 911

    enum class State(val wireName: String) {
        NOT_INSTALLED("notInstalled"),
        NOT_RUNNING("notRunning"),
        PRE_V11("preV11"),
        NO_PERMISSION("noPermission"),
        GRANTED("granted"),
    }

    /** Minimal event bridge so this layer does not depend on Flutter classes. */
    fun interface EventSink {
        fun emit(type: String, payload: Map<String, Any?>)
    }

    @Volatile
    var eventSink: EventSink? = null

    private val binderReceivedListener = Shizuku.OnBinderReceivedListener {
        eventSink?.emit("shizukuBinderReceived", emptyMap())
    }
    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        eventSink?.emit("shizukuBinderDead", emptyMap())
    }
    private val permissionResultListener = Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
        // Fix vs original: the result is only honoured for OUR request code.
        if (requestCode != REQUEST_CODE) return@OnRequestPermissionResultListener
        eventSink?.emit(
            "shizukuPermissionResult",
            mapOf(
                "requestCode" to requestCode,
                "granted" to (grantResult == PackageManager.PERMISSION_GRANTED),
            ),
        )
    }

    @Volatile
    private var listenersRegistered = false

    /** Registers all Shizuku listeners. Idempotent; call from MainActivity/Application start. */
    @Synchronized
    fun registerListeners() {
        if (listenersRegistered) return
        Shizuku.addBinderReceivedListenerSticky(binderReceivedListener)
        Shizuku.addBinderDeadListener(binderDeadListener)
        Shizuku.addRequestPermissionResultListener(permissionResultListener)
        listenersRegistered = true
    }

    /** Removes all listeners (fix vs original, which never removed its listener). */
    @Synchronized
    fun unregisterListeners() {
        if (!listenersRegistered) return
        Shizuku.removeBinderReceivedListener(binderReceivedListener)
        Shizuku.removeBinderDeadListener(binderDeadListener)
        Shizuku.removeRequestPermissionResultListener(permissionResultListener)
        listenersRegistered = false
    }

    fun isInstalled(context: Context): Boolean =
        try {
            context.packageManager.getPackageInfo(SHIZUKU_PACKAGE, 0) != null
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }

    fun isBinderAlive(): Boolean = Shizuku.pingBinder()

    fun hasPermission(): Boolean {
        if (Shizuku.isPreV11()) return false
        return try {
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        } catch (_: Exception) {
            false
        }
    }

    /** The state, checked in the contract's exact order. Never throws. */
    fun state(context: Context): State {
        if (!isInstalled(context)) return State.NOT_INSTALLED
        if (!isBinderAlive()) return State.NOT_RUNNING
        return try {
            if (Shizuku.isPreV11()) return State.PRE_V11
            if (hasPermission()) State.GRANTED else State.NO_PERMISSION
        } catch (_: Exception) {
            State.NOT_RUNNING
        }
    }

    /** Full state payload for `getShizukuState`. Never throws. */
    fun statePayload(context: Context): Map<String, Any?> {
        val state = state(context)
        var serverVersion: Int? = null
        var serverUid: Int? = null
        var preV11 = false
        if (state != State.NOT_INSTALLED && state != State.NOT_RUNNING) {
            try { serverVersion = Shizuku.getVersion() } catch (_: Exception) { /* diagnostic only */ }
            try { serverUid = Shizuku.getUid() } catch (_: Exception) { /* diagnostic only */ }
            try { preV11 = Shizuku.isPreV11() } catch (_: Exception) { /* diagnostic only */ }
        }
        return mapOf(
            "state" to state.wireName,
            "serverVersion" to serverVersion,
            "serverUid" to serverUid,
            "isPreV11" to preV11,
        )
    }

    /**
     * Dispatches the permission request (the grant/deny arrives asynchronously
     * via the `shizukuPermissionResult` event). Throws the taxonomy errors for
     * the states in which a request cannot even be attempted.
     */
    fun requestPermission(context: Context) {
        when (state(context)) {
            State.NOT_INSTALLED -> throw PrivException(
                ErrorCodes.SHIZUKU_NOT_INSTALLED, "Shizuku is not installed",
            )
            State.NOT_RUNNING -> throw PrivException(
                ErrorCodes.SHIZUKU_NOT_RUNNING, "Shizuku server is not running",
            )
            State.PRE_V11 -> throw PrivException(
                ErrorCodes.SHIZUKU_PRE_V11, "Shizuku server is older than v11; update Shizuku",
            )
            else -> Shizuku.requestPermission(REQUEST_CODE)
        }
    }

    /** Throws the correct `SHIZUKU_*` error unless the state is GRANTED. */
    fun requireGranted(context: Context) {
        when (state(context)) {
            State.GRANTED -> Unit
            State.NOT_INSTALLED -> throw PrivException(
                ErrorCodes.SHIZUKU_NOT_INSTALLED, "Shizuku is not installed",
            )
            State.NOT_RUNNING -> throw PrivException(
                ErrorCodes.SHIZUKU_NOT_RUNNING, "Shizuku server is not running",
            )
            State.PRE_V11 -> throw PrivException(
                ErrorCodes.SHIZUKU_PRE_V11, "Shizuku server is older than v11; update Shizuku",
            )
            State.NO_PERMISSION -> throw PrivException(
                ErrorCodes.SHIZUKU_NO_PERMISSION, "Shizuku permission has not been granted",
            )
        }
    }

    /** The error used when a runner call could not run a command at all (no binder / pre-V11). */
    fun unavailableException(): PrivException =
        PrivException(
            ErrorCodes.SHIZUKU_NOT_RUNNING,
            "Shizuku command could not be started (no live binder, or pre-V11 server)",
        )
}
