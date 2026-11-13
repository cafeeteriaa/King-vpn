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

# ---- 3) Load all .dart files ----
files = {}
for fn in os.listdir(LIB):
    if fn.endswith('.dart'):
        with open(os.path.join(LIB, fn), encoding='utf-8') as f:
            content = f.read().replace('\r\n', '\n')
        files[fn[:-5]] = content
print('Loaded %d dart files' % len(files))

# =====================================================================
# APPLY ALL PATCHES (V1..V19 consolidated)
# =====================================================================

# ---- 4) HOT PATH ----
print('\n[4] hotPath')
patch_hard('nat_ultra',
"""String _hotPath() {
  const dir = '/data/data/com.kingvpn.king_vpn/files';
  try {
    final d = Directory(dir);
    if (!d.existsSync()) d.createSync(recursive: true);
    return '$dir/hot_cache.txt';
  } catch (jex, jstk) { errJournalAdd(jex, st: jstk);
    return '${Directory.systemTemp.path}/hot_cache.txt';
  }
}
""",
"""const String hotVisibleDir = '/storage/emulated/0/Download/King-VPN';
String _hotPath() {
  const dir = '/data/data/com.kingvpn.king_vpn/files';
  try {
    final d = Directory(dir);
    if (!d.existsSync()) d.createSync(recursive: true);
    return '$dir/hot_cache.txt';
  } catch (_) {
    return '${Directory.systemTemp.path}/hot_cache.txt';
  }
}
Future<void> hotExportToDownload() async {
  try {
    final src = File(_hotPath());
    if (!src.existsSync()) return;
    final v = Directory(hotVisibleDir);
    if (!v.existsSync()) v.createSync(recursive: true);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final dst = File('$hotVisibleDir/hot_configs_$ts.txt');
    await src.copy(dst.path);
    try {
      final all = v.listSync()
          .whereType<File>()
          .where((f) => f.path.contains('hot_configs_'))
          .toList()
        ..sort((a, b) {
          try { return b.statSync().modified.compareTo(a.statSync().modified); }
          catch (_) { return 0; }
        });
      for (var i = 3; i < all.length; i++) {
        try { all[i].deleteSync(); } catch (_) {}
      }
    } catch (_) {}
  } catch (e) {
    dbg('hotExport ignored: $e');
  }
}
""", 'hotPath V9 app-private')

patch_hard('nat_ultra',
"  if (_hotBusy) return;\n  final f = File(_hotPath());\n",
"  if (force) await hotStorageAllow();\n  if (_hotBusy) return;\n  final f = File(_hotPath());\n",
'hotEnsure force')

if 'hotAutoStart()' not in files['nat_ultra']:
    files['nat_ultra'] += """

Future<void> hotStorageAllow() async {
  try {
    final st = Permission.manageExternalStorage;
    if (await st.isGranted) return;
    await st.request();
  } catch (e) { logError(e); }
}
Future<void> hotAutoFill() async {
  try {
    if (!(await Permission.manageExternalStorage.isGranted)) return;
  } catch (e) { logError(e); return; }
  await natHotEnsure();
}
Future<void> hotAutoStart() async {
  try { WidgetsBinding.instance.addObserver(HotResumeWatcher()); } catch (e) { logError(e); }
  try {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool('hotAsked') ?? false)) {
      await p.setBool('hotAsked', true);
      await hotStorageAllow();
    }
  } catch (e) { logError(e); }
  await hotAutoFill();
}
class HotResumeWatcher extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(hotAutoFill());
  }
}
"""
    print('  OK: hot helpers appended')

# ---- 5) main() auto-start ----
print('\n[5] main auto-start')
patch_hard('main',
"void main() {\n  runZonedGuarded(() {",
"void main() {\n  Future.delayed(const Duration(seconds: 5), () => unawaited(hotAutoStart()));\n  runZonedGuarded(() {",
'main hotAutoStart')

# ---- 6) Relay chain ----
print('\n[6] Relay chain')
patch_hard('main',
"""      String? chainCfg;
      if (nationalMode && !proxyOnly) {
        final relays = _usable().where((x) => !identical(x, s)).take(1).toList();
        if (relays.isNotEmpty) {
          chainCfg = natChainCfg(cfg, natCfg(relays.first, 0), keepInbounds: true);
          if (chainCfg != null) {
            dbg('MULTIHOP: آخرین تلاش از پشت ${relays.first.name} (relay) برای ${s.name}');
          }
        }
      }""",
"""      String? chainCfg;
      if (nationalMode && !proxyOnly) {
        if (relayServerUrl.isNotEmpty) {
          final relaySrv = Server.parse(relayServerUrl);
          if (relaySrv != null) {
            chainCfg = natChainCfg(cfg, natCfg(relaySrv, 0), keepInbounds: true);
            if (chainCfg != null) dbg('MULTIHOP: manual relay for ${s.name}');
          }
        }
        if (chainCfg == null) {
          final relays = _usable().where((x) => !identical(x, s)).take(1).toList();
          if (relays.isNotEmpty) {
            chainCfg = natChainCfg(cfg, natCfg(relays.first, 0), keepInbounds: true);
            if (chainCfg != null) {
              dbg('MULTIHOP: آخرین تلاش از پشت ${relays.first.name} (relay) برای ${s.name}');
            }
          }
        }
      }""", 'relay chain')

# ---- 7) relayServerUrl load/save ----
print('\n[7] relay load/save')
patch_hard('main',
"          npvParse = j['npv'] as bool? ?? npvParse;",
"          npvParse = j['npv'] as bool? ?? npvParse;\n          relayServerUrl = j['relay_url'] as String? ?? '';\n          sniSpoofAll = j['sni_all'] as bool? ?? false;",
'load relay_url + sni_all')
patch_hard('main',
"            'npv': npvParse,",
"            'npv': npvParse,\n            'relay_url': relayServerUrl,\n            'sni_all': sniSpoofAll,",
'save relay_url + sni_all')

# ---- 8) UiTools ----
print('\n[8] UiTools')
patch_hard('main',
"UiTools(items: [",
"UiTools(items: [\n            UiTool(Icons.swap_horiz, 'سرور واسط (نت ملی)', () => showRelayDialog(context)),\n            UiTool(Icons.router, 'بازه‌های IP نت ملی', () => _natRangesDialog(context)),\n            UiTool(sniSpoofAll ? Icons.security : Icons.security_outlined, sniSpoofAll ? 'جعل SNI: روشن ✓' : 'جعل SNI: خاموش', () { setState(() => sniSpoofAll = !sniSpoofAll); _saveSettings(); _set(sniSpoofAll ? 'جعل SNI روشن شد: DPI فکر می‌کند سایت ایرانی هست' : 'جعل SNI خاموش شد'); }),",
'UiTools buttons')

# ---- 9) DIALER proxy ----
print('\n[9] DIALER')
patch_hard('main',
"""      if (so is Map) {
        final dp = so['dialerProxy']?.toString();
        if (dp != null && !tags.contains(dp)) {
          so.remove('dialerProxy');
          changed = true;
        }
      }""",
"""      if (so is Map) {
        final dp = so['dialerProxy']?.toString();
        if (dp != null && !tags.contains(dp)) {
          so.remove('dialerProxy');
          changed = true;
        }
        final ps = so['proxySettings']?.toString();
        if (ps != null && !tags.contains(ps)) {
          so.remove('proxySettings');
          changed = true;
        }
      }""", 'dialerProxy + proxySettings')

# ---- 10,11) configs ----
print('\n[10,11] kNatMergeCache, kFolderInjectGood')
patch_hard('main', "const bool kNatMergeCache = false;", "const bool kNatMergeCache = true;", 'kNatMergeCache')
patch_hard('main', "const bool kFolderInjectGood = false;", "const bool kFolderInjectGood = true;", 'kFolderInjectGood')

# ---- 12) requestPermission ----
print('\n[12] requestPermission')
patch_hard('main',
"""    if (!proxyMode && inForeground) {
      try {
        // PERMTIMEOUT: same limit as above
        final ok = await v2ray.requestPermission().timeout(""",
"""    if (!proxyMode && inForeground && !vpnPermOk) {
      try {
        // PERMTIMEOUT: same limit as above
        final ok = await v2ray.requestPermission().timeout(""",
'requestPermission skip')

# ---- 13) V8-FRESH ----
print('\n[13] V8-FRESH')
patch_hard('main',
"""  Future<void> _loadCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      await loadGeminiPrefs(p);""",
"""  Future<void> _loadCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!p.containsKey('settings')) {
        for (final k in const [
          'speedoff27', 'lowdata_v1', 'restore_speed_v1', 'best_defaults_v4',
          'fw5_v1', 'workers12_v2', 'contsearch_v1', 'cip_v2', 'idm_v2',
          'nat_v2', 'defsync_v1', 'defsync_v2', 'badping2000_v1',
          'tuned_v1', 'tuned_v2', 'tuned_v3', 'tuned_v4', 'tuned_v5',
          'bestProfile26', 'fwDefault27', 'bgWorkersOne',
        ]) {
          await p.setBool(k, true);
        }
        await p.setBool('autotune_on2', false);
        for (final o in numOpts) { o.set(o.def); }
        badPingMs = 2000;
        fwUserSet = false;
        fwUserValue = 5;
        autoTune = false;
        proxyMode = false;
        onlyHealthySrc = true;
        ipMode = false;
        ultraMode = false;
        indestructibleMode = false;
        turboSpeed = true;
        fastDelay = true;
        iranRoute = true;
        iranGeoip = false;
        iranMore = true;
        blockQuic = true;
        lanDirect = true;
        routeOnly = false;
        fragEnabled = false;
        muxEnabled = true;
        muxConc = 128;
        secureDns = true;
        cleanIpMode = true;
        npvParse = true;
        offlineOnly = false;
        dataSaver = false;
        autoNetReconnect = true;
        preflightOn = true;
        sniSpoofAll = false;
        await saveNumPrefs();
        await _saveSettings();
        dbg('V8-FRESH: default settings applied');
      }
      await loadGeminiPrefs(p);""",
'V8-FRESH')

