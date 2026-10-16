import os
import re

# Android-only setup (manifest, gradle, MainActivity). The Dart code in lib/
# is already final, so nothing here touches main.dart.
APP = 'build_app'

mp = os.path.join(APP, 'android/app/src/main/AndroidManifest.xml')
m = open(mp, encoding='utf-8').read()
perms = ('<uses-permission android:name="android.permission.INTERNET"/>\n'
         '    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/>\n'
         '    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>\n'
         '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    ')
if 'QUERY_ALL_PACKAGES' not in m:
    m = m.replace('<application', perms + '<application', 1)
open(mp, 'w', encoding='utf-8').write(m)

# Gradle: minSdk 24 and compileSdk 37 (permission_handler_android needs 37)
for name in ('build.gradle', 'build.gradle.kts'):
    gp = os.path.join(APP, 'android/app', name)
    if os.path.exists(gp):
        g = open(gp, encoding='utf-8').read()
        g = g.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
        g = g.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')
        g = g.replace('compileSdk = flutter.compileSdkVersion', 'compileSdk = 37')
        g = g.replace('compileSdkVersion flutter.compileSdkVersion',
                      'compileSdkVersion 37')
        g = re.sub(r'compileSdk\s*=\s*\d+', 'compileSdk = 37', g)
        open(gp, 'w', encoding='utf-8').write(g)

# silence the "max recommended SDK" warning of the Android Gradle plugin
gpp = os.path.join(APP, 'android', 'gradle.properties')
if os.path.exists(gpp):
    t = open(gpp, encoding='utf-8').read()
    if 'suppressUnsupportedCompileSdk' not in t:
        t += '\nandroid.suppressUnsupportedCompileSdk=37\n'
        open(gpp, 'w', encoding='utf-8').write(t)


# app name shown to the user
m = open(mp, encoding='utf-8').read()
m = re.sub(r'android:label="[^"]*"', 'android:label="King VPN"', m, count=1)
open(mp, 'w', encoding='utf-8').write(m)

# Release signing (keystore comes from env vars set by the workflow)
SIGN_KTS = """signingConfigs {
        create("release") {
            val ksFile = System.getenv("KS_FILE")
            if (ksFile != null) {
                storeFile = file(ksFile)
                storePassword = System.getenv("KS_PASS")
                keyAlias = System.getenv("KS_ALIAS")
                keyPassword = System.getenv("KS_PASS")
            }
        }
    }
"""
SIGN_GROOVY = """signingConfigs {
        release {
            def ksFile = System.getenv("KS_FILE")
            if (ksFile != null) {
                storeFile file(ksFile)
                storePassword System.getenv("KS_PASS")
                keyAlias System.getenv("KS_ALIAS")
                keyPassword System.getenv("KS_PASS")
            }
        }
    }
"""
for name, block in (('build.gradle.kts', SIGN_KTS), ('build.gradle', SIGN_GROOVY)):
    gp = os.path.join(APP, 'android/app', name)
    if os.path.exists(gp):
        g = open(gp, encoding='utf-8').read()
        if 'KS_FILE' not in g:
            g = g.replace('android {', 'android {\n    ' + block, 1)
            g = g.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("release")')
            g = g.replace('signingConfig signingConfigs.debug', 'signingConfig signingConfigs.release')
            g = g.replace('signingConfig = signingConfigs.debug', 'signingConfig = signingConfigs.release')
        open(gp, 'w', encoding='utf-8').write(g)

kd = os.path.join(APP, 'android/app/src/main/kotlin/com/kingvpn/king_vpn')
os.makedirs(kd, exist_ok=True)
open(os.path.join(kd, 'MainActivity.kt'), 'w', encoding='utf-8').write("""package com.kingvpn.king_vpn

import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

// BGKEEP: the Flutter engine (and so the Dart server search) lives in a cache
// and is NOT destroyed when the screen is swiped away from the recent apps.
// The VPN service keeps the process alive, so the search keeps running.
// When the screen closes, Dart is asked ("gone"): with no VPN wanted/up it
// answers false and the engine is destroyed, otherwise it is kept.
class MainActivity : FlutterActivity() {
    companion object {
        private const val ENGINE_ID = "vpn_main_engine"
        private var ch: MethodChannel? = null
        private var liveActivity: MainActivity? = null

        private fun killEngine() {
            try {
                val e = FlutterEngineCache.getInstance().get(ENGINE_ID)
                FlutterEngineCache.getInstance().remove(ENGINE_ID)
                e?.destroy()
            } catch (x: Exception) {}
            ch = null
        }
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        val cache = FlutterEngineCache.getInstance()
        var e = cache.get(ENGINE_ID)
        if (e == null) {
            e = FlutterEngine(context.applicationContext)
            GeneratedPluginRegistrant.registerWith(e)
            val c = MethodChannel(e.dartExecutor.binaryMessenger, "vpn/bg")
            c.setMethodCallHandler { call, result ->
                when (call.method) {
                    "back" -> { liveActivity?.moveTaskToBack(true); result.success(true) }
                    "alive" -> result.success(true)
                    "vpnSettings" -> {
                        try {
                            val i = Intent(Settings.ACTION_VPN_SETTINGS)
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(i)
                            result.success(true)
                        } catch (x: Exception) { result.success(false) }
                    }
                    else -> result.notImplemented()
                }
            }
            ch = c
            e.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            cache.put(ENGINE_ID, e)
        }
        return e
    }

    // plugins are already registered in provideFlutterEngine
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {}

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        liveActivity = this
        super.onCreate(savedInstanceState)
    }

    // required by openvpn_flutter so the VPN permission result starts the tunnel
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        try {
            id.laskarmedia.openvpn_flutter.OpenVPNFlutterPlugin.connectWhileGranted(
                requestCode == 24 && resultCode == RESULT_OK
            )
        } catch (e: Exception) {}
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        val finishing = isFinishing
        if (liveActivity === this) liveActivity = null
        super.onDestroy()
        if (finishing) {
            try {
                ch?.invokeMethod("gone", null, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (result == false) killEngine()
                    }
                    override fun error(code: String, msg: String?, details: Any?) {}
                    override fun notImplemented() {}
                })
            } catch (e: Exception) {}
        }
    }
}
""")
print('prepare_android OK')
