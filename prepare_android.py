import os
import re
import shutil

APP = 'build_app'
LIB = os.path.join(APP, 'lib')

# =====================================================================
# ---- 0) AGP 9.4.0 + Gradle 9.6.0 ----
# =====================================================================
print('[0] Upgrading AGP to 9.4.0 + Gradle 9.6.0')

sett = os.path.join(APP, 'android/settings.gradle.kts')
if not os.path.exists(sett):
    sett = os.path.join(APP, 'android/settings.gradle')
if os.path.exists(sett):
    with open(sett, encoding='utf-8') as f:
        s = f.read()
    s = re.sub(r'(id\("com\.android\.(?:application|library)"\)\s+version\s+")[^"]+(")',
               r'\g<1>9.4.0\g<2>', s)
    with open(sett, 'w', encoding='utf-8') as f:
        f.write(s)
    print('  OK: settings.gradle AGP -> 9.4.0')

gw = os.path.join(APP, 'android/gradle/wrapper/gradle-wrapper.properties')
if os.path.exists(gw):
    with open(gw, encoding='utf-8') as f:
        g = f.read()
    g = re.sub(r'gradle-[0-9.]+-(bin|all)\.zip', r'gradle-9.6.0-\1.zip', g)
    with open(gw, 'w', encoding='utf-8') as f:
        f.write(g)
    print('  OK: gradle-wrapper -> 9.6.0')

# =====================================================================
# Helpers
# =====================================================================
def patch_hard(file_key, old, new, label):
    text = files[file_key]
    if new in text:
        print('  SKIP (already applied): ' + label)
        return
    count = text.count(old)
    if count == 0:
        raise SystemExit('\n\nHARD FAIL: [%s]\nPattern NOT FOUND in %s.dart\nSearched for:\n---\n%s\n---\n' % (label, file_key, old[:300]))
    if count > 1:
        raise SystemExit('\n\nHARD FAIL: [%s]\nPattern matched %d times in %s.dart (must be 1)\n' % (label, count, file_key))
    files[file_key] = text.replace(old, new, 1)
    print('  OK: ' + label)


def patch_find(old, new, label):
    for fn, text in files.items():
        if new in text:
            print('  SKIP (already in %s): %s' % (fn, label))
            return
    matches = []
    for fn, text in files.items():
        c = text.count(old)
        if c > 0:
            matches.append((fn, c))
    if not matches:
        raise SystemExit('\n\nHARD FAIL: [%s]\nPattern NOT FOUND in any .dart file\nSearched for:\n---\n%s\n---\n' % (label, old[:300]))
    if len(matches) > 1:
        raise SystemExit('\n\nHARD FAIL: [%s]\nPattern found in multiple files: %s\n' % (label, matches))
    fn, c = matches[0]
    if c > 1:
        raise SystemExit('\n\nHARD FAIL: [%s]\nPattern matched %d times in %s.dart (must be 1)\n' % (label, c, fn))
    files[fn] = files[fn].replace(old, new, 1)
    print('  OK (%s): %s' % (fn, label))


def insert_before(file_key, anchor, content, label):
    text = files[file_key]
    if content.strip() in text:
        print('  SKIP (already inserted): ' + label)
        return
    if anchor not in text:
        raise SystemExit('\n\nHARD FAIL: [%s]\nAnchor NOT FOUND in %s.dart\n' % (label, file_key))
    files[file_key] = text.replace(anchor, content + anchor, 1)
    print('  OK: ' + label)


def replace_function_braces(file_key, sig_regex, new_func, label):
    text = files[file_key]
    m = re.search(sig_regex, text)
    if not m:
        raise SystemExit('\n\nHARD FAIL: [%s]\nSignature not found in %s.dart\nRegex: %s\n' % (label, file_key, sig_regex))
    start = m.start()
    pos = m.end()
    depth = 1
    n = len(text)
    in_string = None
    while pos < n:
        c = text[pos]
        if in_string:
            if c == '\\':
                pos += 2
                continue
            if c == in_string:
                in_string = None
            pos += 1
            continue
        if c == "'" or c == '"':
            in_string = c
            pos += 1
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                files[file_key] = text[:start] + new_func + text[pos + 1:]
                print('  OK: ' + label)
                return
        pos += 1
    raise SystemExit('\n\nHARD FAIL: [%s]\nClosing brace not found in %s.dart\n' % (label, file_key))


