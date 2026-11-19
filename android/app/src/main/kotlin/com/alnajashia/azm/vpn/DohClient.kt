package com.alnajashia.azm.vpn

import android.util.Log
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.Socket
import java.net.URL
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLSocketFactory

/**
 * DNS-over-HTTPS (RFC 8484) client for the VPN DNS filter.
 *
 * Endpoints verified against the providers' own documentation
 * (2026-11-19): CleanBrowsing Family, AdGuard Family and
 * Cloudflare Family all answer RFC 8484 wire-format queries.
 *
 * Sockets are created through [ProtectedSocketFactory] so the
 * VpnService can `protect()` them — without that, the DoH request
 * itself would loop back into the TUN.
 */
object DohClient {
    private const val TAG = "AzmVpn"

    const val PROVIDER_CLEANBROWSING = "cleanBrowsing"
    const val PROVIDER_ADGUARD = "adguard"
    const val PROVIDER_CLOUDFLARE = "cloudflare"
    const val PROVIDER_CUSTOM = "custom"

    private const val CLEANBROWSING_URL =
        "https://doh.cleanbrowsing.org/doh/family-filter/"
    private const val ADGUARD_URL = "https://family.adguard-dns.com/dns-query"
    private const val CLOUDFLARE_URL =
        "https://family.cloudflare-dns.com/dns-query"

    fun isKnownProvider(value: String): Boolean =
        value == PROVIDER_CLEANBROWSING || value == PROVIDER_ADGUARD ||
            value == PROVIDER_CLOUDFLARE || value == PROVIDER_CUSTOM

    /** The DoH endpoint for [provider]; null when unusable. */
    fun endpoint(provider: String, customUrl: String): String? = when (provider) {
        PROVIDER_CLEANBROWSING -> CLEANBROWSING_URL
        PROVIDER_ADGUARD -> ADGUARD_URL
        PROVIDER_CLOUDFLARE -> CLOUDFLARE_URL
        PROVIDER_CUSTOM -> customUrl.trim().takeIf {
            it.startsWith("https://") && it.length > "https://".length
        }
        else -> null
    }

    /**
     * Sends one DNS wire-format query and returns the wire-format
     * response, or null on any failure (the caller drops the query —
     * fail-closed, matching the app's protection intent).
     */
    fun query(
        protect: (Socket) -> Boolean,
        endpoint: String,
        dnsMessage: ByteArray,
    ): ByteArray? {
        var connection: HttpsURLConnection? = null
        return try {
            connection = URL(endpoint).openConnection() as HttpsURLConnection
            connection.sslSocketFactory =
                ProtectedSocketFactory(protect, connection.sslSocketFactory)
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            connection.setRequestProperty("Content-Type", "application/dns-message")
            connection.setRequestProperty("Accept", "application/dns-message")
            connection.outputStream.use { it.write(dnsMessage) }
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                Log.w(TAG, "DoH HTTP ${connection.responseCode} from $endpoint")
                null
            } else {
                connection.inputStream.use { it.readBytes() }
            }
        } catch (e: Exception) {
            Log.w(TAG, "DoH query failed: ${e.message}")
            null
        } finally {
            connection?.disconnect()
        }
    }

    /**
     * SSLSocketFactory whose sockets are handed to [protect] before
     * connecting, so DoH traffic bypasses the VPN TUN.
     */
    private class ProtectedSocketFactory(
        private val protect: (Socket) -> Boolean,
        private val delegate: SSLSocketFactory,
    ) : SSLSocketFactory() {
        override fun createSocket(): Socket {
            val socket = Socket()
            protect(socket)
            return socket
        }

        override fun createSocket(host: String, port: Int): Socket {
            val socket = createSocket()
            socket.connect(java.net.InetSocketAddress(host, port), 5000)
            return socket
        }

        override fun createSocket(host: String, port: Int, localHost: InetAddress, localPort: Int): Socket {
            val socket = createSocket()
            socket.bind(java.net.InetSocketAddress(localHost, localPort))
            socket.connect(java.net.InetSocketAddress(host, port), 5000)
            return socket
        }

        override fun createSocket(host: InetAddress, port: Int): Socket {
            val socket = createSocket()
            socket.connect(java.net.InetSocketAddress(host, port), 5000)
            return socket
        }

        override fun createSocket(address: InetAddress, port: Int, localAddress: InetAddress, localPort: Int): Socket {
            val socket = createSocket()
            socket.bind(java.net.InetSocketAddress(localAddress, localPort))
            socket.connect(java.net.InetSocketAddress(address, port), 5000)
            return socket
        }

        override fun createSocket(s: Socket, host: String, port: Int, autoClose: Boolean): Socket =
            delegate.createSocket(s, host, port, autoClose)

        override fun getDefaultCipherSuites(): Array<String> = delegate.defaultCipherSuites

        override fun getSupportedCipherSuites(): Array<String> = delegate.supportedCipherSuites
    }
}
