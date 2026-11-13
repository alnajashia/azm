package com.alnajashia.azm

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import com.alnajashia.azm.channel.PrivilegedChannelHandler
import com.alnajashia.azm.shizuku.ShizukuGateway
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * The Flutter host Activity. It extends [FlutterFragmentActivity] — NOT the
 * plain FlutterActivity — because the `local_auth` plugin's Android
 * BiometricPrompt requires a FragmentActivity host; with FlutterActivity
 * the "Access app" fingerprint prompt silently never appears (user report
 * 2026-11-09, fixed the same day). Do not downgrade this superclass.
 *
 * Its native jobs:
 *
 *  - register the platform channels (`azm/privileged` +
 *    `azm/privileged/events`) via [PrivilegedChannelHandler];
 *  - register Shizuku's listeners (binder received/dead + permission result,
 *    request code **911** verified in [ShizukuGateway]) — and **remove them
 *    symmetrically when the engine is cleaned up**. The original registered
 *    its permission listener in composition and never removed it; that leak
 *    is fixed here (registration in [ShizukuGateway] is idempotent, and
 *    removal happens only for the listeners this Activity registered).
 *  - host the `POST_NOTIFICATIONS` runtime request for the channel's
 *    `requestNotificationPermission` method ([NotificationPermissionBridge]):
 *    a runtime permission can only be requested from an Activity, and the
 *    channel handler owns none. This bridge is the only addition for that
 *    path — attach/detach in [onCreate]/[onDestroy], result delivery in
 *    [onRequestPermissionsResult].
 */
class MainActivity : FlutterFragmentActivity() {

    private var channelHandler: PrivilegedChannelHandler? = null
    private var registeredListenersHere = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NotificationPermissionBridge.attach(this)
        WindowSecurityBridge.attach(this)
    }

    override fun onDestroy() {
        WindowSecurityBridge.detach(this)
        NotificationPermissionBridge.detach(this)
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        NotificationPermissionBridge.onResult(requestCode)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ShizukuGateway.registerListeners()
        registeredListenersHere = true
        channelHandler = PrivilegedChannelHandler(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.attach() }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channelHandler?.detach()
        channelHandler = null
        if (registeredListenersHere) {
            // Symmetric with configureFlutterEngine: no leaked listeners.
            // ShizukuGateway.unregisterListeners() removes exactly the three
            // listeners this process registered (permission result incl. 911).
            ShizukuGateway.unregisterListeners()
            registeredListenersHere = false
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

/**
 * Bridges the channel's `requestNotificationPermission` call to the host
 * Activity's runtime-permission flow (Android 13+). The channel handler
 * runs on a background executor; [request] posts the actual
 * `requestPermissions` call to the main thread and waits (bounded) for
 * [MainActivity.onRequestPermissionsResult] to release it, then re-reads
 * the permission state as the source of truth — a timeout or a dismissed
 * dialog simply reports the current (ungranted) state, never a fake grant.
 */
object NotificationPermissionBridge {
    private const val REQUEST_CODE = 7331
    private const val TIMEOUT_SECONDS = 60L

    @Volatile
    private var activity: MainActivity? = null

    @Volatile
    private var pendingLatch: CountDownLatch? = null

    fun attach(a: MainActivity) {
        activity = a
    }

    fun detach(a: MainActivity) {
        if (activity === a) activity = null
    }

    /** The attached host activity, or null when no UI is alive. */
    fun currentActivity(): MainActivity? = activity

    /**
     * Requests `POST_NOTIFICATIONS` from [a]. Must be called off the main
     * thread (it blocks until the user answers or the timeout lapses).
     * Returns whether the permission is granted when the flow settles.
     */
    fun request(a: MainActivity): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        val latch = CountDownLatch(1)
        pendingLatch = latch
        Handler(Looper.getMainLooper()).post {
            try {
                a.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_CODE)
            } catch (e: Exception) {
                latch.countDown()
            }
        }
        try {
            latch.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
            // Fall through and report the current state.
        }
        pendingLatch = null
        return a.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    /** Releases a pending [request]; returns true when the code was ours. */
    fun onResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pendingLatch?.countDown()
        return true
    }
}

/**
 * Bridges the channel's `setWindowSecure` call to the host Activity's window
 * (v1.0.6 UX / Audit 12.1). When secure is true, sets WindowManager.LayoutParams.FLAG_SECURE;
 * when false, clears it. Must be executed on the UI thread.
 */
object WindowSecurityBridge {
    @Volatile
    private var activity: MainActivity? = null

    fun attach(act: MainActivity) {
        activity = act
    }

    fun detach(act: MainActivity) {
        if (activity === act) {
            activity = null
        }
    }

    fun setSecure(enabled: Boolean) {
        val act = activity ?: return
        act.runOnUiThread {
            if (enabled) {
                act.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                act.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
        }
    }
}

