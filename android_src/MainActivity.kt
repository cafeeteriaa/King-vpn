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
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions

// SINGBOX: پل Flutter ↔ هسته sing-box (libbox 1.14). کانال: king/singbox
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
        @Volatile private var server: CommandServer? = null
        @Volatile private var state = STATE_IDLE
        @Volatile private var libboxReady = false
        @Volatile var lastError = ""

        fun isAlive(): Boolean = state == STATE_RUNNING && server != null

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
            val s = server
            server = null
            try {
                s?.closeService()
            } catch (t: Throwable) {
                Log.w(TAG, "closeService", t)
            }
            try {
                s?.close()
            } catch (t: Throwable) {
                Log.w(TAG, "close", t)
            }
            state = STATE_IDLE
            service?.stopSelf()
        }

        // Libbox.setup فقط یک بار لازم است و مسیرهای داده‌ی برنامه را تنظیم می‌کند
        @Synchronized
        fun ensureLibboxSetup(ctx: Context) {
            if (libboxReady) return
            val o = SetupOptions()
            o.basePath = ctx.filesDir.absolutePath
            o.workingPath = ctx.filesDir.absolutePath
            o.tempPath = ctx.cacheDir.absolutePath
            o.debug = false
            Libbox.setup(o)
            libboxReady = true
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
                ensureLibboxSetup(this)
                val srv = Libbox.newCommandServer(makeCommandHandler(), makeSingboxPlatform(this))
                srv.start()
                srv.startOrReloadService(cfg, OverrideOptions())
                server = srv
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
            server?.closeService()
        } catch (_: Throwable) {
        }
        try {
            server?.close()
        } catch (_: Throwable) {
        }
        server = null
        super.onDestroy()
    }

    fun buildTun(options: TunOptions): Int {
        if (VpnService.prepare(this) != null) throw IllegalStateException("VPN permission missing")
        val b = Builder()
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

// پیاده‌سازی CommandServerHandler (۷ متد الزامی libbox 1.14)
private fun makeCommandHandler(): CommandServerHandler = object : CommandServerHandler {
    override fun serviceStop() {
        SingboxVpnService.stop()
    }

    override fun serviceReload() {
    }

    override fun getSystemProxyStatus(): SystemProxyStatus? = null

    override fun setSystemProxyEnabled(enabled: Boolean) {
    }

    override fun triggerNativeCrash() {
    }

    override fun writeDebugMessage(message: String) {
        Log.d("SingboxCore", message)
    }

    override fun connectSSHAgent(): Int = -1
}

// پیاده‌سازی PlatformInterface برای libbox.
// با Proxy ساخته می‌شود تا کامپایل به لیست کامل متدهای رابط وابسته نباشد:
// متدهای شناخته‌شده رفتار واقعی دارند و بقیه مقدار پیش‌فرض امن برمی‌گردانند.
private fun makeSingboxPlatform(svc: SingboxVpnService): PlatformInterface {
    val handler = java.lang.reflect.InvocationHandler { _, method, args ->
        when (method.name) {
            "usePlatformAutoDetectInterfaceControl" -> true
            "autoDetectInterfaceControl" -> {
                val fd = args!![0] as Int
                if (!svc.protect(fd)) throw IllegalStateException("protect($fd) failed")
                null
            }
            "openTun" -> svc.buildTun(args!![0] as TunOptions)
            "tailscaleHostname" -> ""
            "usePlatformBridge", "usePlatformShell",
            "underNetworkExtension", "includeAllNetworks" -> false
            "clearDNSCache" -> null
            else -> defaultReturnFor(method.returnType)
        }
    }
    return java.lang.reflect.Proxy.newProxyInstance(
        PlatformInterface::class.java.classLoader,
        arrayOf(PlatformInterface::class.java),
        handler
    ) as PlatformInterface
}

private fun defaultReturnFor(t: Class<*>): Any? = when (t) {
    java.lang.Boolean.TYPE -> false
    java.lang.Integer.TYPE -> 0
    java.lang.Long.TYPE -> 0L
    java.lang.Short.TYPE -> 0.toShort()
    java.lang.Byte.TYPE -> 0.toByte()
    java.lang.Float.TYPE -> 0f
    java.lang.Double.TYPE -> 0.0
    java.lang.Character.TYPE -> 0.toChar()
    java.lang.String::class.java -> ""
    else -> null
}