# ---- 1) AndroidManifest + native files ----
mp = os.path.join(APP, 'android/app/src/main/AndroidManifest.xml')
m = open(mp, encoding='utf-8').read()
perms = ('<uses-permission android:name="android.permission.INTERNET"/>\n'
         '    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/>\n'
         '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>\n'
         '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>\n'
         '    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>\n'
         '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
         '    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>\n    ')
if 'QUERY_ALL_PACKAGES' not in m:
    m = m.replace('<application', perms + '<application', 1)
SVC = ('<service android:name="dev.amirzr.flutter_v2ray_client.v2ray.services.V2rayProxyOnlyService"\n'
       '             android:foregroundServiceType="specialUse">\n'
       '            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"\n'
       '                      android:value="local proxy core for the user"/>\n'
       '        </service>\n    ')
if 'foregroundServiceType' not in m and '</application>' in m:
    m = m.replace('</application>', SVC + '</application>', 1)
KSVC = ('<service android:name="com.kingvpn.king_vpn.KingVpnService"\n'
        '            android:permission="android.permission.BIND_VPN_SERVICE"\n'
        '            android:exported="false"\n'
        '            android:foregroundServiceType="specialUse">\n'
        '            <intent-filter><action android:name="android.net.VpnService"/></intent-filter>\n'
        '            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"\n'
        '                      android:value="vpn"/>\n'
        '        </service>\n    ')
if 'com.kingvpn.king_vpn.KingVpnService' not in m and '</application>' in m:
    m = m.replace('</application>', KSVC + '</application>', 1)
open(mp, 'w', encoding='utf-8').write(m)
print('OK: AndroidManifest')

ja = os.path.join(APP, 'android/app/src/main/java/com/kingvpn/king_vpn')
os.makedirs(ja, exist_ok=True)
shutil.copy('android_src/KingVpnService.java', ja)
shutil.copy('android_src/KingDiag.java', ja)
old_java_main = os.path.join(ja, 'MainActivity.java')
if os.path.exists(old_java_main):
    os.remove(old_java_main)
ka = os.path.join(APP, 'android/app/src/main/kotlin/com/kingvpn/king_vpn')
os.makedirs(ka, exist_ok=True)
shutil.copy('android_src/MainActivity.kt', os.path.join(ka, 'MainActivity.kt'))
print('OK: Native files copied')

# ---- 2) Gradle ----
for name in ('build.gradle', 'build.gradle.kts'):
    gp = os.path.join(APP, 'android/app', name)
    if os.path.exists(gp):
        g = open(gp, encoding='utf-8').read()
        g = g.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
        g = g.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')
        g = g.replace('compileSdk = flutter.compileSdkVersion', 'compileSdk = 37')
        g = g.replace('compileSdkVersion flutter.compileSdkVersion', 'compileSdkVersion 37')
        g = re.sub(r'compileSdk\s*=\s*\d+', 'compileSdk = 37', g)
        open(gp, 'w', encoding='utf-8').write(g)

for name in ('build.gradle', 'build.gradle.kts'):
    gp = os.path.join(APP, 'android/app', name)
    if not os.path.exists(gp): continue
    g = open(gp, encoding='utf-8').read()
    if 'abiFilters' in g: continue
    is_kts = name.endswith('.kts')
    ndk_block = ('\n        ndk {\n            abiFilters += listOf("arm64-v8a", "armeabi-v7a")\n        }\n' if is_kts
                 else '\n        ndk {\n            abiFilters "arm64-v8a", "armeabi-v7a"\n        }\n')
    dc = re.search(r'defaultConfig\s*\{', g)
    if dc:
        g = g[:dc.end()] + ndk_block + g[dc.end():]
        open(gp, 'w', encoding='utf-8').write(g)
print('OK: Gradle')

# =====================================================================
# Dart source patches (V1..V19) have all been applied permanently to the
# files under lib/ (main.dart, iran_ai_extras.dart, npv_am_extras.dart,
# nat_ultra.dart, nip_scan.dart, auto_test.dart).
# This script now only fixes up the generated Android project
# (AGP/Gradle versions, AndroidManifest permissions/services, native
# source files, compileSdk) and no longer rewrites any .dart file.
# =====================================================================
print('\n' + '=' * 60)
print('=== Android project prepared (dart sources already final) ===')