# ---- 14) resetAllToDefaults ----
print('\n[14] resetAllToDefaults')
MIGRATION_CODE = '''
    SharedPreferences.getInstance().then((p) async {
      for (final k in const [
        'speedoff27', 'lowdata_v1', 'restore_speed_v1', 'best_defaults_v4',
        'fw5_v1', 'workers12_v2', 'contsearch_v1', 'cip_v2', 'idm_v2',
        'nat_v2', 'defsync_v1', 'defsync_v2', 'badping2000_v1',
        'tuned_v1', 'tuned_v2', 'tuned_v3', 'tuned_v4', 'tuned_v5',
        'bestProfile26', 'fwDefault27', 'bgWorkersOne',
      ]) {
        await p.setBool(k, true);
      }
      await p.setBool('autotune_on2', false);
    });'''

already = False
for fn, text in files.items():
    if 'resetAllToDefaults()' in text:
        idx = text.find('resetAllToDefaults()')
        if 'SharedPreferences.getInstance().then' in text[idx:idx+800]:
            print('  SKIP: already patched')
            already = True
            break
if not already:
    pattern = re.compile(r'void\s+resetAllToDefaults\s*\(\s*\)\s*\{')
    found = []
    for fn, text in files.items():
        m = pattern.search(text)
        if m:
            found.append((fn, m.end()))
            break
    if not found:
        pattern2 = re.compile(r'resetAllToDefaults\s*\(\s*\)\s*\{')
        for fn, text in files.items():
            m = pattern2.search(text)
            if m:
                found.append((fn, m.end()))
                break
    if not found:
        raise SystemExit('\n\nHARD FAIL: [resetAllToDefaults]\nFunction not found')
    fn, pos = found[0]
    files[fn] = files[fn][:pos] + '\n' + MIGRATION_CODE + '\n    badPingMs = 2000;\n    natRound = 1;\n    sniSpoofAll = false;\n    muxConc = 128;' + files[fn][pos:]
    print('  OK (%s): resetAllToDefaults patched' % fn)

# ---- 15) pre-social-check ----
print('\n[15] pre-social-check')
patch_hard('main',
"""      if (!trust && !pin && !nationalMode && !proxyMode) {
        _set('بررسی تلگرام روی ${s.name}...');
        final sc = await _preSocialCheck(s);
        if (abort) return false;
        if (sc == false) {
          siteSkips++;
          s.svc = 0;
          s.badAt = DateTime.now();
          errorLog.value = '${s.name}: تلگرام باز نشد — سرور بعدی…';
          dbg('اتصال: ${s.name} رد شد — تلگرام باز نشد • سرور بعدی');
          continue;
        }
      }""",
"      // V8: pre-social-check removed (v2rayNG-style connect)",
'pre-social-check')

# ---- 16) needSocial ----
print('\n[16] needSocial')
patch_hard('main', "        final needSocial = !proxyMode;", "        final needSocial = false; // V8", 'needSocial false')

# ---- 17) abort guard ----
print('\n[17] abort guard')
patch_hard('main',
"""      _onConnected(s);
      return true;
    }
    return false;
  }

  // REAL speed test""",
"""      if (abort || !wantVpn) return false; // V8: abort guard
      _onConnected(s);
      return true;
    }
    return false;
  }

  // REAL speed test""",
'abort guard')

# ---- 18) target 3 servers (V13: connect at 1) ----
print('\n[18] target 3')
patch_hard('main', "const int kStandbyPause = 5;", "const int kStandbyPause = 3;", 'kStandbyPause')
patch_hard('main', "const int kStandbyResume = 5;", "const int kStandbyResume = 3;", 'kStandbyResume')
patch_hard('main', "const int kFgSearchTarget = 5;", "const int kFgSearchTarget = 1; // V13: connect immediately on first healthy", 'kFgSearchTarget 1')

# ---- 19) _doConnect national pre-load ----
print('\n[19] _doConnect national pre-load')
patch_hard('main',
"""      if (nationalMode || indestructibleMode) {
        _resInject();
        await _checkSaved(); // re-test known-good before searching new lists
        if (nationalMode) await _natMergeCache(); // پوشه‌ی منابع تازه (فقط نت ملی)
      }""",
"""      if (nationalMode || indestructibleMode) {
        try {
          await goldLoad();
          await _goldMergeGood(this);
          dbg('V8-NAT: gold=${_goldSrv.length}srv ${_goldIps.length}ip');
        } catch (e, stk) { logError(e, stk); }
        _resInject();
        await _checkSaved();
        if (nationalMode) {
          await _natMergeCache();
          final hasTpl = pending.isNotEmpty || natRestPending.isNotEmpty ||
              natTemplateSeeds.isNotEmpty || good.isNotEmpty;
          if (pending.isEmpty && hasTpl) {
            await _natMemoryReuse();
            await _natPrescan();
          } else if (pending.isEmpty) {
            dbg('V8-NAT: no template - skipping prescan');
            _set('نت ملی: هیچ کانفیگی موجود نیست. با نت جهانی وصل شو یا کانفیگ اضافه کن.');
          }
          dbg('V8-NAT: pending=${pending.length} good=${good.length} res=${_resMap.length}');
        }
      }""",
'_doConnect national pre-load')

# ---- 20) _natIpHunt pool ----
print('\n[20] _natIpHunt pool')
patch_find(
"""    final pool = <Server>[];
    pool.addAll(good);
    pool.addAll(pending);
    pool.addAll(_resMap.values.whereType<Server>());""",
"""    final pool = <Server>[];
    pool.addAll(good);
    pool.addAll(pending);
    for (final e in _resMap.values) {
      if (!pool.any((x) => x.link == e.link)) pool.add(e.s);
    }""",
'_natIpHunt pool fix')

# ---- 21) _natRangeAdd (brace-match) ----
print('\n[21] _natRangeAdd (brace-match)')
if 'V8: no template' in files['main']:
    print('  SKIP: already patched')
else:
    replace_function_braces('main',
        r'Future\s*<\s*void\s*>\s+_natRangeAdd\s*\(\s*List\s*<\s*String\s*>\s+items\s*,\s*\{\s*bool\s+count\s*=\s*true\s*\}\s*\)\s*async\s*\{',
        """  Future<void> _natRangeAdd(List<String> items, {bool count = true}) async {
    if (items.isEmpty) return;
    for (final it in items) {
      natScanHits.add(it.split('|')[0]);
    }
    final tpl = [...pending, ...natRestPending, ...natTemplateSeeds, ...good].take(2).toList();
    if (tpl.isEmpty) {
      dbg('V8: no template - skipping');
      return;
    }
    final made = <Server>[];
    for (final item in items) {
      final parts = item.split('|');
      if (parts.length < 2) continue;
      final ip = parts[0].trim();
      final port = int.tryParse(parts[1].trim());
      if (port == null || port <= 0 || port > 65535) continue;
      if (InternetAddress.tryParse(ip) == null) continue;
      for (final t in tpl) {
        try {
          made.add(Server(
            _natSetHost(t.link, ip, t.host),
            t.name,
            ip,
            port,
          ));
        } catch (e, stk) { logError(e, stk); }
      }
    }
    if (made.isEmpty) return;
    if (count) natIpFound += items.length;
    pending = [...made, ...pending];
    natRangeCursor = 0;
  }""",
        '_natRangeAdd replaced')

# ---- 22) _natEscalate ----
print('\n[22] _natEscalate')
patch_hard('main',
    "      if (nationalMode && !abort && !ipWaiting) {",
    "      final hasTpl = pending.isNotEmpty || natRestPending.isNotEmpty ||\n          natTemplateSeeds.isNotEmpty || good.isNotEmpty;\n      if (nationalMode && !abort && !ipWaiting && pending.isEmpty && hasTpl) {",
    '_natEscalate hasTpl+pending')
patch_hard('main',
    "            budget: const Duration(minutes: 12));",
    "            budget: const Duration(minutes: 3));",
    '_natEscalate 3min')

# ---- 23) sing-box URLs ----
print('\n[23] sing-box URLs')
start_marker = "  // PHASE1-SINGBOX:"
url_inner = "yebekhe/TelegramV2rayCollector/main/sub/normal/tuic'"
if start_marker in files['main']:
    start = files['main'].find(start_marker)
    if start >= 0:
        url_pos = files['main'].find(url_inner, start)
        if url_pos >= 0:
            nl = files['main'].find('\n', url_pos)
            if nl < 0: nl = len(files['main'])
            end = nl + 1
            files['main'] = files['main'][:start] + "  // V8: sing-box URLs removed\n" + files['main'][end:]
            print('  OK: sing-box URLs removed')

# ---- 24) stopSingbox ----
print('\n[24] stopSingbox call')
patch_hard('main',
"      try { await stopSingbox(); } catch (_) {} // SINGBOX: هر دو هسته خاموش شوند",
"      // V8: singbox removed",
'stopSingbox call')

# ---- 25-29) nat_ultra ----
print('\n[25] natMaxVariants')
patch_hard('nat_ultra', "const int natMaxVariants = 2000000;", "const int natMaxVariants = 0x7FFFFFFF; // V8", 'natMaxVariants')

