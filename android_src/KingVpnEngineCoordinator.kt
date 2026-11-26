package com.kingvpn.king_vpn

import java.util.concurrent.TimeUnit

/**
 * Process-wide ownership fence for Android's single active VPN/TUN slot.
 * A full-device engine acquires ownership before creating TUN and releases it
 * only after its native runtime has stopped and its descriptor is closed.
 */
object KingVpnEngineCoordinator {
    private val monitor = Object()

    @Volatile
    private var activeOwner: String? = null

    @JvmStatic
    fun currentOwner(): String? = activeOwner

    @JvmStatic
    fun acquire(engine: String, timeoutMs: Long): Boolean {
        require(engine.isNotBlank()) { "Engine id must not be blank" }
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs.coerceAtLeast(0L))
        synchronized(monitor) {
            while (activeOwner != null && activeOwner != engine) {
                val remaining = deadline - System.nanoTime()
                if (remaining <= 0L) return false
                val waitMs = TimeUnit.NANOSECONDS.toMillis(remaining).coerceAtLeast(1L)
                try {
                    monitor.wait(waitMs)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return false
                }
            }
            activeOwner = engine
            return true
        }
    }

    @JvmStatic
    fun release(engine: String) {
        synchronized(monitor) {
            if (activeOwner == engine) {
                activeOwner = null
                monitor.notifyAll()
            }
        }
    }
}
