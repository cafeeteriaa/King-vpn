import os
import re
import shutil

APP = 'build_app'
LIB = os.path.join(APP, 'lib')
# Flutter 3.50 + Kotlin 2.4.20 supported Android toolchain.
AGP_VERSION = '9.3.1'
GRADLE_VERSION = '9.5.0'
MAVEN_CENTRAL_MIRROR = 'https://maven-central.storage-download.googleapis.com/maven2/'
ALIYUN_CENTRAL_MIRROR = 'https://maven.aliyun.com/repository/central/'
ALIYUN_GRADLE_PLUGIN_MIRROR = 'https://maven.aliyun.com/repository/gradle-plugin/'

def add_maven_mirror_to_scope(text, scope_name, mirror_line):
    """Insert the Maven Central mirror into a named Gradle repositories block."""
    scope = re.search(rf'{re.escape(scope_name)}\s*\{{', text)
    if not scope:
        return text
    scope_open = scope.end() - 1

    def matching_brace(source, open_pos):
        depth = 0
        for pos in range(open_pos, len(source)):
            if source[pos] == '{':
                depth += 1
            elif source[pos] == '}':
                depth -= 1
                if depth == 0:
                    return pos
        return -1

    scope_close = matching_brace(text, scope_open)
    if scope_close < 0:
        raise SystemExit('HARD FAIL: malformed ' + scope_name + ' block')
    block = text[scope_open + 1:scope_close]
    repo_match = re.search(r'repositories\s*\{', block)
    if not repo_match:
        raise SystemExit('HARD FAIL: ' + scope_name + ' has no repositories block')
    repo_open = scope_open + 1 + repo_match.end() - 1
    repo_close = matching_brace(text, repo_open)
    if repo_close < 0 or repo_close > scope_close:
        raise SystemExit('HARD FAIL: malformed ' + scope_name + ' repositories block')
    repo_body = text[repo_open:repo_close]
    if MAVEN_CENTRAL_MIRROR not in repo_body:
        text = text[:repo_open + 1] + '\n' + mirror_line.rstrip('\n') + text[repo_open + 1:]
        print('  OK: Added Maven Central mirror to ' + scope_name)
    else:
        print('  OK: ' + scope_name + ' already has Maven Central mirror')
    return text


# =====================================================================
# ---- 0) Flutter 3.50 / Kotlin 2.4.20 compatible toolchain ----
# =====================================================================
print(f'[0] Pinning AGP {AGP_VERSION} + Gradle {GRADLE_VERSION}')

sett = os.path.join(APP, 'android/settings.gradle.kts')
if not os.path.exists(sett):
    sett = os.path.join(APP, 'android/settings.gradle')
