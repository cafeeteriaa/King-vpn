package com.kingvpn.king_vpn

import android.net.VpnService
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import org.amnezia.awg.GoBackend

/**
 * KING-owned AmneziaWG userspace adapter.
 *
 * The caller supplies the TUN Builder callback so the shared KING VPN service
 * remains the only component that decides addresses, routes, DNS, MTU and app
 * exclusions. The upstream GoBackend VpnService is deliberately not used.
 *
 * The native engine receives the already-established TUN fd and owns its data
 * plane until awgTurnOff has returned. KING retains the PFD until that barrier.
 */
class KingAmneziaWgCore private constructor() {
    private val lock = Any()
    @Volatile private var nativeHandle: Int? = null
    @Volatile private var tunDescriptor: ParcelFileDescriptor? = null
    @Volatile private var vpnService: VpnService? = null

    fun connect(
        service: VpnService,
        userspaceSettings: String,
        establishTun: () -> ParcelFileDescriptor?
    ): String = synchronized(lock) {
        check(Looper.myLooper() != Looper.getMainLooper()) {
            "AmneziaWG startup must run off the Android main thread"
        }
        require(userspaceSettings.isNotBlank()) { "AmneziaWG userspace settings are empty" }
        check(VpnService.prepare(service) == null) {
            "Android VPN permission is not granted"
        }
        check(nativeHandle == null && tunDescriptor == null) {
            "AmneziaWG is already running or has an unverified shutdown"
        }

        stopPreviousOwner(service)
        check(KingVpnEngineCoordinator.acquire(ENGINE_ID, HANDOFF_TIMEOUT_MS)) {
            "Another KING VPN engine did not release the Android VPN slot"
        }

        var descriptor: ParcelFileDescriptor? = null
        var handle: Int? = null
        try {
            val activeDescriptor = establishTun()
                ?: error("Android did not establish the AmneziaWG TUN interface")
            descriptor = activeDescriptor
            val started = GoBackend.awgTurnOn(INTERFACE_NAME, activeDescriptor.fd, userspaceSettings)
            check(started > 0) { "AmneziaWG native engine returned an invalid handle: $started" }
            handle = started

            // Protect both address-family sockets before allowing the engine to
            // continue. A failed protect is fatal: looping VPN transport is unsafe.
            val socket4 = GoBackend.awgGetSocketV4(started)
            if (socket4 >= 0) check(service.protect(socket4)) {
                "VpnService.protect failed for the AmneziaWG IPv4 transport socket"
            }
            val socket6 = GoBackend.awgGetSocketV6(started)
            if (socket6 >= 0) check(service.protect(socket6)) {
                "VpnService.protect failed for the AmneziaWG IPv6 transport socket"
            }

            vpnService = service
            tunDescriptor = descriptor
            nativeHandle = started
            descriptor = null // retained until native shutdown is confirmed
            GoBackend.awgVersion() ?: "AmneziaWG"
        } catch (failure: Throwable) {
            var nativeStopped = handle == null
            if (handle != null) {
                nativeStopped = runCatching {
                    GoBackend.awgTurnOff(handle)
                    true
                }.getOrDefault(false)
            }
            if (nativeStopped) {
                runCatching { descriptor?.close() }
                KingVpnEngineCoordinator.release(ENGINE_ID)
            } else {
                // Native state is uncertain. Keep the descriptor and ownership
                // fence so no other engine can replace a live/unknown TUN.
                tunDescriptor = descriptor
                nativeHandle = handle
                vpnService = service
            }
            throw failure
        }
    }

    fun disconnect() = synchronized(lock) {
        check(Looper.myLooper() != Looper.getMainLooper()) {
            "AmneziaWG shutdown must run off the Android main thread"
        }
        val handle = nativeHandle
        if (handle != null) {
            // Do not release ownership or close the TUN unless native confirms stop.
            GoBackend.awgTurnOff(handle)
            nativeHandle = null
        }
        tunDescriptor?.close()
        tunDescriptor = null
        vpnService = null
        KingVpnEngineCoordinator.release(ENGINE_ID)
    }

    fun state(): String = when {
        nativeHandle != null -> "UP"
        tunDescriptor != null -> "STOP_UNCONFIRMED"
        else -> "DOWN"
    }

    private fun stopPreviousOwner(service: VpnService) {
        when (val owner = KingVpnEngineCoordinator.currentOwner()) {
            null, ENGINE_ID -> Unit
            "xray" -> check(
                KingVpnService.instance?.stopForEngineHandoff(HANDOFF_TIMEOUT_MS) == true
            ) { "Xray did not confirm shutdown before AmneziaWG start" }
            "wireguard" -> KingWireGuardCore.shared(service).disconnect()
            "libbox" -> check(
                KingVpnEngineCoordinator.stopLibboxAndRelease(service, HANDOFF_TIMEOUT_MS)
            ) { "sing-box did not confirm shutdown before AmneziaWG start" }
            "amneziawg" -> Unit
            else -> error("Unknown active VPN engine owner: $owner")
        }
    }

    companion object {
        private const val ENGINE_ID = "amneziawg"
        private const val INTERFACE_NAME = "kingawg"
        private const val HANDOFF_TIMEOUT_MS = 30_000L

        @Volatile private var instance: KingAmneziaWgCore? = null

        @JvmStatic
        fun shared(): KingAmneziaWgCore = instance ?: synchronized(this) {
            instance ?: KingAmneziaWgCore().also { instance = it }
        }
    }
}
