package com.alnajashia.azm.vpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle

/**
 * Transparent trampoline for the one-time system VPN consent
 * dialog. When Azm is Device Owner with the always-on pin set,
 * [VpnService.prepare] normally returns null (already consented)
 * and this activity just starts the service and finishes.
 */
class VpnConsentActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val consent = VpnService.prepare(this)
        if (consent == null) {
            startVpn()
            finish()
        } else {
            @Suppress("DEPRECATION")
            startActivityForResult(consent, REQUEST_CONSENT)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CONSENT && resultCode == RESULT_OK) {
            startVpn()
        }
        finish()
    }

    private fun startVpn() {
        startService(
            Intent(this, AzmVpnService::class.java)
                .setAction(AzmVpnService.ACTION_START),
        )
    }

    companion object {
        private const val REQUEST_CONSENT = 41
    }
}
