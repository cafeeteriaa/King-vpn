package com.kingvpn.king_vpn

import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock

/**
 * Process-wide ownership fence for Android's single active VPN/TUN slot.
 * A full-device engine acquires ownership before creating TUN and releases it
 * only after its native runtime has stopped and its descriptor is closed.
 */
object KingVpnEngineCoordinator {
    private val lock = ReentrantLock()
    private val released = lock.newCondition()

    @Volatile
    private var activeOwner: String? = null

    @JvmStatic
    fun currentOwner(): String? = activeOwner

    @JvmStatic
    fun acquire(engine: String, timeoutMs: Long): Boolean {
        require(engine.isNotBlank()) { "Engine id must not be blank" }
        var remaining = TimeUnit.MILLISECONDS.toNanos(timeoutMs.coerceAtLeast(0L))
        lock.lock()
        try {
            while (activeOwner != null && activeOwner != engine) {
                if (remaining <= 0L) return false
                try {
                    remaining = released.awaitNanos(remaining)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return false
                }
            }
            activeOwner = engine
            return true
        } finally {
            lock.unlock()
        }
    }

    @JvmStatic
    fun release(engine: String) {
        lock.lock()
        try {
            if (activeOwner == engine) {
                activeOwner = null
                released.signalAll()
            }
        } finally {
            lock.unlock()
        }
    }
}
