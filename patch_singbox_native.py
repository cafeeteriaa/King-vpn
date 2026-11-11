#!/usr/bin/env python3
# patch_singbox_native.py
# اجرا در ریشه‌ی ریپو، بعد از prepare_android.py (داخل CI)
# کار: کپی SingboxBridge.kt، ثبت سرویس در Manifest، افزودن libbox.aar به Gradle،
#      و ثبت کانال king/singbox در MainActivity.
import os
import re
import shutil

APP = 'build_app'
KDIR = os.path.join(APP, 'android/app/src/main/kotlin/com/kingvpn/king_vpn')

# 1) کپی فایل Kotlin
os.makedirs(KDIR, exist_ok=True)
shutil.copy('android_src/SingboxBridge.kt', KDIR)
print('OK: SingboxBridge.kt copied')

# 2) Manifest: سرویس VPN مخصوص sing-box
mp = os.path.join(APP, 'android/app/src/main/AndroidManifest.xml')
m = open(mp, encoding='utf-8').read()
if 'SingboxVpnService' not in m:
    svc = (
        '<service android:name="com.kingvpn.king_vpn.SingboxVpnService"\n'
        '            android:permission="android.permission.BIND_VPN_SERVICE"\n'
        '            android:exported="false"\n'
        '            android:foregroundServiceType="specialUse">\n'
        '            <intent-filter><action android:name="android.net.VpnService"/></intent-filter>\n'
        '            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"\n'
        '                      android:value="vpn"/>\n'
        '        </service>\n    '
    )
    assert m.count('</application>') == 1, 'AndroidManifest: </application> not unique'
    m = m.replace('</application>', svc + '</application>', 1)
    open(mp, 'w', encoding='utf-8').write(m)
    print('OK: manifest service added')

# 3) Gradle: افزودن libbox.aar
for name in ('build.gradle', 'build.gradle.kts'):
    gp = os.path.join(APP, 'android/app', name)
    if not os.path.exists(gp):
        continue
    g = open(gp, encoding='utf-8').read()
    if 'libbox.aar' in g:
        print('OK: libbox already in', name)
        continue
    if name.endswith('.kts'):
        line = 'implementation(files("libs/libbox.aar"))'
    else:
        line = "implementation files('libs/libbox.aar')"
    g, n = re.subn(r'dependencies\s*\{', 'dependencies {\n    ' + line, g, count=1)
    assert n == 1, name + ': dependencies block not found'
    open(gp, 'w', encoding='utf-8').write(g)
    print('OK: libbox dependency added to', name)

# 4) MainActivity: ثبت کانال king/singbox
ma = os.path.join(KDIR, 'MainActivity.kt')
t = open(ma, encoding='utf-8').read()
if 'SingboxBridge.register' not in t:
    anchor = 'super.configureFlutterEngine(flutterEngine)'
    assert t.count(anchor) == 1, 'MainActivity: anchor not unique'
    t = t.replace(
        anchor,
        anchor + '\n        SingboxBridge.register(this, flutterEngine.dartExecutor.binaryMessenger)',
        1,
    )
    open(ma, 'w', encoding='utf-8').write(t)
    print('OK: SingboxBridge registered in MainActivity')