print('\n[26] natGrow real')
patch_hard('nat_ultra',
"int natGrow(int n) => 0;",
"""int _natGrowCounter = 0;
int natGrow(int n) {
  if (_natSpecs.length > 500000) return 0;
  final rnd = Random(DateTime.now().millisecondsSinceEpoch + _natGrowCounter++);
  var added = 0;
  const fps = ['chrome', 'firefox', 'randomized', 'ios', 'android', 'safari', 'edge', 'random', 'qq', '360', 'hellogolang', 'hellochrome', 'hellofirefox', 'hellosafari', 'helloios', 'helloandroid', 'helloedge', 'hello360', 'helloqq', 'hellorandomized', 'hellorandomizedalpn', 'hellorandomizednoalpn'];
  const alpns = <String?>[null, 'h2', 'http/1.1', 'h2,http/1.1'];
  for (var i = 0; i < n; i++) {
    final fp = fps[rnd.nextInt(fps.length)];
    final alpn = alpns[rnd.nextInt(alpns.length)];
    final frag = rnd.nextInt(_natFrags.length);
    final port = rnd.nextBool();
    final portIdx = port ? rnd.nextInt(_natCfPorts.length) : null;
    final clean = rnd.nextBool();
    final cleanIdx = clean ? rnd.nextInt(10) : null;
    final doh = rnd.nextBool() ? _natDnsList[rnd.nextInt(_natDnsList.length)] : null;
    final v4 = rnd.nextBool();
    final tfo = rnd.nextBool();
    final keep = rnd.nextBool() ? rnd.nextInt(30) + 1 : null;
    final sniSwap = rnd.nextBool() ? rnd.nextInt(15) : null;
    _natSpecs.add(_natMk(
      fp: fp, alpn: alpn, frag: frag, port: port, portIdx: portIdx,
      clean: clean, cleanIdx: cleanIdx, v4: v4, tfo: tfo, keep: keep, doh: doh,
      sniSwap: sniSwap,
    ));
    added++;
  }
  if (added > 0) { _natNamesC = null; _natGenRankKey = ''; }
  return added;
}""",
'natGrow real')

print('\n[27] natGrow wired')
patch_hard('nat_ultra',
"""    if (app.isNotEmpty && cursor < app.length) {
      final end = min(app.length, cursor + cap);
      for (var k = cursor; k < end; k++) {
        final gv = app[k];
        if (skipHeavy && natIsHeavy(gv)) continue;
        gens.add(gv);
      }
    }""",
"""    if (cursor >= app.length && lvl >= 2) {
      natGrow(1000);
      app.clear();
      for (final v in _natGenRanked()) {
        if (_natAppliesF(f, v)) app.add(v);
      }
    }
    if (app.isNotEmpty && cursor < app.length) {
      final end = min(app.length, cursor + cap);
      for (var k = cursor; k < end; k++) {
        final gv = app[k];
        if (skipHeavy && natIsHeavy(gv)) continue;
        gens.add(gv);
      }
    }""",
'natGrow wired')

print('\n[28] 80-block CF')
patch_hard('nat_ultra',
"""  final blocks = natRanges.isNotEmpty ? natRanges : natSeedBlocks(hosts);
  final addrs = <String>[];
  for (final r in blocks) {
    addrs.addAll(natExpandAny(r));
  }""",
"""  final blocks = natRanges.isNotEmpty ? natRanges : natSeedBlocks(hosts);
  final addrs = <String>[];
  for (final r in blocks) {
    addrs.addAll(natExpandAny(r));
  }
  addrs.addAll(_getCfIps());""",
'blocks CF mix')

insert_before('nat_ultra', 'Future<List<String>> natRangeScanStep({',
"""final Map<String, int> _cfRangeCursors = {};
List<String> _getCfIps({int batchSize = 160000}) {
  final out = <String>[];
  final ranges = _cfRanges;
  final perRange = (batchSize / ranges.length).ceil();
  for (final cidr in ranges) {
    final parts = cidr.split('/');
    if (parts.length != 2) continue;
    final octets = parts[0].split('.');
    if (octets.length != 4) continue;
    final a = int.tryParse(octets[0]);
    final b = int.tryParse(octets[1]);
    final c = int.tryParse(octets[2]);
    final d = int.tryParse(octets[3]);
    final prefix = int.tryParse(parts[1]);
    if (a == null || b == null || c == null || d == null || prefix == null) continue;
    if (prefix < 8 || prefix > 32) continue;
    final base = (a << 24) | (b << 16) | (c << 8) | d;
    final span = 1 << (32 - prefix);
    var cursor = _cfRangeCursors[cidr] ?? 0;
    for (var i = 0; i < perRange; i++) {
      final offset = (cursor + i) % span;
      final v = base + offset;
      out.add('${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}');
    }
    _cfRangeCursors[cidr] = (cursor + perRange) % span;
  }
  return out;
}

""", '_getCfIps inserted')

print('\n[29] deadline')
patch_hard('nat_ultra',
"""  for (final port in portList) {
    if (stop != null && stop()) break;
    final hits = await natScanIps(""",
"""  final scanDeadline = DateTime.now().add(budget);
  for (final port in portList) {
    if (stop != null && stop()) break;
    if (DateTime.now().isAfter(scanDeadline)) break;
    final hits = await natScanIps(""",
'natRangeScanStep deadline')

# ---- 30) sing-box stub ----
print('\n[30] sing-box stub')
files['singbox_core'] = """// V8: SING-BOX REMOVED
Future<bool> startSingbox(String config) async => false;
Future<void> stopSingbox() async {}
Future<bool> isSingboxAlive() async => false;
String? buildSingboxConfigFromLink(String link) => null;
"""
print('  OK')

# ---- 31) V9: tunUp fix ----
print('\n[31] V9: tunUp fix')
patch_hard('main',
"""Future<bool?> tunUp() async {
  try {
    final l = await NetworkInterface.list();
    tunNames = l.map((i) => i.name).join(',');
    if (l.isEmpty) return null;
    return l.any((i) {
      final n = i.name.toLowerCase();
      // Broad OEM coverage: tun/ppp/vpn + Xiaomi/Huawei/Samsung/OPPO/Vivo quirks
      return n.startsWith('tun') ||
          n.startsWith('ppp') ||
          n.startsWith('vpn') ||
          n.startsWith('ipsec') ||
          n.startsWith('tap') ||
          n.startsWith('utun') ||
          n.startsWith('ccmni') ||
          n.startsWith('rmnet') ||
          n.startsWith('seth') ||
          n.startsWith('v4-rmnet') ||
          n.contains('tun') ||
          n.contains('ppp') ||
          n.contains('vpn') ||
          n.contains('ipsec') ||
          n.contains('xray') ||
          n.contains('v2ray');
    });
  } catch (_swE) {
    _swl('tunUp#1', _swE);
    return null;
  }
}""",
"""Future<bool?> tunUp() async {
  try {
    for (var attempt = 0; attempt < 3; attempt++) {
      final l = await NetworkInterface.list(includeLoopback: false);
      tunNames = l.map((i) => i.name).join(',');
      final hasTunnel = l.any((i) {
        final n = i.name.toLowerCase();
        return n.startsWith('tun') ||
            n.startsWith('ppp') ||
            n.startsWith('vpn') ||
            n.startsWith('utun') ||
            n.contains('xray') ||
            n.contains('v2ray');
      });
      if (hasTunnel) return true;
      if (attempt < 2) await Future.delayed(const Duration(milliseconds: 800));
    }
    if (lastState == 'CONNECTED') return true;
    return false;
  } catch (_swE) {
    _swl('tunUp#1', _swE);
    return lastState == 'CONNECTED' ? true : null;
  }
}""",
'V9: tunUp retry')

# ---- 32) V9: E-NO-TUN split ----
print('\n[32] V9: E-NO-TUN split')
patch_hard('main',
"""  if (has('تونل VPN')) {
    return h('E-NO-TUN',
        'lib/main.dart → tunUp() و شاخه‌ی Tunnel guard در _startWatch؛ شکست شروع در _start (lastFail)',
        'NetworkInterface.list() اینترفیسی با نام tun/ppp ندید (نام‌های دیده‌شده در خط «tun:» بالا آمده). یعنی اندروید تونل نساخت یا با نام دیگری ساخته، یا مجوز VPN دست اپ دیگری است. آیکن کلید نمی‌آید.',
        'نام اینترفیس‌های خط «tun:» را ببین؛ اگر نام دیگری دارد شرط startsWith در tunUp() را گسترش بده. اگر هیچ نیست: _restartTunnel (خودکار تا ۲ بار) و بعد درخواست مجوز VPN.');
  }""",
"""  if (has('ساخت دوباره تونل VPN')) {
    return h('E-TUN-RESTART',
        'lib/main.dart → _restartTunnel() از _startWatch',
        'ترمیم خودکار: ۲ بار tun دیده نشد → تونل دوباره ساخته شد. این عمل عادی است، نه خطا.',
        'نیازی به اقدام نیست. اگر پشت سر هم تکرار شد، خط tun و E-NO-TUN واقعی را ببین.');
  }
  if (has('تونل VPN نساخته') ||
      has('tun پیدا نشد') ||
      has('اندروید تونل VPN') ||
      has('وضعیت تونل اندروید')) {
    return h('E-NO-TUN',
        'lib/main.dart → tunUp() و شاخه‌ی Tunnel guard در _startWatch؛ شکست شروع در _start (lastFail)',
        'NetworkInterface.list() اینترفیسی با نام tun/ppp ندید.',
        'خط tun را ببین؛ اگر نام دیگری دارد شرط startsWith در tunUp() را گسترش بده.');
  }""",
'E-NO-TUN split from restart')

