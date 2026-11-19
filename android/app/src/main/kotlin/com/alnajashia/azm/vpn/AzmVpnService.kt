package com.alnajashia.azm.vpn

import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * The local, no-configuration VPN (user order 2026-11-19).
 *
 * Modes, from [VpnConfigStore.Config]:
 *  - DNS filtering (level off): only DNS traffic is routed into
 *    the TUN (a fake DNS server address); each query is answered
 *    over DoH on port 443 by [DohClient]. All other traffic
 *    bypasses the VPN untouched.
 *  - App / group block: only the chosen apps' traffic enters the
 *    TUN and is dropped — the apps still run, without internet.
 *  - Whole-phone block: all traffic enters the TUN and is dropped
 *    (Azm itself is excluded so its own sockets keep working).
 *
 * While a block level is active, DNS filtering for other apps is
 * inactive (Android routes either the chosen apps or everything
 * into one VPN — the UI states this honestly).
 *
 * Failure posture is fail-closed: a DoH failure drops the query;
 * with the Device Owner always-on lockdown pin, a dead service
 * blocks traffic instead of leaking it, and the system restarts
 * the service.
 */
class AzmVpnService : VpnService() {
    private var tun: ParcelFileDescriptor? = null
    private var readerThread: Thread? = null
    @Volatile private var running = false
    private val dnsPool = Executors.newCachedThreadPool { r ->
        Thread(r, "azm-vpn-dns").apply { isDaemon = true }
    }
    private val writeLock = Any()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            teardown()
            stopSelf()
            return START_NOT_STICKY
        }
        val config = VpnConfigStore.read(this)
        if (!config.active) {
            teardown()
            stopSelf()
            return START_NOT_STICKY
        }
        establish(config)
        return START_STICKY
    }

    override fun onRevoke() {
        teardown()
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        teardown()
        super.onDestroy()
    }

    private fun establish(config: VpnConfigStore.Config) {
        teardown()
        val builder = Builder()
            .setSession("Azm")
            .setBlocking(true)
            .addAddress(TUN_ADDRESS_V4, 32)
            .addDnsServer(DNS_ADDRESS)
        when (config.level) {
            VpnConfigStore.LEVEL_APPS, VpnConfigStore.LEVEL_GROUPS -> {
                builder.addAddress(TUN_ADDRESS_V6, 128)
                builder.addRoute("0.0.0.0", 0)
                builder.addRoute("::", 0)
                for (pkg in VpnConfigStore.effectivePackages(config)) {
                    try {
                        builder.addAllowedApplication(pkg)
                    } catch (e: PackageManager.NameNotFoundException) {
                        Log.w(TAG, "blocked app not installed: $pkg")
                    }
                }
            }
            VpnConfigStore.LEVEL_PHONE -> {
                builder.addAddress(TUN_ADDRESS_V6, 128)
                builder.addRoute("0.0.0.0", 0)
                builder.addRoute("::", 0)
                try {
                    builder.addDisallowedApplication(packageName)
                } catch (e: PackageManager.NameNotFoundException) {
                    Log.w(TAG, "own package lookup failed: ${e.message}")
                }
            }
            else -> {
                // DNS filtering only: route just the fake DNS server.
                builder.addRoute(DNS_ADDRESS, 32)
            }
        }
        val fd = try {
            builder.establish()
        } catch (e: Exception) {
            Log.w(TAG, "establish failed: ${e.message}")
            null
        }
        if (fd == null) {
            Log.w(TAG, "VPN interface could not be established")
            stopSelf()
            return
        }
        tun = fd
        running = true
        isRunning = true
        val filterDns = !config.blocking
        readerThread = Thread({ readLoop(fd, config, filterDns) }, "azm-vpn-reader")
            .apply { isDaemon = true; start() }
        Log.i(TAG, "VPN established (level=${config.level})")
    }

    private fun readLoop(
        fd: ParcelFileDescriptor,
        config: VpnConfigStore.Config,
        filterDns: Boolean,
    ) {
        val input = FileInputStream(fd.fileDescriptor)
        val buffer = ByteArray(MAX_PACKET)
        while (running) {
            val length = try {
                input.read(buffer)
            } catch (e: Exception) {
                if (running) Log.w(TAG, "TUN read failed: ${e.message}")
                break
            }
            if (length <= 0) continue
            if (!filterDns) continue // block modes: drop everything
            val packet = buffer.copyOf(length)
            val query = parseDnsQuery(packet) ?: continue
            dnsPool.execute { answerDns(fd, config, query) }
        }
    }

    private fun answerDns(
        fd: ParcelFileDescriptor,
        config: VpnConfigStore.Config,
        query: DnsQuery,
    ) {
        val endpoint = DohClient.endpoint(config.dohProvider, config.customDohUrl)
            ?: return
        val response = DohClient.query({ socket -> protect(socket) }, endpoint, query.payload)
            ?: return // fail-closed: drop the query
        val packet = buildDnsResponse(query, response)
        synchronized(writeLock) {
            try {
                FileOutputStream(fd.fileDescriptor).write(packet)
            } catch (e: Exception) {
                if (running) Log.w(TAG, "TUN write failed: ${e.message}")
            }
        }
    }

    private fun teardown() {
        running = false
        isRunning = false
        readerThread?.interrupt()
        readerThread = null
        try {
            tun?.close()
        } catch (e: Exception) {
            Log.w(TAG, "TUN close failed: ${e.message}")
        }
        tun = null
    }

    // ------------------------------------------------------------ packets

    private class DnsQuery(
        val srcAddress: ByteArray,
        val dstAddress: ByteArray,
        val srcPort: Int,
        val payload: ByteArray,
    )

    /** Extracts a UDP/53 payload from an IPv4 packet, or null. */
    private fun parseDnsQuery(packet: ByteArray): DnsQuery? {
        if (packet.size < 28) return null
        val version = (packet[0].toInt() shr 4) and 0xF
        if (version != 4) return null
        val ihl = (packet[0].toInt() and 0xF) * 4
        if (ihl < 20 || packet.size < ihl + 8) return null
        if (packet[9].toInt() != 17) return null // UDP only
        val srcPort = u16(packet, ihl)
        val dstPort = u16(packet, ihl + 2)
        if (dstPort != 53) return null
        val udpLength = u16(packet, ihl + 4)
        val payloadLength = udpLength - 8
        if (payloadLength <= 0 || ihl + 8 + payloadLength > packet.size) return null
        return DnsQuery(
            srcAddress = packet.copyOfRange(12, 16),
            dstAddress = packet.copyOfRange(16, 20),
            srcPort = srcPort,
            payload = packet.copyOfRange(ihl + 8, ihl + 8 + payloadLength),
        )
    }

    private fun buildDnsResponse(query: DnsQuery, dnsResponse: ByteArray): ByteArray {
        val totalLength = 20 + 8 + dnsResponse.size
        val packet = ByteArray(totalLength)
        packet[0] = 0x45 // IPv4, IHL 5
        packet[1] = 0
        put16(packet, 2, totalLength)
        put16(packet, 4, 0) // identification
        put16(packet, 6, 0) // flags + fragment offset
        packet[8] = 64 // TTL
        packet[9] = 17 // UDP
        System.arraycopy(query.dstAddress, 0, packet, 12, 4)
        System.arraycopy(query.srcAddress, 0, packet, 16, 4)
        put16(packet, 10, ipChecksum(packet, 20))
        put16(packet, 20, 53)
        put16(packet, 22, query.srcPort)
        put16(packet, 24, 8 + dnsResponse.size)
        put16(packet, 26, 0) // UDP checksum 0 = not computed (valid for IPv4)
        System.arraycopy(dnsResponse, 0, packet, 28, dnsResponse.size)
        return packet
    }

    private fun u16(data: ByteArray, offset: Int): Int =
        ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)

    private fun put16(data: ByteArray, offset: Int, value: Int) {
        data[offset] = ((value shr 8) and 0xFF).toByte()
        data[offset + 1] = (value and 0xFF).toByte()
    }

    private fun ipChecksum(header: ByteArray, length: Int): Int {
        var sum = 0
        var i = 0
        while (i < length) {
            sum += u16(header, i)
            i += 2
        }
        while (sum shr 16 != 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        return sum.inv() and 0xFFFF
    }

    companion object {
        private const val TAG = "AzmVpn"
        private const val MAX_PACKET = 32767
        private const val TUN_ADDRESS_V4 = "10.111.222.2"
        private const val TUN_ADDRESS_V6 = "fd00:1::2"
        private const val DNS_ADDRESS = "10.111.222.1"

        const val ACTION_START = "com.alnajashia.azm.vpn.START"
        const val ACTION_STOP = "com.alnajashia.azm.vpn.STOP"

        @Volatile var isRunning: Boolean = false
            private set
    }
}
