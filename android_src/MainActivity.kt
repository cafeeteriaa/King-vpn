package com.kingvpn.king_vpn

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// KINGVPN: کانال ارتباطی Flutter با سرویس VPN خودمان (کانال: king/vpn)
class MainActivity : FlutterActivity() {
    // KINGDIAG: ثبت‌کننده‌ی کرش Java؛ قبل از super.onCreate نصب می‌شود تا کرش‌های شروع هم ثبت شوند
    override fun onCreate(savedInstanceState: Bundle?) {
        KingDiag.install(applicationContext)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "king/vpn")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val i = Intent(this, KingVpnService::class.java)
                        i.action = KingVpnService.ACTION_START
                        i.putExtra(KingVpnService.EXTRA_CONFIG, call.argument<String>("config") ?: "")
                        i.putExtra(KingVpnService.EXTRA_REMARK, call.argument<String>("remark") ?: "")
                        i.putExtra(KingVpnService.EXTRA_ADDR, call.argument<String>("addr") ?: "")
                        i.putExtra(KingVpnService.EXTRA_PORT, call.argument<String>("port") ?: "")
                        // BACKUPFIX: lib/own_vpn.dart's ownVpnStart() already sends "backups"
                        // (KINGFAILOVER) and KingVpnService already reads EXTRA_BACKUPS, but
                        // this bridge never forwarded it — so the whole backup/failover list,
                        // this file's own A4 success-weighted ordering included, was silently
                        // empty no matter what Dart sent. One line was missing.
                        i.putExtra(KingVpnService.EXTRA_BACKUPS, call.argument<String>("backups") ?: "")
                        startForegroundService(i)
                        result.success(true)
                    }
                    "stop" -> {
                        val i = Intent(this, KingVpnService::class.java)
                        i.action = KingVpnService.ACTION_STOP
                        startService(i)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        // ALIVE-NATIVE: Dart asks 'alive' on channel vpn/bg every minute; answer it here
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vpn/bg")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "alive" -> result.success(true)
                    // BACK-NATIVE: Dart برای دکمه‌ی برگشت این متد را صدا می‌زند؛ فقط به پس‌زمینه می‌رویم
                    "back" -> {
                        moveTaskToBack(true)
                        result.success(true)
                    }
                    "vpnSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_VPN_SETTINGS))
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
                                result.success(true)
                            } catch (fallback: Exception) {
                                result.error(
                                    "VPN_SETTINGS_UNAVAILABLE",
                                    "Android VPN settings could not be opened",
                                    null
                                )
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // KINGSHARE (Group D — آفلاین/نزدیک): به‌جای پیاده‌سازی دستی بلوتوث/Wi-Fi
        // Direct/SMS که بدون دستگاه واقعی قابل تست نیست، از شیت اشتراک‌گذاری خود
        // اندروید استفاده می‌کند؛ کاربر در همان شیت بین بلوتوث، پیامک، Nearby Share،
        // تلگرام، ایمیل و هر اپ دیگری که متن می‌پذیرد انتخاب می‌کند. پایدارترین راه
        // برای «نزدیک یا بی‌اینترنت» چون از قابلیت‌های خود سیستم‌عامل استفاده می‌کند.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "king/share")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareText" -> {
                        try {
                            val text = call.argument<String>("text") ?: ""
                            val subject = call.argument<String>("subject") ?: ""
                            if (text.isEmpty()) {
                                result.error("SHARE_EMPTY", "nothing to share", null)
                                return@setMethodCallHandler
                            }
                            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, text)
                                if (subject.isNotEmpty()) {
                                    putExtra(Intent.EXTRA_SUBJECT, subject)
                                }
                            }
                            val chooserTitle = subject.ifEmpty { "اشتراک‌گذاری" }
                            startActivity(Intent.createChooser(sendIntent, chooserTitle))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // KINGDIAG: Dart می‌پرسد پردازه‌ی قبلی چرا مرد؛ جواب از KingDiag.java می‌آید.
        // خواندن گزارش سیستم در یک ترد جدا انجام می‌شود تا ترد اصلی گیر نکند.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "king/diag")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "lastCrash", "lastExit" -> {
                        val wantCrash = call.method == "lastCrash"
                        Thread {
                            val text = try {
                                if (wantCrash) KingDiag.takeLastCrash(applicationContext)
                                else KingDiag.lastExits(applicationContext)
                            } catch (t: Throwable) {
                                ""
                            }
                            runOnUiThread { result.success(text) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