if os.path.exists(sett):
    with open(sett, encoding='utf-8') as f:
        s = f.read()
    # Resolve Kotlin/Android plugin transitives from Google's and Maven Central's
    # repositories as well as the Gradle Plugin Portal. Recent Flutter templates
    # can otherwise leave Kotlin stdlib/plugin artifacts searched only at portal.
    pm = re.search(r'pluginManagement\s*\{', s)
    if pm:
        block_end = s.find('}', pm.end())
        block = s[pm.end():block_end if block_end >= 0 else len(s)]
        repo_match = re.search(r'repositories\s*\{', block)
        if repo_match:
            insert_at = pm.end() + repo_match.end()
            repo_block = block[repo_match.end():]
            additions = ''
            mirror_entry = (
                f'maven {{ url = uri("{MAVEN_CENTRAL_MIRROR}") }}'
                if sett.endswith('.kts') else
                f'maven {{ url "{MAVEN_CENTRAL_MIRROR}" }}'
            )
            # Keep the Google-hosted Central mirror first, then use Aliyun
            # as a fallback for Kotlin DSL plugin markers and transitives.
            aliyun_central_entry = (
                f'maven {{ url = uri("{ALIYUN_CENTRAL_MIRROR}") }}'
                if sett.endswith('.kts') else
                f'maven {{ url "{ALIYUN_CENTRAL_MIRROR}" }}'
            )
            aliyun_plugin_entry = (
                f'maven {{ url = uri("{ALIYUN_GRADLE_PLUGIN_MIRROR}") }}'
                if sett.endswith('.kts') else
                f'maven {{ url "{ALIYUN_GRADLE_PLUGIN_MIRROR}" }}'
            )
            if MAVEN_CENTRAL_MIRROR not in repo_block:
                additions += '\n        ' + mirror_entry
            if ALIYUN_CENTRAL_MIRROR not in repo_block:
                additions += '\n        ' + aliyun_central_entry
            if ALIYUN_GRADLE_PLUGIN_MIRROR not in repo_block:
                additions += '\n        ' + aliyun_plugin_entry
            if 'google()' not in repo_block:
                additions += '\n        google()'
            if 'mavenCentral()' not in repo_block:
                additions += '\n        mavenCentral()'
            if additions:
                s = s[:insert_at] + additions + s[insert_at:]
        else:
            mirror_entry = (
                f'maven {{ url = uri("{MAVEN_CENTRAL_MIRROR}") }}'
                if sett.endswith('.kts') else
                f'maven {{ url "{MAVEN_CENTRAL_MIRROR}" }}'
            )
            s = s[:pm.end()] + '\n    repositories { ' + mirror_entry + '; google(); mavenCentral(); gradlePluginPortal() }' + s[pm.end():]
    root_mirror_entry = (
        f'        maven {{ url = uri("{MAVEN_CENTRAL_MIRROR}") }}'
        if sett.endswith('.kts') else
        f'        maven {{ url "{MAVEN_CENTRAL_MIRROR}" }}'
    )
    s = add_maven_mirror_to_scope(s, 'dependencyResolutionManagement', root_mirror_entry)
    s = re.sub(r'(id\("com\.android\.(?:application|library)"\)\s+version\s+")[^"]+(")',
               lambda m: f'{m.group(1)}{AGP_VERSION}{m.group(2)}', s)
    with open(sett, 'w', encoding='utf-8') as f:
        f.write(s)
    print(f'  OK: settings.gradle plugin repositories + AGP -> {AGP_VERSION}')

gw = os.path.join(APP, 'android/gradle/wrapper/gradle-wrapper.properties')
if os.path.exists(gw):
    with open(gw, encoding='utf-8') as f:
        g = f.read()
    g = re.sub(r'gradle-[0-9.]+-(bin|all)\.zip', lambda m: f'gradle-{GRADLE_VERSION}-{m.group(1)}.zip', g)
    with open(gw, 'w', encoding='utf-8') as f:
        f.write(g)
    print(f'  OK: gradle-wrapper -> {GRADLE_VERSION}')

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
required_permissions = (
    'android.permission.INTERNET',
    'android.permission.RECORD_AUDIO',
    'android.permission.QUERY_ALL_PACKAGES',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_SPECIAL_USE',
    'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.REQUEST_INSTALL_PACKAGES',
)
if '<application' not in m:
    raise SystemExit('HARD FAIL: AndroidManifest.xml has no application element')
# Add each permission independently. A partially pre-populated manifest must
# not suppress unrelated permissions just because QUERY_ALL_PACKAGES exists.
for permission in required_permissions:
    if f'android:name="{permission}"' not in m:
        declaration = f'    <uses-permission android:name="{permission}"/>\n    '
        m = m.replace('<application', declaration + '<application', 1)
# speech_to_text uses Android's system recognizer. Keep recognition on-device
# in Dart and declare package visibility for Android 11+ even when Flutter's
# generated manifest already contains an unrelated <queries> block.
if 'android.speech.RecognitionService' not in m:
    speech_intent = ('\n        <intent>\n'
                     '            <action android:name="android.speech.RecognitionService"/>\n'
                     '        </intent>\n    ')
    if '<queries>' in m:
        m = m.replace('<queries>', '<queries>' + speech_intent, 1)
    else:
        speech_queries = ('<queries>' + speech_intent + '</queries>\n    ')
        m = m.replace('<application', speech_queries + '<application', 1)
