#!/usr/bin/env python3
# patch_singbox_native.py
# اجرا در ریشه‌ی ریپو، بعد از prepare_android.py (داخل CI)
import os
import re
import shutil

APP = 'build_app'
KDIR = os.path.join(APP, 'android/app/src/main/kotlin/com/kingvpn/king_vpn')
MARK = '// SINGBOX-DUP: go.Seq shared by libbox and libv2ray'

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

# 3) Gradle: libbox.aar + رفع تکراری go.Seq
for name in ('build.gradle', 'build.gradle.kts'):
    gp = os.path.join(APP, 'android/app', name)
    if not os.path.exists(gp):
        continue
    is_kts = name.endswith('.kts')
    g = open(gp, encoding='utf-8').read()
    changed = False

    if 'libbox.aar' not in g:
        line = 'implementation(files("libs/libbox.aar"))' if is_kts else "implementation files('libs/libbox.aar')"
        g2, n = re.subn(r'dependencies\s*\{', 'dependencies {\n    ' + line, g, count=1)
        if n == 1:
            g = g2
        else:
            g = g.rstrip() + '\n\ndependencies {\n    ' + line + '\n}\n'
        changed = True
        print('OK: libbox dependency added to', name)

    if MARK not in g:
        if is_kts:
            block = (
                f'\n{MARK}\n'
                'android {\n'
                '    packaging {\n'
                '        jniLibs {\n'
                '            pickFirsts += setOf("**/libgojni.so")\n'
                '        }\n'
                '    }\n'
                '}\n'
                'tasks.matching { it.name == "checkReleaseDuplicateClasses" }.configureEach {\n'
                '    enabled = false\n'
                '}\n'
            )
        else:
            block = (
                f'\n{MARK}\n'
                'android {\n'
                '    packagingOptions {\n'
                "        pickFirst '**/libgojni.so'\n"
                '    }\n'
                '}\n'
                "tasks.matching { it.name == 'checkReleaseDuplicateClasses' }.configureEach {\n"
                '    enabled = false\n'
                '}\n'
            )
        g = g.rstrip() + '\n' + block
        changed = True
        print('OK: duplicate go.Seq handling added to', name)

    if changed:
        open(gp, 'w', encoding='utf-8').write(g)

# 4) MainActivity: ثبت کانال king/singbox
ma = os.path.join(KDIR, 'MainActivity.kt')
t = open(ma, encoding='utf-8').read()
if 'SingboxBridge.register' in t:
    print('OK: SingboxBridge already registered in MainActivity')
elif True:
    anchor = 'super.configureFlutterEngine(flutterEngine)'
    if t.count(anchor) < 1:
        raise SystemExit('MainActivity: configureFlutterEngine anchor not found')
    t = t.replace(
        anchor,
        anchor + '\n        SingboxBridge.register(this, flutterEngine.dartExecutor.binaryMessenger)',
        1,
    )
    open(ma, 'w', encoding='utf-8').write(t)
    print('OK: SingboxBridge registered in MainActivity')

# 5) R8 duplicate-class fix: libbox.aar and libv2ray.aar both ship go/*.class
#    (e.g. go/error.class). R8 treats this as fatal, so release minification is
#    disabled. Gradle merges this `android {}` block into the existing config.
for name in ('build.gradle', 'build.gradle.kts'):
    gp = os.path.join(APP, 'android/app', name)
    if not os.path.exists(gp):
        continue
    g = open(gp, encoding='utf-8').read()
    if 'R8-OFF' in g:
        print(f'OK: R8 already disabled in {name}')
        continue
    if name.endswith('.kts'):
        block = ('\n// R8-OFF: duplicate go/* classes in libbox + libv2ray\n'
                 'android {\n'
                 '    buildTypes {\n'
                 '        getByName("release") {\n'
                 '            isMinifyEnabled = false\n'
                 '            isShrinkResources = false\n'
                 '        }\n'
                 '    }\n'
                 '}\n')
    else:
        block = ('\n// R8-OFF: duplicate go/* classes in libbox + libv2ray\n'
                 'android {\n'
                 '    buildTypes {\n'
                 '        release {\n'
                 '            minifyEnabled false\n'
                 '            shrinkResources false\n'
                 '        }\n'
                 '    }\n'
                 '}\n')
    g = g.rstrip() + '\n' + block
    open(gp, 'w', encoding='utf-8').write(g)
    print(f'OK: R8 disabled for release in {name}')