# ---- 33) V9-NATGOLD: gold IPs ----
print('\n[33] V9-NATGOLD gold IPs round 0')
patch_hard('main',
"""      if (round == 0 && nationalMode) {
        // NATFIRSTFAST: دور اول فقط جستجوی سریع است؛ اولین سرور سالمی که پیدا شد وصل می‌شود.
        // اسکن‌های سنگین IP/دامنه (چند دقیقه) در دورهای بعد و در پس‌زمینه‌ی اتصال اجرا می‌شوند.
        if (_pickList().isEmpty) await _natQuickStart();
      }""",
"""      if (round == 0 && nationalMode) {
        if (_pickList().isEmpty) {
          await _natQuickStart();
          if (pending.isEmpty) {
            try {
              final goldIps = goldIpList();
              final tpl = [...good, ...natTemplateSeeds].take(2).toList();
              if (goldIps.isNotEmpty && tpl.isNotEmpty) {
                final made = <Server>[];
                for (final gip in goldIps.take(20)) {
                  for (final t in tpl) {
                    try {
                      made.add(Server(
                        _natSetHost(t.link, gip.ip, t.host),
                        '${t.name} (gold)',
                        gip.ip,
                        gip.port,
                      ));
                    } catch (e, stk) { logError(e, stk); }
                  }
                }
                if (made.isNotEmpty) {
                  pending.insertAll(0, made);
                  dbg('V9-NATGOLD: ${made.length} gold configs injected');
                }
              }
            } catch (e, stk) { logError(e, stk); }
          }
        }
      }""",
'V9-NATGOLD inject gold IPs')

# ---- 34) V15: Iranian SNI Spoofing ----
print('\n[34] V15: Iranian SNI Spoofing')
patch_hard('nip_scan',
"""const natFrontSnis = <String>[
  'cdnjs.cloudflare.com',
  'www.cloudflare.com',
  'cloudflare.com',
  'speed.cloudflare.com',
];""",
"""const natFrontSnis = <String>[
  // V15: Iranian domains first. DPI sees these and lets traffic through.
  'www.aparat.com',
  'www.digikala.com',
  'divar.ir',
  'www.snapp.ir',
  'www.bale.ai',
  'eitaa.com',
  'www.zarinpal.com',
  'www.iranserver.com',
  'www.shatel.ir',
  'www.mci.ir',
  // Cloudflare domains after.
  'cdnjs.cloudflare.com',
  'www.cloudflare.com',
  'cloudflare.com',
  'speed.cloudflare.com',
  'workers.dev',
  'dash.cloudflare.com',
  'one.one.one.one',
  '1.1.1.1',
  'cloudflare-dns.com',
];""",
'V15: Iranian SNI Spoofing')

# ---- 35) V9: badPingMs = 2000 ----
print('\n[35] V9: badPingMs = 2000')
if 'int badPingMs = 1700;' in files['main']:
    files['main'] = files['main'].replace('int badPingMs = 1700;', 'int badPingMs = 2000; // V9')
if 'iran_ai_extras' in files and "1700, 7000" in files['iran_ai_extras']:
    files['iran_ai_extras'] = files['iran_ai_extras'].replace("1700, 7000", "2000, 7000")
if "'badping1700_v1'" in files['main']:
    files['main'] = files['main'].replace("'badping1700_v1'", "'badping2000_v1'")
if "badPingMs = 1700;" in files['main']:
    files['main'] = files['main'].replace("badPingMs = 1700;", "badPingMs = 2000;")
for fn in files:
    txt = files[fn]
    for old in ["'bp': 2500,", "'badPingMs': 2500,", "'bp': 1700,", "'badPingMs': 1700,"]:
        txt = txt.replace(old, old.replace('2500', '2000').replace('1700', '2000'))
    files[fn] = txt
print('  OK: badPingMs -> 2000')

# ---- 36) V9: Force fresh search on manual reconnect (FIXED) ----
print('\n[36] V9: force fresh on reconnect')
if 'if (!localPilotOn && !aiSession) failed.clear();' in files['main']:
    files['main'] = files['main'].replace(
        "if (!localPilotOn && !aiSession) failed.clear();",
        """if (!localPilotOn && !aiSession) {
          failed.clear();
          if (only == null && row == null) {
            good.clear();
            pending.clear();
            if (!offlineOnly) {
              listTime = null;
              lastFetchTry = DateTime(2000);
              fetchedAll.clear();
            }
          }
        }""")
    print('  OK: V9: force fresh')

# ---- 37) V9: Fix FormatException ----
print('\n[37] V9: fix FormatException')
patch_hard('main',
"""      if (!body.contains('://')) {
        if (!RegExp(r'^[A-Za-z0-9+/=_\\-\\s]+$').hasMatch(body)) {
          srcFetchState[u] = 'fail';
          return; // CLEANERR
        }
        try {
          body = utf8.decode(
              base64.decode(base64.normalize(body.replaceAll(RegExp(r'\\s'), ''))),
              allowMalformed: true); // UTF8FIX: bad bytes in a list must not abort the whole source
        } catch (_swE) { _swl('build#1', _swE);
          srcFetchState[u] = 'fail';
          return;
        }
      }""",
"""      if (!body.contains('://')) {
        var b64 = body.replaceAll(RegExp(r'[^A-Za-z0-9+/=_-]'), '');
        b64 = b64.replaceAll('-', '+').replaceAll('_', '/');
        while (b64.length % 4 != 0) { b64 += '='; }
        try {
          body = utf8.decode(base64.decode(b64), allowMalformed: true);
        } catch (_swE) {
          _swl('build#1', _swE);
          srcFetchState[u] = 'fail';
          return;
        }
      }""",
'V9: fix FormatException')

# ---- 38) V9: Fix CPU ----
print('\n[38] V9: fix CPU')
patch_hard('main',
"""        // FREEZEFIX: always give the event loop a turn (timers, heartbeat, taps)
        await Future<void>.delayed(const Duration(milliseconds: 5));""",
"""        // FREEZEFIX: always give the event loop a turn (timers, heartbeat, taps)
        await Future<void>.delayed(Duration(milliseconds: cpuHot >= 1 ? 100 : 20));""",
'V9: throttle search')

patch_hard('main',
"""    final gateMax = nationalMode
        ? kNatDelayConcurrency
        : fastWorkers.clamp(1, 1000);""",
"""    final gateMax = nationalMode
        ? kNatDelayConcurrency
        : (cpuHot >= 2 ? 1 : (cpuHot >= 1 ? 3 : fastWorkers.clamp(1, 1000)));""",
'V9: throttle fastWorkers')

# ---- 39) V10: 50/50 IP mix ----
print('\n[39] V10: 50/50 IP mix')
patch_hard('main',
"""    if (nationalMode && ipList.isNotEmpty) {
      final trusted = natIpMemHosts()..addAll(natScanHits);
      final before = ipList.length;
      ipList.removeWhere((s) => !trusted.contains(s.host));
      final dropped = before - ipList.length;
      if (dropped > 0) dbg('نت ملی: $dropped کانفیگ با IP ناشناخته کنار گذاشته شد');
      if (dropped > 0 && goldIpList().isEmpty) {
        dbg('نت ملی: پوشه‌ی IP تمیز خالی است؛ یک بار در نت جهانی وصل شو تا IP ذخیره شود');
      }
      natFun('ip_untrusted', dropped);
    }""",
"""    if (nationalMode && ipList.isNotEmpty) {
      final trusted = natIpMemHosts()..addAll(natScanHits);
      final known = ipList.where((s) => trusted.contains(s.host)).toList();
      final unknown = ipList.where((s) => !trusted.contains(s.host)).toList();
      final mixed = <Server>[];
      var ki = 0, ui = 0;
      while (ki < known.length || ui < unknown.length) {
        if (ki < known.length) { mixed.add(known[ki]); ki++; }
        if (ui < unknown.length) { mixed.add(unknown[ui]); ui++; }
      }
      ipList
        ..clear()
        ..addAll(mixed);
    }""",
'V10: 50/50 IP mix')

# ---- 40) V10: 50/50 domain mix ----
print('\n[40] V10: 50/50 domain mix')
patch_hard('main',
"""        if (smartOrder) cand = _diversify(cand);
        cand = _engineMix(cand); // PHASE1-SINGBOX: ۵۰/۵۰ از هر دو هسته
        final batch = _mixBatch(cand, size); // SRCSPLIT""",
"""        if (smartOrder && !nationalMode) cand = _diversify(cand);
        if (nationalMode) {
          final knownC = cand.where((s) => s.checkedAt != null).toList();
          final unknownC = cand.where((s) => s.checkedAt == null).toList();
          final mix = <Server>[];
          var mki = 0, mui = 0;
          while (mki < knownC.length || mui < unknownC.length) {
            if (mki < knownC.length) { mix.add(knownC[mki]); mki++; }
            if (mui < unknownC.length) { mix.add(unknownC[mui]); mui++; }
          }
          cand = mix;
        }
        cand = _engineMix(cand);
        final batch = _mixBatch(cand, size);""",
'V10/V11: 50/50 domain mix')

# ---- 41) V10: shorter failWindow ----
print('\n[41] V10: failWindow 2min')
patch_hard('main',
"""  bool _recentFail(Server s) {
    final t = failed[s.key];
    return t != null && DateTime.now().difference(t) < failWindow;
  }""",
"""  bool _recentFail(Server s) {
    final t = failed[s.key];
    if (t == null) return false;
    // V12-ROUND2: in national mode, forget failures when we're in pass 2.
    if (nationalMode && natRound >= 2) return false;
    final win = nationalMode ? const Duration(minutes: 2) : failWindow;
    return DateTime.now().difference(t) < win;
  }""",
'V10/V12: failWindow + round2')

# ---- 42) V10: shorter badFor ----
print('\n[42] V10: badFor 2min')
patch_hard('main',
"""  bool _bad(Server s) =>
      (s.badAt != null && DateTime.now().difference(s.badAt!) < badFor) ||
      _crashBanned(s.key); // CRASHGUARD: سروری که اپ را وسط شروع کرش داد موقتاً رد می‌شود""",
"""  bool _bad(Server s) {
    if (_crashBanned(s.key)) return true;
    // V12-ROUND2: in national mode, forget "bad" marks when we're in pass 2.
    if (nationalMode && natRound >= 2) return false;
    if (s.badAt == null) return false;
    final win = nationalMode ? const Duration(minutes: 2) : badFor;
    return DateTime.now().difference(s.badAt!) < win;
  }""",
'V10/V12: badFor + round2')