SVC = ('<service android:name="dev.amirzr.flutter_v2ray_client.v2ray.services.V2rayProxyOnlyService"\n'
       '             android:foregroundServiceType="specialUse">\n'
       '            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"\n'
       '                      android:value="local proxy core for the user"/>\n'
       '        </service>\n    ')
proxy_service_name = 'dev.amirzr.flutter_v2ray_client.v2ray.services.V2rayProxyOnlyService'
if proxy_service_name not in m and '</application>' in m:
    m = m.replace('</application>', SVC + '</application>', 1)
elif proxy_service_name in m:
    # Scope the foreground-service check to this service. Another service's
    # foregroundServiceType must not suppress the VPN plugin declaration.
    service_match = re.search(
        r"<service\b(?=[^>]*android:name=['\"]" + re.escape(proxy_service_name) +
        r"['\"])[^>]*>",
        m,
        flags=re.DOTALL,
    )
    if service_match and 'android:foregroundServiceType=' not in service_match.group(0):
        tag = service_match.group(0)
        updated_tag = tag[:-1] + ' android:foregroundServiceType="specialUse">'
        m = m[:service_match.start()] + updated_tag + m[service_match.end():]
    if proxy_service_name in m and 'PROPERTY_SPECIAL_USE_FGS_SUBTYPE' not in m:
        closing = re.search(r'</service>', m[service_match.end():] if service_match else m)
        if closing and service_match:
            insert_at = service_match.end() + closing.start()
            m = m[:insert_at] + (
                '\n            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"'
                '\n                      android:value="local proxy core for the user"/>'
            ) + m[insert_at:]
# VpnService must be exported for Android system binding. The signature-level
# BIND_VPN_SERVICE permission prevents ordinary apps from binding this service.
KSVC = ('<service android:name="com.kingvpn.king_vpn.KingVpnService"\n'
        '            android:permission="android.permission.BIND_VPN_SERVICE"\n'
        '            android:exported="true"\n'
        '            android:foregroundServiceType="specialUse">\n'
        '            <intent-filter><action android:name="android.net.VpnService"/></intent-filter>\n'
        '            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"\n'
        '                      android:value="vpn"/>\n'
        '        </service>\n    ')
if 'com.kingvpn.king_vpn.KingVpnService' not in m and '</application>' in m:
    m = m.replace('</application>', KSVC + '</application>', 1)
# FileProvider exposes only the app-cache subfolder used for SHA-256 verified
# APK updates. Never use file:// URIs for Android package installation.
UPDATE_PROVIDER = ('<provider android:name="androidx.core.content.FileProvider"\n'
                   '            android:authorities="${applicationId}.fileprovider"\n'
                   '            android:exported="false"\n'
                   '            android:grantUriPermissions="true">\n'
                   '            <meta-data android:name="android.support.FILE_PROVIDER_PATHS"\n'
                   '                       android:resource="@xml/king_file_paths"/>\n'
                   '        </provider>\n    ')
if 'androidx.core.content.FileProvider' not in m and '</application>' in m:
    m = m.replace('</application>', UPDATE_PROVIDER + '</application>', 1)

# VPN server configs and local AI credentials are stored in app-private files
# and SharedPreferences. Never include them in cloud backup or device transfer.
app_start = m.find('<application')
app_end = m.find('>', app_start)
if app_start < 0 or app_end < 0:
    raise SystemExit('HARD FAIL: AndroidManifest has no valid application tag')
app_tag = m[app_start:app_end + 1]
for attribute, value in (
    ('allowBackup', 'false'),
    ('fullBackupContent', 'false'),
    ('dataExtractionRules', '@xml/king_data_extraction_rules'),
):
    pattern = rf"""android:{attribute}\s*=\s*("[^"]*"|'[^']*')"""
    replacement = f'android:{attribute}="{value}"'
    if re.search(pattern, app_tag):
        app_tag = re.sub(pattern, replacement, app_tag, count=1)
    else:
        app_tag = app_tag[:-1] + ' ' + replacement + '>'
