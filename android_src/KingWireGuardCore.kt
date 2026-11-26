package com.kingvpn.king_vpn

import android.content.Context
import android.net.VpnService
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import java.io.ByteArrayInputStream
import java.nio.charset.StandardCharsets

/**
 * Independent WireGuard userspace engine.
 * It owns a GoBackend instance and never routes WireGuard profiles through Xray.
 * Android has one active VPN slot per app, so callers must stop another VPN
 * engine before bringing this engine UP.
 */
class KingWireGuardCore private constructor(context: Context) {
    private val appContext = context.applicationContext
    private val backend = GoBackend(appContext)
    @Volatile private var lastState = Tunnel.State.DOWN
    private val tunnel = object : Tunnel {
        override fun getName(): String = "kingwg"
        override fun onStateChange(newState: Tunnel.State) { lastState = newState }
    }

    @Synchronized
    fun connect(rawConfig: String): String {
        require(rawConfig.contains("[Interface]", ignoreCase = true) &&
                rawConfig.contains("[Peer]", ignoreCase = true)) {
            "WireGuard config must contain [Interface] and [Peer] sections"
        }
        check(VpnService.prepare(appContext) == null) {
            "Android VPN permission is not granted; request it before starting WireGuard"
        }
        val config = ByteArrayInputStream(rawConfig.toByteArray(StandardCharsets.UTF_8)).use {
            Config.parse(it)
        }
        if (KingVpnEngineCoordinator.currentOwner() == "xray") {
            KingVpnService.instance?.stopForEngineHandoff()
        }
        check(KingVpnEngineCoordinator.acquire("wireguard", 30_000L)) {
            "Another KING VPN engine did not release the Android VPN slot"
        }
        try {
            backend.setState(tunnel, Tunnel.State.UP, config)
            check(backend.getState(tunnel) == Tunnel.State.UP) {
                "WireGuard backend did not enter UP state"
            }
            lastState = Tunnel.State.UP
            return backend.version
        } catch (failure: Throwable) {
            if (runCatching { backend.getState(tunnel) }.getOrNull() != Tunnel.State.UP) {
                KingVpnEngineCoordinator.release("wireguard")
            }
            throw failure
        }
    }

    @Synchronized
    fun disconnect() {
        if (backend.getState(tunnel) == Tunnel.State.UP) {
            backend.setState(tunnel, Tunnel.State.DOWN, null)
        }
        check(backend.getState(tunnel) == Tunnel.State.DOWN) {
            "WireGuard backend did not confirm DOWN state; retaining VPN ownership"
        }
        lastState = Tunnel.State.DOWN
        KingVpnEngineCoordinator.release("wireguard")
    }

    @Synchronized
    fun state(): String = backend.getState(tunnel).name.also {
        lastState = Tunnel.State.valueOf(it)
        if (lastState == Tunnel.State.DOWN) {
            KingVpnEngineCoordinator.release("wireguard")
        }
    }

    companion object {
        @Volatile private var instance: KingWireGuardCore? = null
        @JvmStatic
        fun shared(context: Context): KingWireGuardCore = instance ?: synchronized(this) {
            instance ?: KingWireGuardCore(context).also { instance = it }
        }
    }
}
