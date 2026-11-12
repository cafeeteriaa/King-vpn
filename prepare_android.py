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

# ---- 4) HOT PATH (V9: app-private) ----
print('\n[4] hotPath V9 app-private')
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
"          npvParse = j['npv'] as bool? ?? npvParse;\n          relayServerUrl = j['relay_url'] as String? ?? '';",
'load relay_url')
patch_hard('main',
"            'npv': npvParse,",
"            'npv': npvParse,\n            'relay_url': relayServerUrl,",
'save relay_url')

# ---- 8) UiTools ----
print('\n[8] UiTools')
patch_hard('main',
"UiTools(items: [",
"UiTools(items: [\n            UiTool(Icons.swap_horiz, 'سرور واسط (نت ملی)', () => showRelayDialog(context)),\n            UiTool(Icons.router, 'بازه‌های IP نت ملی', () => _natRangesDialog(context)),",
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
        indestructibleMode = true;
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
        secureDns = true;
        cleanIpMode = true;
        npvParse = true;
        offlineOnly = false;
        dataSaver = false;
        autoNetReconnect = true;
        preflightOn = true;
        await saveNumPrefs();
        await _saveSettings();
        dbg('V8-FRESH: default settings applied');
      }
      await loadGeminiPrefs(p);""",
'V8-FRESH')

# ---- 14) resetAllToDefaults ----
print('\n[14] resetAllToDefaults')
patch_hard('main',
"""  void resetAllToDefaults() {
    resetNumbers();
    fwUserSet = false; // FWUSER: برگشت به پیش‌فرض ۳
    autoTune = false;""",
"""  void resetAllToDefaults() {
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
    });
    resetNumbers();
    badPingMs = 2000;
    fwUserSet = false; // FWUSER: برگشت به پیش‌فرض ۳
    autoTune = false;""",
'resetAllToDefaults set flags')

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

# ---- 18) target 3 servers ----
print('\n[18] target 3')
patch_hard('main', "const int kStandbyPause = 5;", "const int kStandbyPause = 3;", 'kStandbyPause')
patch_hard('main', "const int kStandbyResume = 5;", "const int kStandbyResume = 3;", 'kStandbyResume')
patch_hard('main', "const int kFgSearchTarget = 5;", "const int kFgSearchTarget = 3;", 'kFgSearchTarget')

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
        else:
            print('  WARN: end URL not found')
    else:
        print('  SKIP: marker not found')
else:
    print('  SKIP: already removed')

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
  const fps = ['chrome', 'firefox', 'randomized', 'ios', 'android', 'safari', 'edge', 'random', 'qq', '360'];
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
    _natSpecs.add(_natMk(
      fp: fp, alpn: alpn, frag: frag, port: port, portIdx: portIdx,
      clean: clean, cleanIdx: cleanIdx, v4: v4, tfo: tfo, keep: keep, doh: doh,
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
"""List<String>? _cfIpCache;
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
    final l = await NetworkInterface.list(includeLoopback: false);
    tunNames = l.map((i) => i.name).join(',');
    if (l.isEmpty) return null;
    // V9: only real tunnel-like names count. ccmni/rmnet/seth are CELLULAR
    // interfaces, not VPN. Treating them as tunnel gave false positives.
    final hasTunnel = l.any((i) {
      final n = i.name.toLowerCase();
      return n.startsWith('tun') ||
          n.startsWith('ppp') ||
          n.startsWith('vpn') ||
          n.startsWith('ipsec') ||
          n.startsWith('tap') ||
          n.startsWith('utun') ||
          n.contains('xray') ||
          n.contains('v2ray');
    });
    if (hasTunnel) return true;
    // V9: list() can be flaky during transient states. Retry once.
    await Future.delayed(const Duration(milliseconds: 400));
    try {
      final l2 = await NetworkInterface.list(includeLoopback: false);
      final ok2 = l2.any((i) {
        final n = i.name.toLowerCase();
        return n.startsWith('tun') ||
            n.startsWith('ppp') ||
            n.startsWith('vpn') ||
            n.startsWith('utun');
      });
      if (ok2) return true;
    } catch (_) {}
    return false;
  } catch (_swE) {
    _swl('tunUp#1', _swE);
    return null;
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

# ---- 33) V9-NATGOLD: gold IPs injection on round 0 ----
print('\n[33] V9-NATGOLD gold IPs round 0')
patch_hard('main',
"""      if (round == 0 && nationalMode) {
        // NATFIRSTFAST: دور اول فقط جستجوی سریع است؛ اولین سرور سالمی که پیدا شد وصل می‌شود.
        // اسکن‌های سنگین IP/دامنه (چند دقیقه) در دورهای بعد و در پس‌زمینه‌ی اتصال اجرا می‌شوند.
        if (_pickList().isEmpty) await _natQuickStart();
      }""",
"""      if (round == 0 && nationalMode) {
        // NATFIRSTFAST + V9-NATGOLD: quick start; then inject cached gold IPs
        // BEFORE any IP scan (saves minutes on fresh install after setup).
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

# ---- 34) V9-SNI: expand natFrontSnis ----
print('\n[34] V9: expand natFrontSnis')
patch_hard('nip_scan',
"""const natFrontSnis = <String>[
  'cdnjs.cloudflare.com',
  'www.cloudflare.com',
  'cloudflare.com',
  'speed.cloudflare.com',
];""",
"""const natFrontSnis = <String>[
  // V9: expanded SNI rotation. All are CF-hosted, so handshaking with any
  // against a CF edge IP succeeds. Rotating SNIs defeats SNI-specific DPI.
  'cdnjs.cloudflare.com',
  'www.cloudflare.com',
  'cloudflare.com',
  'speed.cloudflare.com',
  'workers.dev',
  'dash.cloudflare.com',
  'developers.cloudflare.com',
  'community.cloudflare.com',
  'support.cloudflare.com',
  'blog.cloudflare.com',
  'one.one.one.one',
  '1.1.1.1',
  'cloudflare-dns.com',
  'cloudflareaccess.com',
  'static.cloudflareinsights.com',
  'challenge-platform.cloudflare.com',
];""",
'V9: expanded natFrontSnis')

# ---- 35) V9: badPingMs = 2000 everywhere + autoTune off ----
print('\n[35] V9: badPingMs = 2000 + autoTune off')
patch_hard('main',
"int badPingMs = 1700; // پینگ بد از ۱۷۰۰ms = تعویض",
"int badPingMs = 2000; // V9: default 2000",
'badPingMs global 2000')

patch_hard('iran_ai_extras',
"  NumOpt('badPingMs', 'پینگ بد از', 70, 7000, 1700, 7000, false,\n      () => badPingMs, (v) => badPingMs = v),",
"  NumOpt('badPingMs', 'پینگ بد از', 70, 7000, 2000, 7000, false,\n      () => badPingMs, (v) => badPingMs = v),",
'numOpts badPingMs 2000')

patch_hard('main',
"""      // BADPING1700 v1: «پینگ بد از» = ۱۷۰۰ms (یک‌بار برای نصب‌های قبلی)
      if (p.getBool('badping1700_v1') != true) {
        badPingMs = 1700;
        await p.setBool('badping1700_v1', true);
        await saveNumPrefs();
        await _saveSettings();
      }""",
"""      // V9: badPingMs = 2000 (once for older installs)
      if (p.getBool('badping2000_v1') != true) {
        badPingMs = 2000;
        await p.setBool('badping2000_v1', true);
        await saveNumPrefs();
        await _saveSettings();
      }""",
'badping migration 2000')

# Update all tuned settings 'bp' and 'badPingMs' to 2000
for fn in files:
    txt = files[fn]
    txt = txt.replace("'bp': 2500,", "'bp': 2000,")
    txt = txt.replace("'badPingMs': 2500,", "'badPingMs': 2000,")
    files[fn] = txt
print('  OK: tuned settings badPingMs -> 2000')

# =====================================================================
# Save
# =====================================================================
for fn, content in files.items():
    with open(os.path.join(LIB, fn + '.dart'), 'w', encoding='utf-8') as f:
        f.write(content)

print('\n' + '=' * 60)
print('=== ALL 35 PATCHES APPLIED ===')
print('=== AGP 9.4.0 + Gradle 9.6.0 ===')
print('=== BUILD SHOULD PROCEED ===')
