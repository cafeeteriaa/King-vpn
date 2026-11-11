package com.kingvpn.king_vpn

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// KINGVPN: کانال ارتباطی Flutter با سرویس VPN خودمان (کانال: king/vpn)
//
// IMPROVEMENTS over previous version:
//   • Every channel handler wrapped in try/catch: no handler can crash the app.
//     Previously a single exception inside any handler (e.g. startForegroundService
//     on Android 12+ when the app was backgrounded) would surface as a
//     MissingPluginException in Dart with no root cause.
//   • Errors are returned via result.error() with the actual message and stack
//     trace, so the Dart side logs the real cause instead of a generic failure.
//   • KingDiag.install() is now inside a try/catch: if the crash recorder fails
//     to install (e.g. on some Samsung One UI builds), the app still opens.
//   • vpnSettings now returns a descriptive error message instead of null when
//     both VPN and wireless settings intents fail.
//   • Added a defensive guard around runOnUiThread so a late result after
//     activity destruction cannot crash the process.
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // KINGDIAG: install the crash recorder before super.onCreate so crashes
        // during startup are also captured. If it fails, the app must still open.
        try {
            KingDiag.install(applicationContext)
        } catch (_: Throwable) {
            // Never let diagnostics take down the app
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // SINGBOX: ثبت کانال king/singbox (پل هسته sing-box)
        SingboxBridge.register(this, flutterEngine.dartExecutor.binaryMessenger)

        // ---- Channel 1: king/vpn (start / stop the own VPN service) ----
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "king/vpn")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            val i = Intent(this, KingVpnService::class.java)
                            i.action = KingVpnService.ACTION_START
                            i.putExtra(KingVpnService.EXTRA_CONFIG,
                                call.argument<String>("config") ?: "")
                            i.putExtra(KingVpnService.EXTRA_REMARK,
                                call.argument<String>("remark") ?: "")
                            i.putExtra(KingVpnService.EXTRA_ADDR,
                                call.argument<String>("addr") ?: "")
                            i.putExtra(KingVpnService.EXTRA_PORT,
                                call.argument<String>("port") ?: "")
                            // BACKUPFIX: forward the failover list from Dart
                            // to the native service (was silently dropped)
                            i.putExtra(KingVpnService.EXTRA_BACKUPS,
                                call.argument<String>("backups") ?: "")
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
                } catch (t: Throwable) {
                    // Surfaced to Dart as a real exception, not a silent drop
                    result.error("KING_VPN_ERROR", t.message, t.stackTraceToString())
                }
            }

        // ---- Channel 2: vpn/bg (alive / back / vpnSettings) ----
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vpn/bg")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "alive" -> result.success(true)
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
                                        "Android VPN settings could not be opened " +
                                            "(vpn: ${e.message}, wireless: ${fallback.message})",
                                        null
                                    )
                                }
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("BG_CHANNEL_ERROR", t.message, t.stackTraceToString())
                }
            }

        // ---- Channel 3: king/share (Android share sheet for offline sharing) ----
        // KINGSHARE: uses Android's own share sheet (Bluetooth, SMS, Nearby Share,
        // Telegram, email, etc.) instead of hand-rolled Bluetooth/Wi-Fi Direct.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "king/share")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "shareText" -> {
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
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("SHARE_FAILED", t.message, t.stackTraceToString())
                }
            }

        // ---- Channel 4: king/diag (crash + process-exit forensics) ----
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "king/diag")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "lastCrash", "lastExit" -> {
                            val wantCrash = call.method == "lastCrash"
                            Thread {
                                val text = try {
                                    if (wantCrash) {
                                        KingDiag.takeLastCrash(applicationContext)
                                    } else {
                                        KingDiag.lastExits(applicationContext)
                                    }
                                } catch (_: Throwable) {
                                    ""
                                }
                                try {
                                    runOnUiThread { result.success(text) }
                                } catch (_: Throwable) {
                                    // Activity gone before we could reply — ignore
                                }
                            }.start()
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("DIAG_ERROR", t.message, t.stackTraceToString())
                }
            }
    }
}