m = m[:app_start] + app_tag + m[app_end + 1:]

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
shutil.copy('android_src/KingWireGuardCore.kt', os.path.join(ka, 'KingWireGuardCore.kt'))
xml_dir = os.path.join(APP, 'android/app/src/main/res/xml')
os.makedirs(xml_dir, exist_ok=True)
shutil.copy('android_src/king_file_paths.xml', os.path.join(xml_dir, 'king_file_paths.xml'))
shutil.copy('android_src/king_backup_rules.xml', os.path.join(xml_dir, 'king_backup_rules.xml'))
shutil.copy('android_src/king_data_extraction_rules.xml', os.path.join(xml_dir, 'king_data_extraction_rules.xml'))
print('OK: Native files, scoped update FileProvider paths, and private-data backup exclusions copied')

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
        # WireGuard is an independent userspace tunnel engine (libwg-go).
        if 'com.wireguard.android:tunnel' not in g:
            if name.endswith('.kts'):
                dep_text = '\\n    implementation("com.wireguard.android:tunnel:1.0.20260102")\\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")\\n'
                dep_block = re.search(r'dependencies\\s*\\{', g)
                if dep_block:
                    g = g[:dep_block.end()] + dep_text + g[dep_block.end():]
                else:
                    g += '\\ndependencies {\\n' + dep_text + '}\\n'
                compile_block = re.search(r'compileOptions\\s*\\{', g)
                if not compile_block:
                    raise SystemExit('HARD FAIL: app Gradle has no compileOptions block for WireGuard desugaring')
                close = g.find('}', compile_block.end())
                if close < 0:
                    raise SystemExit('HARD FAIL: malformed compileOptions block')
                if 'isCoreLibraryDesugaringEnabled' not in g[compile_block.end():close]:
                    g = g[:close] + '\\n        isCoreLibraryDesugaringEnabled = true\\n    ' + g[close:]
            else:
                dep_text = "\\n    implementation 'com.wireguard.android:tunnel:1.0.20260102'\\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.3'\\n"
                dep_block = re.search(r'dependencies\\s*\\{', g)
                if dep_block:
                    g = g[:dep_block.end()] + dep_text + g[dep_block.end():]
                else:
                    g += "\\ndependencies {\\n" + dep_text + "}\\n"
                compile_block = re.search(r'compileOptions\\s*\\{', g)
                if not compile_block:
                    raise SystemExit('HARD FAIL: app Gradle has no compileOptions block for WireGuard desugaring')
                close = g.find('}', compile_block.end())
                if close < 0:
                    raise SystemExit('HARD FAIL: malformed compileOptions block')
                if 'coreLibraryDesugaringEnabled' not in g[compile_block.end():close]:
                    g = g[:close] + '\\n        coreLibraryDesugaringEnabled true\\n    ' + g[close:]
        open(gp, 'w', encoding='utf-8').write(g)

# Do not inject ndk.abiFilters when the Flutter build uses --split-per-abi.
# AGP rejects the combination of ndk abiFilters and splits. The build command
# already limits target-platform to android-arm64 and creates the matching APK.
print('OK: Gradle (ABI selection is controlled by Flutter --target-platform/--split-per-abi)')

