package com.kingvpn.king_vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.nekohasekai.libbox.BoxService
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.TunOptions

// SINGBOX: پل Flutter ↔ هسته sing-box (libbox). کانال: king/singbox
// متدها: start(config) -> bool | stop() | alive() -> bool
object SingboxBridge {
    private const val TAG = "SingboxBridge"
    private const val CHANNEL = "king/singbox"

    fun register(ctx: Context, messenger: BinaryMessenger) {
        val ui = Handler(Looper.getMainLooper())
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        val cfg = call.argument<String>("config") ?: ""
                        Thread {
                            val ok = try {
                                SingboxVpnService.start(ctx, cfg)
                            } catch (t: Throwable) {
                                Log.e(TAG, "start failed", t)
                                false
                            }
                            ui.post { result.success(ok) }
                        }.start()
                    }
                    "stop" -> {
                        SingboxVpnService.stop()
                        result.success(true)
                    }
                    "alive" -> result.success(SingboxVpnService.isAlive())
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("SINGBOX_ERROR", t.message, t.stackTraceToString())
            }
        }
    }
}

// سرویس VPN مخصوص sing-box. مجوز VPN را از Dart می‌گیرد (v2ray.requestPermission
// قبل از شروع اجرا می‌شود)، پس کاربر دوباره مجوز نمی‌بیند.
class SingboxVpnService : VpnService() {

    companion object {
        private const val TAG = "SingboxVpnService"
        private const val EXTRA_CONFIG = "config"
        private const val CHANNEL_ID = "king_singbox"
        private const val NOTIF_ID = 43

        private const val STATE_IDLE = 0
        private const val STATE_STARTING = 1
        private const val STATE_RUNNING = 2
        private const val STATE_FAILED = 3

        @Volatile private var service: SingboxVpnService? = null
        @Volatile private var box: BoxService? = null
        @Volatile private var state = STATE_IDLE
        @Volatile var lastError = ""

        fun isAlive(): Boolean = state == STATE_RUNNING && box != null

        fun start(ctx: Context, config: String): Boolean {
            if (VpnService.prepare(ctx) != null) {
                lastError = "VPN permission not granted"
                return false
            }
            stop()
            lastError = ""
            state = STATE_STARTING
            val i = Intent(ctx, SingboxVpnService::class.java).putExtra(EXTRA_CONFIG, config)
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
            val deadline = System.currentTimeMillis() + 20_000L
            while (state == STATE_STARTING && System.currentTimeMillis() < deadline) {
                Thread.sleep(150)
            }
            if (state != STATE_RUNNING && lastError.isEmpty()) lastError = "timeout"
            return state == STATE_RUNNING
        }

        fun stop() {
            try {
                box?.close()
            } catch (t: Throwable) {
                Log.w(TAG, "box close", t)
            }
            box = null
            state = STATE_IDLE
            service?.stopSelf()
        }
    }

    override fun onCreate() {
        super.onCreate()
        service = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        foreground()
        val cfg = intent?.getStringExtra(EXTRA_CONFIG) ?: ""
        Thread {
            try {
                try {
                    Libbox.setup(filesDir.absolutePath, cacheDir.absolutePath, cacheDir.absolutePath, false)
                } catch (t: Throwable) {
                    Log.w(TAG, "libbox setup", t)
                }
                val svc = Libbox.newService(cfg, SingboxPlatform(this))
                svc.start()
                box = svc
                state = STATE_RUNNING
            } catch (t: Throwable) {
                Log.e(TAG, "sing-box start failed", t)
                lastError = t.message ?: t.toString()
                state = STATE_FAILED
                stop()
            }
        }.start()
        return START_NOT_STICKY
    }

    override fun onRevoke() {
        stop()
        super.onRevoke()
    }

    override fun onDestroy() {
        if (service === this) service = null
        try {
            box?.close()
        } catch (_: Throwable) {
        }
        box = null
        super.onDestroy()
    }

    fun buildTun(options: TunOptions): Int {
        if (VpnService.prepare(this) != null) throw IllegalStateException("VPN permission missing")
        val b = VpnService.Builder()
        b.setSession("King VPN (sing-box)")
        b.setMtu(options.getMTU())

        val v4 = options.getInet4Address()
        while (v4.hasNext()) {
            val p = v4.next()
            b.addAddress(p.address(), p.prefix())
        }
        val v6 = options.getInet6Address()
        while (v6.hasNext()) {
            val p = v6.next()
            try {
                b.addAddress(p.address(), p.prefix())
            } catch (_: Exception) {
            }
        }

        if (options.getAutoRoute()) {
            val r4 = options.getInet4RouteAddress()
            if (r4.hasNext()) {
                while (r4.hasNext()) {
                    val p = r4.next()
                    b.addRoute(p.address(), p.prefix())
                }
            } else {
                b.addRoute("0.0.0.0", 0)
            }

            val r6 = options.getInet6RouteAddress()
            if (r6.hasNext()) {
                while (r6.hasNext()) {
                    val p = r6.next()
                    try {
                        b.addRoute(p.address(), p.prefix())
                    } catch (_: Exception) {
                    }
                }
            } else {
                try {
                    b.addRoute("::", 0)
                } catch (_: Exception) {
                }
            }

            try {
                b.addDisallowedApplication(packageName)
            } catch (_: Exception) {
            }
        }

        val pfd = b.establish() ?: throw IllegalStateException("establish() returned null")
        // مالکیت fd به libbox می‌رسد؛ با detach دوبار بسته نمی‌شود
        return pfd.detachFd()
    }

    private fun foreground() {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "King VPN", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val nb = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        val notif = nb
            .setContentTitle("King VPN (sing-box)")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }
}

// پیاده‌سازی PlatformInterface برای libbox.
private class SingboxPlatform(private val svc: SingboxVpnService) : PlatformInterface {

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        if (!svc.protect(fd)) throw IllegalStateException("protect($fd) failed")
    }

    override fun openTun(options: TunOptions): Int = svc.buildTun(options)

    // متدهای الزامی رابط PlatformInterface در libbox (نسخه ۱.۱۴)
    override fun tailscaleHostname(): String = ""

    override fun usePlatformBridge(): Boolean = false

    override fun usePlatformShell(): Boolean = false

    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    override fun clearDNSCache() {
    }
}