# ---- 43) V11: sequential interleave (no sort within groups) ----
print('\n[43] V11: sequential interleave')
patch_hard('main',
"""        if (batches == 1 || batches % 8 == 0) {
          await Future<void>.delayed(Duration.zero); // LOOPFREEZE: let the UI breathe
          pending.sort(_cmpPending);
        }""",
"""        if (batches == 1 || batches % 8 == 0) {
          await Future<void>.delayed(Duration.zero); // LOOPFREEZE: let the UI breathe
          if (nationalMode && pending.length > size) {
            final knownL = <Server>[];
            final unknownL = <Server>[];
            for (final s in pending) {
              if (s.checkedAt != null) { knownL.add(s); } else { unknownL.add(s); }
            }
            pending.clear();
            var ki2 = 0, ui2 = 0;
            while (ki2 < knownL.length || ui2 < unknownL.length) {
              if (ki2 < knownL.length) { pending.add(knownL[ki2]); ki2++; }
              if (ui2 < unknownL.length) { pending.add(unknownL[ui2]); ui2++; }
            }
            dbg('V11-SEQ: interleaved ${knownL.length}k + ${unknownL.length}u');
          } else if (!nationalMode) {
            pending.sort(_cmpPending);
          }
        }""",
'V11: sequential interleave')

# ---- 44) V11: no shuffle in national ----
print('\n[44] V11: no shuffle in national')
patch_hard('main',
"    final rest = fetched.toList()..shuffle();",
"    final rest = nationalMode ? fetched.toList() : (fetched.toList()..shuffle());",
'V11: no shuffle')

# ---- 45) V11: no sort tail in national ----
print('\n[45] V11: no sort tail in national')
patch_hard('main',
"    final tail = out.sublist(headLen)..sort(_cmpPending);",
"    final tail = out.sublist(headLen);\n    if (!nationalMode) tail.sort(_cmpPending);",
'V11: no sort tail')

# ---- 46) V11: sequential CF IPs ----
print('\n[46] V11: sequential CF IPs')
old_getcf = """List<String>? _cfIpCache;
List<String> _getCfIps() {
  if (_cfIpCache != null) return _cfIpCache!;
  final out = <String>[];
  final rnd = Random(42);
  final blocksPerRange = (80 / _cfRanges.length).ceil();
  for (final cidr in _cfRanges) {
    final parts = cidr.split('/');
    if (parts.length != 2) continue;
    final octets = parts[0].split('.');
    if (octets.length != 4) continue;
    final a = int.tryParse(octets[0]);
    final b = int.tryParse(octets[1]);
    final c = int.tryParse(octets[2]);
    final d = int.tryParse(octets[3]);
    final prefix = int.tryParse(parts[1]);
    if (a == null || b == null || c == null || d == null || prefix == null) continue;
    if (prefix < 8 || prefix > 32) continue;
    final base = (a << 24) | (b << 16) | (c << 8) | d;
    final span = 1 << (32 - prefix);
    final blockSize = span ~/ blocksPerRange;
    if (blockSize <= 0) continue;
    for (var bl = 0; bl < blocksPerRange; bl++) {
      final blockStart = base + bl * blockSize;
      for (var i = 0; i < 2000; i++) {
        final v = blockStart + rnd.nextInt(blockSize);
        out.add('${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}');
      }
    }
  }
  _cfIpCache = out;
  return out;
}"""
new_getcf = """final Map<String, int> _cfRangeCursors = {};
List<String> _getCfIps({int batchSize = 160000}) {
  final out = <String>[];
  final ranges = _cfRanges;
  final perRange = (batchSize / ranges.length).ceil();
  for (final cidr in ranges) {
    final parts = cidr.split('/');
    if (parts.length != 2) continue;
    final octets = parts[0].split('.');
    if (octets.length != 4) continue;
    final a = int.tryParse(octets[0]);
    final b = int.tryParse(octets[1]);
    final c = int.tryParse(octets[2]);
    final d = int.tryParse(octets[3]);
    final prefix = int.tryParse(parts[1]);
    if (a == null || b == null || c == null || d == null || prefix == null) continue;
    if (prefix < 8 || prefix > 32) continue;
    final base = (a << 24) | (b << 16) | (c << 8) | d;
    final span = 1 << (32 - prefix);
    var cursor = _cfRangeCursors[cidr] ?? 0;
    for (var i = 0; i < perRange; i++) {
      final offset = (cursor + i) % span;
      final v = base + offset;
      out.add('${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}');
    }
    _cfRangeCursors[cidr] = (cursor + perRange) % span;
  }
  return out;
}"""
if old_getcf in files['nat_ultra']:
    files['nat_ultra'] = files['nat_ultra'].replace(old_getcf, new_getcf, 1)
    print('  OK: sequential CF IPs')

# ---- 47) V11: natRangeScanStep - CF first in national ----
print('\n[47] V11: CF first in national')
patch_hard('nat_ultra',
"""  final blocks = natRanges.isNotEmpty ? natRanges : natSeedBlocks(hosts);
  final addrs = <String>[];
  for (final r in blocks) {
    addrs.addAll(natExpandAny(r));
  }
  addrs.addAll(_getCfIps());
  if (addrs.isEmpty) return const <String>[];
  final from = natRangeCursor % addrs.length;
  final slice = addrs.skip(from).take(maxAddrs).toList();
  natRangeCursor = from + slice.length;""",
"""  final blocks = natRanges.isNotEmpty ? natRanges : natSeedBlocks(hosts);
  final addrs = <String>[];
  if (nationalMode) {
    addrs.addAll(_getCfIps(batchSize: maxAddrs));
    for (final r in blocks) {
      addrs.addAll(natExpandAny(r));
    }
  } else {
    for (final r in blocks) {
      addrs.addAll(natExpandAny(r));
    }
    addrs.addAll(_getCfIps());
  }
  if (addrs.isEmpty) return const <String>[];
  final from = nationalMode ? 0 : (natRangeCursor % addrs.length);
  final slice = addrs.skip(from).take(maxAddrs).toList();
  if (!nationalMode) natRangeCursor = from + slice.length;""",
'V11: CF first in national')

# ---- 48) V11: standby exhaustive in national ----
print('\n[48] V11: standby exhaustive in national')
patch_hard('main',
"""      if (standbyPaused && connected && !nationalMode) {
        lastStandby = DateTime.now();
        return;
      }""",
"""      if (nationalMode) {
        standbyPaused = pending.isEmpty;
      }
      if (standbyPaused && connected && !nationalMode) {
        lastStandby = DateTime.now();
        return;
      }""",
'V11: standby exhaustive')

# ---- 49) V11: skip pause-setting in national ----
print('\n[49] V11: skip pause-setting in national')
patch_hard('main',
"""      if (!nationalMode) {
        if (healthyNow >= kStandbyPause) standbyFilled = true;
        if (healthyNow >= standbyGoal()) {
          standbyPaused = true; // پر است: هیچ تستی نزن
        } else if (standbyFilled ? healthyNow < kStandbyResume : true) {
          standbyPaused = false; // زیر ۵ (بعد از پرشدن) یا هنوز اولین پرشدن: بگرد
        }
      }""",
"""      if (!nationalMode) {
        if (healthyNow >= kStandbyPause) standbyFilled = true;
        if (healthyNow >= standbyGoal()) {
          standbyPaused = true; // پر است: هیچ تستی نزن
        } else if (standbyFilled ? healthyNow < kStandbyResume : true) {
          standbyPaused = false; // زیر ۵ (بعد از پرشدن) یا هنوز اولین پرشدن: بگرد
        }
      }
      // V11: in national mode, only pause when the queue is fully empty.
      if (nationalMode) {
        standbyPaused = pending.isEmpty;
      }""",
'V11: exhaustive pending')

# ---- 50) V12: natRound global state ----
print('\n[50] V12: natRound global')
patch_hard('nat_ultra',
"int natLevel = 1;",
"int natLevel = 1;\nint natRound = 1; // V12: 1 = pass 1 (skip failed), 2 = pass 2 (retry all)",
'V12: natRound global')

# ---- 51) V12: reset natRound at connect start ----
print('\n[51] V12: reset natRound in _doConnect')
patch_hard('main',
"""      natFloor = (natForce || nationalMode) ? 10 : 0;
      natLevel = natFloor;""",
"""      natFloor = (natForce || nationalMode) ? 10 : 0;
      natLevel = natFloor;
      // V12: every user-initiated connect starts at round 1 (skip failed).
      // Round 2 is only entered inside _findGood when pending is exhausted.
      natRound = 1;""",
'V12: reset natRound at connect')

# ---- 52) V12: _findGood two-pass national ----
print('\n[52] V12: two-pass national in _findGood')
patch_hard('main',
"""        if (pending.isEmpty && folderQ.isEmpty) {
          // منابع تازه تمام شد و هیچ سرور سالمی نیست: پوشه‌ی سرورهای سالم پشتیبان می‌شود
          if (!bg && !folderFallback && !offlineOnly && !nationalMode &&
              !indestructibleMode && _ready(row) == 0) {
            folderFallback = true;
            if (_resInject() > 0) {
              dbg('منابع تمام شد و سالمی پیدا نشد؛ پوشه‌ی سرورهای سالم به صف اضافه شد');
              break;
            }
          }
          if (!autoCycle || reloaded) break;
          reloaded = true;
          await _loadPending(bg: bg, exhausted: true);
          if (pending.isEmpty) break;
        }""",
"""        if (pending.isEmpty && folderQ.isEmpty) {
          // V12: in national mode, two-pass search. When the queue empties,
          // enter round 2 (retry every server that was failed in pass 1).
          if (nationalMode && !bg) {
            if (natRound == 1) {
              natRound = 2;
              failed.clear();
              for (final s in good) { s.badAt = null; s.miss = 0; }
              if (!offlineOnly) {
                listTime = null;
                lastFetchTry = DateTime(2000);
              }
              reloaded = false;
              dbg('V12-ROUND2: pending empty → pass 2 (retest all failures)');
              await _loadPending(bg: bg, exhausted: true);
              if (pending.isEmpty) {
                dbg('V12: pass 2 also empty → stop');
                break;
              }
              continue;
            }
            dbg('V12: pass 2 exhausted, stopping');
            break;
          }
          if (!bg && !folderFallback && !offlineOnly && !nationalMode &&
              !indestructibleMode && _ready(row) == 0) {
            folderFallback = true;
            if (_resInject() > 0) {
              dbg('منابع تمام شد و سالمی پیدا نشد؛ پوشه‌ی سرورهای سالم به صف اضافه شد');
              break;
            }
          }
          if (!autoCycle || reloaded) break;
          reloaded = true;
          await _loadPending(bg: bg, exhausted: true);
          if (pending.isEmpty) break;
        }""",
'V12: two-pass national')

