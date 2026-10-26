package com.kingvpn.king_vpn

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// KINGVPN: کانال ارتباطی Flutter با سرویس VPN خودمان (کانال: king/vpn)
class MainActivity : FlutterActivity() {
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
                    else -> result.notImplemented()
                }
            }
    }
}
