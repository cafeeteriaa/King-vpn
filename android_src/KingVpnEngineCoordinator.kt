package com.kingvpn.king_vpn

import android.content.Context
import android.content.Intent
import android.os.Looper
import com.qusadprod.sing_box.core.ServiceState
import com.qusadprod.sing_box.core.ServiceStatus
import com.qusadprod.sing_box.service.SingBoxVpnService
import java.util.concurrent.CountDownLatch
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


    /** Native stop barrier: release TUN only after ServiceState reports Stopped. */
    @JvmStatic
    fun stopLibboxAndRelease(context: Context, timeoutMs: Long): Boolean {
        check(Looper.myLooper() != Looper.getMainLooper()) {
            "libbox shutdown must not block the Android main thread"
        }
        val latch = CountDownLatch(1)
        val listener = ServiceState.Listener { snapshot ->
            if (snapshot.status == ServiceStatus.Stopped) {
                release("libbox")
                latch.countDown()
            }
        }
        ServiceState.addListener(listener)
        try {
            if (ServiceState.status == ServiceStatus.Stopped) {
                release("libbox")
                return true
            }
            context.stopService(Intent(context, SingBoxVpnService::class.java))
            if (ServiceState.status == ServiceStatus.Stopped) {
                release("libbox")
                return true
            }
            val done = latch.await(timeoutMs.coerceAtLeast(0L), TimeUnit.MILLISECONDS)
            if (done) release("libbox")
            return done
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            return false
        } finally {
            ServiceState.removeListener(listener)
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
