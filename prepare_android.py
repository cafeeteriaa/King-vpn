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
meta = ('<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" '
        'android:value="ca-app-pub-3940256099942544~3347511713"/>\n    ')
if 'ads.APPLICATION_ID' not in m:
    m = m.replace('</application>', meta + '</application>', 1)
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

kd = os.path.join(APP, 'android/app/src/main/kotlin/com/vpn/vpn_app')
os.makedirs(kd, exist_ok=True)
open(os.path.join(kd, 'MainActivity.kt'), 'w', encoding='utf-8').write("""package com.vpn.vpn_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var ch: MethodChannel? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vpn/bg")
        ch!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "back" -> { moveTaskToBack(true); result.success(true) }
                "alive" -> result.success(!isFinishing && !isDestroyed)
                else -> result.notImplemented()
            }
        }
    }
    override fun onDestroy() {
        if (isFinishing) {
            try { ch?.invokeMethod("gone", null) } catch (e: Exception) {}
        }
        super.onDestroy()
    }
}
""")
print('prepare_android OK')
