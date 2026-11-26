package com.kingvpn.king_vpn

import android.content.Intent
import android.net.VpnService
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File
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

    // FIX #63: true only while a Flutter engine is attached to this Activity.
    // Dart uses vpn/bg 'alive' to tell whether the app is still running; before this
    // it always answered true, even after the app was closed from recents.
    @Volatile private var engineAttached = false
    private var mySink: KingVpnService.StatusSink? = null
    private var pendingWireGuardConfig: String? = null
    private var pendingWireGuardResult: MethodChannel.Result? = null
    private val wireGuardPermissionRequest = 7912

    private fun finishWireGuardConnect(config: String, result: MethodChannel.Result) {
        Thread {
            try {
                val version = kingWireGuardCore().connect(config)
                runOnUiThread { result.success(mapOf("connected" to true, "version" to version, "core" to "wireguard")) }
            } catch (t: Throwable) {
                runOnUiThread { result.error("KING_WIREGUARD_ERROR", t.message ?: t.javaClass.simpleName, t.stackTraceToString()) }
            }
        }.start()
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != wireGuardPermissionRequest) return
        val config = pendingWireGuardConfig
        val result = pendingWireGuardResult
        pendingWireGuardConfig = null
        pendingWireGuardResult = null
        if (config == null || result == null) return
        if (resultCode == RESULT_OK) finishWireGuardConnect(config, result)
        else result.error("WIREGUARD_PERMISSION_DENIED", "اجازهٔ ایجاد VPN داده نشد", null)
    }

    private fun kingWireGuardCore(): KingWireGuardCore = KingWireGuardCore.shared(applicationContext)

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

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        engineAttached = false
        if (KingVpnService.statusSink === mySink) KingVpnService.statusSink = null // مشکل ۱۰
        mySink = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        engineAttached = true

        // ---- Independent core: WireGuard (libwg-go, not an Xray profile) ----
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "king/wireguard")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> {
                        val config = call.argument<String>("config") ?: ""
                        try {
                            val permissionIntent = VpnService.prepare(this)
                            if (permissionIntent != null) {
                                if (pendingWireGuardResult != null) {
                                    result.error("WIREGUARD_PERMISSION_PENDING", "درخواست مجوز قبلی هنوز باز است", null)
                                } else {
                                    pendingWireGuardConfig = config
                                    pendingWireGuardResult = result
                                    startActivityForResult(permissionIntent, wireGuardPermissionRequest)
                                }
                            } else {
                                finishWireGuardConnect(config, result)
                            }
                        } catch (t: Throwable) {
                            result.error("KING_WIREGUARD_PERMISSION_ERROR", t.message ?: t.javaClass.simpleName, t.stackTraceToString())
                        }
                    }
                    "disconnect", "status" -> Thread {
                        try {
                            if (call.method == "disconnect") {
                                kingWireGuardCore().disconnect()
                                runOnUiThread { result.success(true) }
                            } else {
                                val state = kingWireGuardCore().state()
                                runOnUiThread { result.success(mapOf("state" to state, "core" to "wireguard")) }
                            }
                        } catch (t: Throwable) {
                            runOnUiThread { result.error("KING_WIREGUARD_ERROR", t.message ?: t.javaClass.simpleName, t.stackTraceToString()) }
                        }
                    }.start()
                    else -> result.notImplemented()
                }
            }

        // ---- Shared full-device VPN/TUN owner coordinator ----
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "king/vpn_engine_owner")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        val engine = call.argument<String>("engine")?.trim().orEmpty()
                        val timeoutMs = call.argument<Number>("timeoutMs")?.toLong() ?: 30_000L
                        if (engine.isEmpty()) result.error("ENGINE_ID_REQUIRED", "Engine id must not be empty", null)
                        else Thread {
                            try {
                                val previous = KingVpnEngineCoordinator.currentOwner()
                                if (previous != null && previous != engine) {
                                    when (previous) {
                                        "xray" -> check(
                                            KingVpnService.instance?.stopForEngineHandoff(timeoutMs) == true
                                        ) { "Xray TUN handoff timed out before the native core was verified stopped" }
                                        "wireguard" -> kingWireGuardCore().disconnect()
                                        "libbox" -> check(KingVpnEngineCoordinator.stopLibboxAndRelease(this, timeoutMs)) {
                                                "libbox TUN handoff timed out"
                                            }
                                        "amneziawg" -> KingAmneziaWgCore.shared().disconnect()
                                    }
                                }
                                val acquired = KingVpnEngineCoordinator.acquire(engine, timeoutMs)
                                runOnUiThread { result.success(acquired) }
                            } catch (e: Throwable) {
                                runOnUiThread { result.error("ENGINE_HANDOFF_ERROR", e.message ?: e.javaClass.simpleName, e.stackTraceToString()) }
                            }
                        }.start()
                    }
                    "release" -> {
                        val engine = call.argument<String>("engine")?.trim().orEmpty()
                        if (engine.isEmpty()) result.error("ENGINE_ID_REQUIRED", "Engine id must not be empty", null)
                        else {
                            KingVpnEngineCoordinator.release(engine)
                            result.success(true)
                        }
                    }
                    "owner" -> result.success(KingVpnEngineCoordinator.currentOwner())
                    else -> result.notImplemented()
                }
            }

        // ---- Channel 1: king/vpn (start / stop the own VPN service) ----
        val kingVpnChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "king/vpn")
        // جدید: the native outcome of a start (CONNECTED / FAILED / STOPPED) goes to Dart as 'status'
        // FIX #83: every status carries the attempt id of the start it belongs to, so Dart
        // can drop late messages from an earlier attempt.
        val sink = KingVpnService.StatusSink { state, error, attempt ->
            runOnUiThread {
                try {
                    kingVpnChannel.invokeMethod(
                        "status",
                        mapOf("state" to state, "error" to error, "attempt" to attempt)
                    )
                } catch (_: Throwable) {
                    // Activity or engine already gone; nothing to report to
                }
            }
        }
        mySink = sink
        KingVpnService.statusSink = sink
        kingVpnChannel
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
                            i.putExtra(KingVpnService.EXTRA_NATIONAL,
                                call.argument<Boolean>("national") ?: false)
                            i.putExtra(KingVpnService.EXTRA_ATTEMPT,
                                call.argument<Int>("attempt") ?: 0)
                            ContextCompat.startForegroundService(this, i)
                            result.success(true)
                        }
                        "stop" -> {
                            // جدید: call the running service directly. startService from the
                            // background is refused on Android 12+; a direct call is not.
                            KingVpnService.instance?.stopFromApp()
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
                        "alive" -> result.success(
                            engineAttached && !isFinishing && !isDestroyed
                        )
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

        // ---- Channel 5: king/update (verified APK installer handoff) ----
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "king/update")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "installApk" -> {
                            val path = call.argument<String>("path")?.trim().orEmpty()
                            val apk = File(path).canonicalFile
                            val expectedUpdateDir = File(cacheDir, "king_updates").canonicalFile
                            val apkSize = apk.length()
                            // The method channel is an internal trust boundary: only accept the
                            // exact app-private cache asset that Dart just SHA-256 verified.
                            // Never let an arbitrary local path be handed to Android's installer.
                            if (!apk.isFile ||
                                apk.parentFile != expectedUpdateDir ||
                                apk.name != "king-vpn-update.apk" ||
                                apkSize !in 1L..(300L * 1024L * 1024L)) {
                                result.error("UPDATE_APK_INVALID", "Verified APK file is missing or invalid", null)
                                return@setMethodCallHandler
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                !packageManager.canRequestPackageInstalls()) {
                                val settingsIntent = Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                )
                                startActivity(settingsIntent)
                                result.success("permission_required")
                                return@setMethodCallHandler
                            }
                            val contentUri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                apk
                            )
                            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(contentUri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(installIntent)
                            result.success("installer_opened")
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("UPDATE_INSTALL_FAILED", t.message, t.stackTraceToString())
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