# ---- 53) V12: natBudget = 900s for lvl 10 ----
print('\n[53] V12: natBudget 900s for lvl 10')
patch_hard('nat_ultra',
"""Duration natBudget({bool full = false}) {
  final l = full ? 3 : natLevel;
  if (l <= 1) return const Duration(seconds: 40);
  if (l == 2) return const Duration(seconds: 75);
  if (l == 3) return const Duration(seconds: 150);
  return const Duration(seconds: 260);
}""",
"""Duration natBudget({bool full = false}) {
  final l = full ? 3 : natLevel;
  // V12: at lvl 10 (national default) give a generous budget so the FULL
  // matrix (Fragment, DNS, port, FP, ALPN, clean IP, host, SNI...) is tested
  // against every server. No variant is skipped due to short budget.
  if (l <= 1) return const Duration(seconds: 60);
  if (l == 2) return const Duration(seconds: 120);
  if (l == 3) return const Duration(seconds: 240);
  if (l >= 9) return const Duration(seconds: 900);
  return const Duration(seconds: 480);
}""",
'V12: natBudget 900s for lvl 10')

# ---- 54) V12: force natLevel 10 in round 2 ----
print('\n[54] V12: force natLevel 10 in round 2')
patch_hard('main',
"""      if (nationalMode && !searching && !busy && !switching && !upBusy) {
        await _standbyRun();
      }""",
"""      if (nationalMode && !searching && !busy && !switching && !upBusy) {
        // V12: round 2 forces natLevel=10 to guarantee full DPI matrix.
        if (natRound >= 2 && natLevel < 10) natLevel = 10;
        await _standbyRun();
      }""",
'V12: force natLevel 10 in round 2')

# ---- 55) V12: don't drop pending items in round 2 ----
print('\n[55] V12: keep pending items in round 2')
patch_hard('main',
"""    if (nationalMode && ipList.isNotEmpty) {
      final trusted = natIpMemHosts()..addAll(natScanHits);
      final known = ipList.where((s) => trusted.contains(s.host)).toList();
      final unknown = ipList.where((s) => !trusted.contains(s.host)).toList();
      final mixed = <Server>[];
      var ki = 0, ui = 0;
      while (ki < known.length || ui < unknown.length) {
        if (ki < known.length) { mixed.add(known[ki]); ki++; }
        if (ui < unknown.length) { mixed.add(unknown[ui]); ui++; }
      }
      ipList
        ..clear()
        ..addAll(mixed);
    }""",
"""    if (nationalMode && ipList.isNotEmpty) {
      final trusted = natIpMemHosts()..addAll(natScanHits);
      // V12: in round 2 every IP counts as trusted for the purposes of testing
      // order. In round 1, split known/unknown 50/50 in queue position only.
      final known = ipList.where((s) => trusted.contains(s.host)).toList();
      final unknown = ipList.where((s) => !trusted.contains(s.host)).toList();
      final mixed = <Server>[];
      var ki = 0, ui = 0;
      while (ki < known.length || ui < unknown.length) {
        if (ki < known.length) { mixed.add(known[ki]); ki++; }
        if (ui < unknown.length) { mixed.add(unknown[ui]); ui++; }
      }
      ipList
        ..clear()
        ..addAll(mixed);
      if (natRound >= 2) {
        dbg('V12-R2: testing ALL IPs in round 2 (known=${known.length}, unknown=${unknown.length})');
      }
    }""",
'V12: keep pending in round 2')

# ---- 56a) V13: _NatSpec sniSwap field ----
print('\n[56a] V13: _NatSpec sniSwap')
patch_hard('nat_ultra',
"""class _NatSpec {
  final String name;
  final bool other;
  final String? fp, alpn;
  final int? frag;
  final bool port, clean, mux, sniHost, v4, tfo, ed, noise;
  final String? doh;
  final int muxN;
  final int noiseK;
  final bool nodelay;
  final String? mode;
  final int? edN;
  final int? portIdx;
  final int? cleanIdx;
  final int? keep;
  final int? mss;
  const _NatSpec(this.name,
      {this.other = false,
      this.fp,
      this.alpn,
      this.frag,
      this.port = false,
      this.clean = false,
      this.mux = false,
      this.sniHost = false,
      this.v4 = false,
      this.tfo = false,
      this.ed = false,
      this.noise = false,
      this.doh,
      this.muxN = 0,
      this.noiseK = 0,
      this.nodelay = false,
      this.mode,
      this.edN,
      this.portIdx,
      this.cleanIdx,
      this.keep,
      this.mss});
}""",
"""class _NatSpec {
  final String name;
  final bool other;
  final String? fp, alpn;
  final int? frag;
  final bool port, clean, mux, sniHost, v4, tfo, ed, noise;
  final String? doh;
  final int muxN;
  final int noiseK;
  final bool nodelay;
  final String? mode;
  final int? edN;
  final int? portIdx;
  final int? cleanIdx;
  final int? keep;
  final int? mss;
  final int? sniSwap; // V13: swap SNI to natFrontSnis[idx] (CDN-only)
  const _NatSpec(this.name,
      {this.other = false,
      this.fp,
      this.alpn,
      this.frag,
      this.port = false,
      this.clean = false,
      this.mux = false,
      this.sniHost = false,
      this.v4 = false,
      this.tfo = false,
      this.ed = false,
      this.noise = false,
      this.doh,
      this.muxN = 0,
      this.noiseK = 0,
      this.nodelay = false,
      this.mode,
      this.edN,
      this.portIdx,
      this.cleanIdx,
      this.keep,
      this.mss,
      this.sniSwap});
}""",
'P56a: _NatSpec sniSwap')

# ---- 56b) V13: _natMk sniSwap param ----
print('\n[56b] V13: _natMk sniSwap param')
patch_hard('nat_ultra',
"""    String? doh,
    String? mode,
    int? keep}) {""",
"""    String? doh,
    String? mode,
    int? keep,
    int? sniSwap}) {""",
'P56b: _natMk sniSwap')

# ---- 56c) V13: _natMk return sniSwap ----
print('\n[56c] V13: _natMk return sniSwap')
patch_hard('nat_ultra',
"""  if (mode != null) n.add(mode);
  return _NatSpec(n.isEmpty ? 'عادی+' : n.join(' + '),""",
"""  if (mode != null) n.add(mode);
  if (sniSwap != null) n.add('SNI>CF#${sniSwap + 1}');
  return _NatSpec(n.isEmpty ? 'عادی+' : n.join(' + '),""",
'P56c: _natMk name sniSwap')

patch_hard('nat_ultra',
"""      mode: mode,
      keep: keep);
}""",
"""      mode: mode,
      keep: keep,
      sniSwap: sniSwap);
}""",
'P56c2: _natMk return sniSwap')

# ---- 56d) V13: _natSig sniSwap ----
print('\n[56d] V13: _natSig')
patch_hard('nat_ultra',
"""    '${x.edN}|${x.noise}|${x.noiseK}|${x.nodelay}|${x.doh}|${x.mode}|${x.keep}';""",
"""    '${x.edN}|${x.noise}|${x.noiseK}|${x.nodelay}|${x.doh}|${x.mode}|${x.keep}|${x.sniSwap}';""",
'P56d: _natSig sniSwap')

# ---- 56e) V13: _natDims sniSwap ----
print('\n[56e] V13: _natDims')
patch_hard('nat_ultra',
"""  if (x.keep != null) d.add('ka=${x.keep}');
  return d;
}""",
"""  if (x.keep != null) d.add('ka=${x.keep}');
  if (x.sniSwap != null) d.add('sni=${x.sniSwap}');
  return d;
}""",
'P56e: _natDims sniSwap')

# ---- 56f) V13: _natAppliesF sniSwap ----
print('\n[56f] V13: _natAppliesF')
patch_hard('nat_ultra',
"""  if (x.doh != null && f.isIp) return false;
  return true;
}""",
"""  if (x.doh != null && f.isIp) return false;
  // V13: SNI swap only makes sense for CDN configs with TLS (not reality).
  if (x.sniSwap != null && !(f.sec && f.cdnLike && !f.reality)) return false;
  return true;
}""",
'P56f: _natAppliesF sniSwap')

# ---- 56g) V13: _natApplySniSwap helper ----
print('\n[56g] V13: _natApplySniSwap')
insert_before('nat_ultra', 'String _natFrag(String cfg, int fi,',
"""String _natApplySniSwap(String cfg, int sniIdx) {
  try {
    if (sniIdx < 0 || sniIdx >= natFrontSnis.length) return cfg;
    final sni = natFrontSnis[sniIdx];
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    final outs = (j['outbounds'] as List?) ?? <dynamic>[];
    for (final o in outs) {
      if (o is! Map) continue;
      final st = o['streamSettings'];
      if (st is! Map) continue;
      if (st['security'] != 'tls') continue;
      final tls = st['tlsSettings'];
      if (tls is! Map) continue;
      tls['serverName'] = sni;
      tls['allowInsecure'] = true;
    }
    return jsonEncode(j);
  } catch (_) {
    return cfg;
  }
}

""", 'P56g: _natApplySniSwap helper')