# Flutter's Gradle plugin is an included build. Its settings are separate from
# build_app/android/settings.gradle(.kts). The Flutter SDK settings file in
# recent releases may declare dependencyResolutionManagement but omit
# pluginManagement; Gradle then falls back to the Plugin Portal alone for
# Kotlin DSL plugin transitives. Add explicit Google + Maven Central sources.
flutter_root = os.environ.get('FLUTTER_ROOT')
if flutter_root:
    for settings_name in ('settings.gradle.kts', 'settings.gradle'):
        flutter_settings = os.path.join(
            flutter_root, 'packages/flutter_tools/gradle', settings_name
        )
        if not os.path.isfile(flutter_settings):
            continue
        with open(flutter_settings, encoding='utf-8') as f:
            flutter_settings_text = f.read()

        mirror_repo = (
            f'        maven {{ url = uri("{MAVEN_CENTRAL_MIRROR}") }}\n'
            if settings_name.endswith('.kts') else
            f'        maven {{ url "{MAVEN_CENTRAL_MIRROR}" }}\n'
        )
        aliyun_flutter_repos = (
            '        maven { url = uri("' + ALIYUN_CENTRAL_MIRROR + '") }\n'
            '        maven { url = uri("' + ALIYUN_GRADLE_PLUGIN_MIRROR + '") }\n'
            if settings_name.endswith('.kts') else
            '        maven { url "' + ALIYUN_CENTRAL_MIRROR + '" }\n'
            '        maven { url "' + ALIYUN_GRADLE_PLUGIN_MIRROR + '" }\n'
        )
        pm = re.search(r'pluginManagement\s*\{', flutter_settings_text)
        if not pm:
            flutter_settings_text = (
                'pluginManagement {\n'
                '    repositories {\n'
                + mirror_repo
                + aliyun_flutter_repos
                + '        google()\n'
                '        mavenCentral()\n'
                '        gradlePluginPortal()\n'
                '    }\n'
                '}\n\n' + flutter_settings_text
            )
            print('  OK: Added pluginManagement repositories to Flutter included build')
        else:
            block_open = pm.end() - 1
            depth = 0
            block_close = None
            for pos in range(block_open, len(flutter_settings_text)):
                if flutter_settings_text[pos] == '{':
                    depth += 1
                elif flutter_settings_text[pos] == '}':
                    depth -= 1
                    if depth == 0:
                        block_close = pos
                        break
            if block_close is None:
                raise SystemExit('HARD FAIL: malformed Flutter pluginManagement block')
            block = flutter_settings_text[block_open + 1:block_close]
            repo_match = re.search(r'repositories\s*\{', block)
            if not repo_match:
                raise SystemExit('HARD FAIL: Flutter pluginManagement has no repositories block')
            repo_open = block_open + 1 + repo_match.end() - 1
            depth = 0
            repo_close = None
            for pos in range(repo_open, block_close + 1):
                if flutter_settings_text[pos] == '{':
                    depth += 1
                elif flutter_settings_text[pos] == '}':
                    depth -= 1
                    if depth == 0:
                        repo_close = pos
                        break
            if repo_close is None:
                raise SystemExit('HARD FAIL: malformed Flutter plugin repositories block')
            repositories_text = flutter_settings_text[repo_open:repo_close]
            additions = ''
            if mirror_repo.strip() not in repositories_text:
                additions += '\n' + mirror_repo.rstrip('\n')
            for mirror_line in aliyun_flutter_repos.splitlines():
                if mirror_line.strip() not in repositories_text:
                    additions += '\n' + mirror_line
            if 'google()' not in repositories_text:
                additions += '\n        google()'
            if 'mavenCentral()' not in repositories_text:
                additions += '\n        mavenCentral()'
            if additions:
                flutter_settings_text = (
                    flutter_settings_text[:repo_open + 1] + additions
                    + flutter_settings_text[repo_open + 1:]
                )
                print('  OK: Added Maven Central mirror and missing Flutter plugin repositories')
            else:
                print('  OK: Flutter included-build plugin repositories already complete')

        # The included Flutter build resolves implementation(...) dependencies
        # from dependencyResolutionManagement, not pluginManagement.
        flutter_settings_text = add_maven_mirror_to_scope(
            flutter_settings_text,
            'dependencyResolutionManagement',
            mirror_repo.rstrip('\\n'),
        )

        with open(flutter_settings, 'w', encoding='utf-8') as f:
            f.write(flutter_settings_text)
        break

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
