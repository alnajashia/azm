package io.github.alnajashia.dominanter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.github.alnajashia.dominanter.channel.PrivilegedChannelHandler
import io.github.alnajashia.dominanter.shizuku.ShizukuGateway

/**
 * The Flutter host Activity. Its only native jobs:
 *
 *  - register the platform channels (`dominanter/privileged` +
 *    `dominanter/privileged/events`) via [PrivilegedChannelHandler];
 *  - register Shizuku's listeners (binder received/dead + permission result,
 *    request code **911** verified in [ShizukuGateway]) — and **remove them
 *    symmetrically when the engine is cleaned up**. The original registered
 *    its permission listener in composition and never removed it; that leak
 *    is fixed here (registration in [ShizukuGateway] is idempotent, and
 *    removal happens only for the listeners this Activity registered).
 */
class MainActivity : FlutterActivity() {

    private var channelHandler: PrivilegedChannelHandler? = null
    private var registeredListenersHere = false

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