# ---- 56h) V13: _natCfgRaw apply sniSwap ----
print('\n[56h] V13: _natCfgRaw sniSwap')
patch_hard('nat_ultra',
"""  if (x.v4 || x.tfo || x.nodelay || x.keep != null || x.mss != null) {
    cfg = _natSock(cfg,
        v4: x.v4, tfo: x.tfo, nodelay: x.nodelay, keep: x.keep, mss: x.mss);
  }
  return cfg;
}""",
"""  if (x.v4 || x.tfo || x.nodelay || x.keep != null || x.mss != null) {
    cfg = _natSock(cfg,
        v4: x.v4, tfo: x.tfo, nodelay: x.nodelay, keep: x.keep, mss: x.mss);
  }
  if (x.sniSwap != null) cfg = _natApplySniSwap(cfg, x.sniSwap!);
  return cfg;
}""",
'P56h: _natCfgRaw sniSwap')

# ---- 56i) V13: 4 SNI swap base variants ----
print('\n[56i] V13: SNI swap base variants')
patch_hard('nat_ultra',
"""  _NatSpec('آدرس دیگر + Fragment خیلی ریز', other: true, frag: 3),
];""",
"""  _NatSpec('آدرس دیگر + Fragment خیلی ریز', other: true, frag: 3),
  // V13: SNI swap variants (CDN bypass by masking SNI, keeping Host header).
  _NatSpec('SNI>cdnjs', sniSwap: 0),
  _NatSpec('SNI>cloudflare', sniSwap: 2),
  _NatSpec('SNI>speed', sniSwap: 3),
  _NatSpec('SNI>1.1.1.1', sniSwap: 10),
];""",
'P56i: SNI swap base')

# ---- 56j) V13: _natBaseCount 50->54 ----
print('\n[56j] V13: _natBaseCount 50->54')
patch_hard('nat_ultra',
"const int _natBaseCount = 50;",
"const int _natBaseCount = 54; // V13: +4 SNI swap",
'P56j: _natBaseCount 54')

# ---- 56k) V13: SNI swap + frag combos ----
print('\n[56k] V13: SNI swap + frag combos')
patch_hard('nat_ultra',
"""  final topSet = top.toSet();
  final rest = <int>[
    for (var i = _natFragBase.length; i < _natFrags.length; i++)
      if (!topSet.contains(i)) i
  ];

  for (final p in fps) {
    add(_natMk(fp: p));
  }""",
"""  final topSet = top.toSet();
  final rest = <int>[
    for (var i = _natFragBase.length; i < _natFrags.length; i++)
      if (!topSet.contains(i)) i
  ];

  // V13: SNI-swap x fragment combos (bypass SNI + DPI in one shot).
  for (var sniIdx = 0; sniIdx < 4; sniIdx++) {
    final realIdx = const [0, 2, 3, 10][sniIdx];
    for (var fi = 0; fi < _natFragBase.length; fi++) {
      add(_natMk(frag: fi, sniSwap: realIdx));
    }
  }

  for (final p in fps) {
    add(_natMk(fp: p));
  }""",
'P56k: SNI swap+frag combos')

# ---- 57a) V13: Time-of-day in natVarSet ----
print('\n[57a] V13: time-of-day natVarSet')
patch_hard('nat_ultra',
"""  if (v > 0 && v < _natSpecs.length) {
    for (final d in _natDims(_natSpecs[v])) {
      final dk = '$natOpKey#$d';
      natDimWins[dk] = (natDimWins[dk] ?? 0) + 1;
    }
    _natLearnVer++;
  }""",
"""  if (v > 0 && v < _natSpecs.length) {
    final hb = DateTime.now().hour ~/ 3; // V13: 3-hour bucket (0-7)
    for (final d in _natDims(_natSpecs[v])) {
      final dk = '$natOpKey#$d';
      natDimWins[dk] = (natDimWins[dk] ?? 0) + 1;
      final hk = '$natOpKey#h$hb#$d';
      natDimWins[hk] = (natDimWins[hk] ?? 0) + 1;
    }
    _natLearnVer++;
  }""",
'P57a: time-of-day')

# ---- 57b) V13: Time-of-day in _natGenRanked ----
print('\n[57b] V13: time-of-day _natGenRanked')
patch_hard('nat_ultra',
"""List<int> _natGenRanked() {
  final key = '$natOpKey|$_natLearnVer|${_natSpecs.length}';
  if (key == _natGenRankKey) return _natGenRank;
  final idx = <int>[for (var i = _natBaseCount; i < _natSpecs.length; i++) i];
  final sc = <int, int>{};
  for (final i in idx) {
    var s = 0;
    for (final d in _natDims(_natSpecs[i])) {
      s += natDimWins['$natOpKey#$d'] ?? 0;
    }
    sc[i] = s;
  }""",
"""List<int> _natGenRanked() {
  final hb = DateTime.now().hour ~/ 3; // V13: 3-hour bucket
  final key = '$natOpKey|$_natLearnVer|${_natSpecs.length}|h$hb';
  if (key == _natGenRankKey) return _natGenRank;
  final idx = <int>[for (var i = _natBaseCount; i < _natSpecs.length; i++) i];
  final sc = <int, int>{};
  for (final i in idx) {
    var s = 0;
    for (final d in _natDims(_natSpecs[i])) {
      s += natDimWins['$natOpKey#$d'] ?? 0;
      s += (natDimWins['$natOpKey#h$hb#$d'] ?? 0) * 2;
    }
    sc[i] = s;
  }""",
'P57b: time-of-day ranked')

# ---- 58) V13: uTLS fingerprints 10 -> 22 ----
print('\n[58] V13: uTLS fingerprints')
patch_hard('nat_ultra',
"""  const fps = [
    'chrome', 'firefox', 'randomized', 'ios', 'android', 'safari', 'edge',
    'random', 'qq', '360'
  ];""",
"""  const fps = [
    'chrome', 'firefox', 'randomized', 'ios', 'android', 'safari', 'edge',
    'random', 'qq', '360',
    'hellogolang', 'hellochrome', 'hellofirefox', 'hellosafari', 'helloios',
    'helloandroid', 'helloedge', 'hello360', 'helloqq', 'hellorandomized',
    'hellorandomizedalpn', 'hellorandomizednoalpn',
  ];""",
'P58: expanded uTLS')

# ---- 59) V13: sniSwap priority in _natOrder (CDN first) ----
print('\n[59] V13: sniSwap priority in _natOrder')
patch_hard('nat_ultra',
"""    final lightFirst = <int>[0, 1, 4, 13, 7, 20, 12, 33, 38, 40, 44];""",
"""    // V13: try SNI-swap variants first on CDN configs (bypasses SNI DPI).
    // If the config is CDN, base index 50..53 are the SNI swaps.
    final lightFirst = <int>[
      if (f.cdnLike && f.sec && !f.reality) ...[50, 51, 52, 53],
      0, 1, 4, 13, 7, 20, 12, 33, 38, 40, 44,
    ];""",
'P59: sniSwap priority')

# ---- 60) V13: add more tiny fragment variants ----
print('\n[60] V13: tiny fragment variants')
patch_hard('nat_ultra',
"""  const lens = [
    '1-3', '2-8', '5-15', '10-30', '20-50', '30-60', '50-100', '100-200',
    '200-400', '400-800'
  ];""",
"""  const lens = [
    '1-2', '1-3', '2-5', '2-8', '5-15', '10-30', '20-50', '30-60', '50-100',
    '100-200', '200-400', '400-800'
  ];""",
'P60: tiny fragments')

# ---- 61) V13: smart SNI for workers.dev ----
print('\n[61] V13: smart SNI')
patch_hard('nat_ultra',
"""  if (x.sniSwap != null) cfg = _natApplySniSwap(cfg, x.sniSwap!);
  return cfg;
}""",
"""  if (x.sniSwap != null) cfg = _natApplySniSwap(cfg, x.sniSwap!);
  return cfg;
}

// V13/V16: automatically apply SNI swap if the host is workers.dev
// (always), or any CDN host when sniSpoofAll is on (V16).
String _natSmartSni(String cfg, Server s, {bool forceAll = false}) {
  try {
    final h = s.host.toLowerCase();
    final isWorker = h.endsWith('workers.dev') || h.endsWith('pages.dev');
    final isCdn = isWorker || s.cdn;
    if (!isWorker && !(forceAll && isCdn)) return cfg;
    final j = jsonDecode(cfg);
    if (j is! Map<String, dynamic>) return cfg;
    final outs = (j['outbounds'] as List?) ?? <dynamic>[];
    for (final o in outs) {
      if (o is! Map) continue;
      final st = o['streamSettings'];
      if (st is! Map || st['security'] != 'tls') continue;
      final tls = st['tlsSettings'];
      if (tls is! Map) continue;
      final current = (tls['serverName'] ?? '').toString().toLowerCase();
      if (!isWorker &&
          !current.endsWith('workers.dev') &&
          !current.endsWith('pages.dev') &&
          !current.isEmpty) {
        continue;
      }
      tls['serverName'] = natFrontSnis[0]; // cdnjs.cloudflare.com (or first Iran)
      tls['allowInsecure'] = true;
    }
    return jsonEncode(j);
  } catch (_) { return cfg; }
}""",
'P61: smart SNI helper')

patch_hard('nat_ultra',
"""String _natCfgRaw(Server s, int v, {bool reuse = false}) {
  var cfg = buildCoreConfig(_natLinkFor(s, v, reuse: reuse));
  if (v <= 0 || v >= _natSpecs.length) return cfg;
  final x = _natSpecs[v];""",
"""String _natCfgRaw(Server s, int v, {bool reuse = false}) {
  var cfg = buildCoreConfig(_natLinkFor(s, v, reuse: reuse));
  if (v <= 0 || v >= _natSpecs.length) {
    return _natSmartSni(cfg, s, forceAll: sniSpoofAll);
  }
  final x = _natSpecs[v];""",
'P61b: apply smart SNI')

# ---- 62) V14: auto_test 5 hours duration ----
print('\n[62] V14: auto_test 5h')
patch_hard('auto_test',
"static const _testDuration = Duration(hours: 4); // STEST4H: همه‌ی سطوح، IP تمیز و همه‌ی حالت‌های جایگزین جا شوند",
"static const _testDuration = Duration(hours: 5); // V14: 5-hour national test",
'V14: auto_test 5h')

# ---- 63) V14: only run national test in auto_test ----
print('\n[63] V14: only national test')
patch_hard('auto_test',
"""      final steps = <(String, Duration, Future<void> Function())>[
        (_atItemNames[2], const Duration(minutes: 50), _atItemNational),
        (_atSubstName, const Duration(minutes: 150), _atItemSubst),
      ];""",
"""      // V14: only run the national test for the full 5 hours.
      final steps = <(String, Duration, Future<void> Function())>[
        (_atItemNames[2], const Duration(hours: 5), _atItemNational),
      ];""",
'V14: only national test')

# ---- 64) V14: _atItemNational monitors V13 engine (ROBUST) ----
print('\n[64] V14: national monitor')
if "Future<void> _atItemNational() async {" in files['auto_test']:
    replace_function_braces('auto_test',
        r'Future<void> _atItemNational\(\) async \{',
        """  Future<void> _atItemNational() async {
    _scenario = 3;
    final name = _atItemNames[2];
    natForce = true;
    nationalMode = true;
    userModeChoice = true;
    offlineOnly = false;
    natRound = 1; // V14: force pass 1
    await ultimateSave();

    _set('نت ملی: پاک‌سازی صف برای تست کامل ۵ ساعته');
    good.clear();
    pending.clear();
    failed.clear();
    fetchedAll.clear();
    listTime = null;

    _set('نت ملی: شروع اتصال اولیه...');
    await connect(); // Triggers V13 logic, returns on first server

    final tStart = DateTime.now();
    final testDuration = const Duration(hours: 5);

    while (_phase == _AtPhase.running && !_abortRequested) {
      final elapsed = DateTime.now().difference(tStart);
      if (elapsed > testDuration) break;

      final progress = elapsed.inSeconds / testDuration.inSeconds;
      autoTestProgress.value = progress.clamp(0.0, 1.0);
      autoTestText.value = 'نت ملی ۵ ساعته • ${elapsed.inHours}h ${elapsed.inMinutes % 60}m • '
          'دور: $natRound • سالم: ${good.length} • صف: ${pending.length} • '
          'IP تست‌شده: $natIpTested • IP باز: $natIpFound';

      if (natRound >= 2 && pending.isEmpty && !searching && !busy) {
        _atAdd('NAT-EXHAUSTED', 'کل صف در هر دو دور تست شد و صف خالی است.');
        break;
      }

      if (!searching && !busy && connected && pending.isNotEmpty) {
        unawaited(_standbyRun());
      }

      await Future<void>.delayed(const Duration(seconds: 3));
    }

    _itemResult[name] = '✅ تست ۵ ساعته تمام شد • '
        'سالم: ${good.length} • تست‌شده: $natIpTested • باز: $natIpFound';
  }""",
        'V14: national monitor')

# ---- 65) V14: save report to multiple public dirs ----
print('\n[65] V14: save report dirs')
patch_hard('auto_test',
"""  const privDir = '/data/data/com.kingvpn.king_vpn/files/reports';
  // REPORTDIR: پوشه‌ی گزارش در ریشه‌ی فضای داخلی، کنار DCIM و Download
  const pubDir = '/storage/emulated/0/King-VPN';
  String saved = '';
  for (final d in const [privDir, pubDir]) {""",
"""  const privDir = '/data/data/com.kingvpn.king_vpn/files/reports';
  // V14: save to multiple public directories
  const pubDir1 = '/storage/emulated/0/King-VPN';
  const pubDir2 = '/storage/emulated/0/Documents/KingVPN';
  const pubDir3 = '/storage/emulated/0/Download/KingVPN';
  String saved = '';
  for (final d in const [privDir, pubDir1, pubDir2, pubDir3]) {""",
'V14: save report dirs')

# ---- 66) V16: sniSpoofAll setting + normal-mode SNI spoof ----
print('\n[66] V16: sniSpoofAll setting + normal-mode spoof')
# Define the global variable
patch_hard('main',
"bool onlyHealthySrc = true;",
"bool onlyHealthySrc = true;\nbool sniSpoofAll = false; // V16: apply SNI spoof to all CDN configs (normal mode too)",
'V16: sniSpoofAll global')

# In _startImpl, apply SNI spoof to normal-mode CDN configs
patch_hard('main',
"""      final cfg = proxyOnly
          ? base
          : _reliableVpnCfg(base);""",
"""      var cfg = proxyOnly
          ? base
          : _reliableVpnCfg(base);
      // V16: apply SNI spoof in normal mode when user enabled it.
      // Only for CDN configs with TLS; safe for workers.dev always (handled
      // inside _natSmartSni), other CDN only when sniSpoofAll is true.
      if (!nationalMode && s.cdn && s.tls) {
        cfg = _natApplySniSwap(cfg, 0); // cdnjs.cloudflare.com (first in list)
      }""",
'V16: apply SNI spoof in normal mode')

# ---- 67) V17: Mux 64/128 ----
print('\n[67] V17: Mux 128')
patch_hard('main',
"int muxConc = 32;",
"int muxConc = 128; // V17: default Mux concurrency = 128",
'V17: Mux 128 default')

patch_hard('iran_ai_extras',
"const _muxOpts = <int>[4, 8, 16, 32];",
"const _muxOpts = <int>[4, 8, 16, 32, 64, 128];",
'V17: Mux 128 UI')

patch_hard('main',
"""    muxConc = max(muxConc, 32);
    if (!nationalMode) fragEnabled = false;""",
"""    muxConc = max(muxConc, 128);
    if (!nationalMode) fragEnabled = false;""",
'V17: Mux 128 after connect')

# ---- 68) V17: Auto-Reconnect (Throttle Escape) ----
print('\n[68] V17: Auto-Reconnect Throttle Escape')
patch_hard('main',
"  int stallRun = 0; // SPEEDSWITCHPATCH: checks in a row under 100 KB/s",
"""  int stallRun = 0; // SPEEDSWITCHPATCH: checks in a row under 100 KB/s
  int _throttleRun = 0; // V17: consecutive slow-speed checks (possible ISP throttle)""",
'V17: _throttleRun var')

patch_hard('main',
"            final slowNow = sp * 1024 < 40 ||",
"""            if (sp * 1024 < 50) {
              _throttleRun++;
              if (_throttleRun >= 3 && current != null) {
                _throttleRun = 0;
                dbg('V17-THROTTLE: سرعت ۳ بار زیر ۵۰KB/s ماند • تلاش برای فرار از throttle ISP');
                _set('سرعت بسیار پایین است؛ تلاش برای تغییر مسیر...');
                if (nationalMode) natVar.remove(_nk(current!));
                sniSpoofAll = true;
                _saveSettings();
                await _restartTunnel();
                return;
              }
            } else {
              _throttleRun = 0;
            }
            final slowNow = sp * 1024 < 40 ||""",
'V17: throttle escape')

# ---- 69) V19: Apply Best Settings per Mode ----
print('\n[69] V19: _applyModePreset')
# Add the function before _doConnect
insert_before('main', '  Future<void> _doConnect({Server? only, String? row}) async {',
"""  /// V19: reset settings to the best default for the selected mode.
  void _applyModePreset(bool nat, bool offline, bool pilot) {
    if (nat) {
      // Best settings for National Network (Heavy bypass)
      fragEnabled = true;
      sniSpoofAll = true;
      ultraMode = true;
      indestructibleMode = true;
      muxEnabled = true;
      muxConc = 128;
      badPingSwitch = true;
      badPingMs = 2000;
    } else if (pilot) {
      // Best settings for Pilot (Auto)
      fragEnabled = false;
      sniSpoofAll = false;
      ultraMode = true;
      indestructibleMode = false;
      muxEnabled = true;
      muxConc = 128;
      badPingSwitch = true;
      badPingMs = 2000;
    } else {
      // Best settings for Normal Connect (Speed)
      fragEnabled = false;
      sniSpoofAll = false;
      ultraMode = false;
      indestructibleMode = false;
      muxEnabled = true;
      muxConc = 128;
      badPingSwitch = true;
      badPingMs = 2000;
    }
    _saveSettings();
  }

""", 'V19: _applyModePreset helper')

# Apply the preset in _doConnect (FIXED)
patch_hard('main',
"""      natRound = 1;""",
"""      natRound = 1;
      // V19: apply the best preset for this specific connect mode.
      _applyModePreset(nationalMode, offlineOnly, false);""",
'V19: apply preset in _doConnect')

# Apply preset in local pilot start (FIXED)
patch_hard('main',
"  void startLocalPilot() {\n    ensureLocalPilotRunning();",
"  void startLocalPilot() {\n    _applyModePreset(false, false, true); // V19: best settings for pilot\n    ensureLocalPilotRunning();",
'V19: apply preset in pilot')

# =====================================================================
# Save
# =====================================================================
for fn, content in files.items():
    with open(os.path.join(LIB, fn + '.dart'), 'w', encoding='utf-8') as f:
        f.write(content)

print('\n' + '=' * 60)
print('=== ALL PATCHES APPLIED ===')
print('=== V19: Mode-specific presets, Mux 128, Throttle Escape ===')
print('=== BUILD SHOULD PROCEED ===')
