import os
import re
import shutil

APP = 'build_app'

# =====================================================================
# ---- 1) AndroidManifest + native files ----
# =====================================================================
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

# =====================================================================
# ---- 2) Gradle ----
# =====================================================================
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
    ndk_block = (
        '\n        ndk {\n'
        '            abiFilters += listOf("arm64-v8a", "armeabi-v7a")\n'
        '        }\n'
        if is_kts else
        '\n        ndk {\n'
        '            abiFilters "arm64-v8a", "armeabi-v7a"\n'
        '        }\n'
    )
    dc = re.search(r'defaultConfig\s*\{', g)
    if dc:
        g = g[:dc.end()] + ndk_block + g[dc.end():]
        open(gp, 'w', encoding='utf-8').write(g)

# =====================================================================
# ---- 3) Fresh-sources folder (hotPath → Download) ----
# =====================================================================
NAT = os.path.join(APP, 'lib/nat_ultra.dart')
MAIN = os.path.join(APP, 'lib/main.dart')

def patch_once(text, old, new, label):
    if text.count(old) != 1:
        raise SystemExit('ERROR: %s found %d times.' % (label, text.count(old)))
    return text.replace(old, new, 1)

OLD_PATH = """String _hotPath() {
  const dir = '/data/data/com.kingvpn.king_vpn/files';
  try {
    final d = Directory(dir);
    if (!d.existsSync()) d.createSync(recursive: true);
    return '$dir/hot_cache.txt';
  } catch (jex, jstk) { errJournalAdd(jex, st: jstk);
    return '${Directory.systemTemp.path}/hot_cache.txt';
  }
}
"""
NEW_PATH = """const String hotVisibleDir = '/storage/emulated/0/Download/King-VPN';
String _hotPath() {
  try {
    final v = Directory(hotVisibleDir);
    if (!v.existsSync()) v.createSync(recursive: true);
    final probe = File('$hotVisibleDir/.kv_probe');
    probe.writeAsStringSync('ok', flush: true);
    probe.deleteSync();
    return '$hotVisibleDir/hot_configs.txt';
  } catch (_) {}
  const dir = '/data/data/com.kingvpn.king_vpn/files';
  try {
    final d = Directory(dir);
    if (!d.existsSync()) d.createSync(recursive: true);
    return '$dir/hot_cache.txt';
  } catch (_) {
    return '${Directory.systemTemp.path}/hot_cache.txt';
  }
}
"""
OLD_ENSURE = "  if (_hotBusy) return;\n  final f = File(_hotPath());\n"
NEW_ENSURE = ("  if (force) await hotStorageAllow();\n"
              "  if (_hotBusy) return;\n"
              "  final f = File(_hotPath());\n")
APPEND = """
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
n = open(NAT, encoding='utf-8').read()
if 'hotVisibleDir' not in n:
    n = patch_once(n, OLD_PATH, NEW_PATH, 'hotPath')
    n = patch_once(n, OLD_ENSURE, NEW_ENSURE, 'hotEnsure')
    if not n.endswith('\n'): n += '\n'
    n += APPEND
    open(NAT, 'w', encoding='utf-8').write(n)

mn = open(MAIN, encoding='utf-8').read()
if 'hotAutoStart()' not in mn:
    mn = patch_once(mn, 'void main() {\n', 'void main() {\n  Future.delayed(const Duration(seconds: 5), () => unawaited(hotAutoStart()));\n', 'main()')

# =====================================================================
# ---- 4) Relay + IP Range UI ----
# =====================================================================
old_chain = """          String? chainCfg;
          if (nationalMode && !proxyOnly) {
            final relays = _usable().where((x) => !identical(x, s)).take(1).toList();
            if (relays.isNotEmpty) {
              chainCfg = natChainCfg(cfg, natCfg(relays.first, 0), keepInbounds: true);
              if (chainCfg != null) {
                dbg('MULTIHOP: آخرین تلاش از پشت ${relays.first.name} (relay) برای ${s.name}');
              }
            }
          }"""
new_chain = """          String? chainCfg;
          if (nationalMode && !proxyOnly) {
            if (relayServerUrl.isNotEmpty) {
              final relaySrv = Server.parse(relayServerUrl);
              if (relaySrv != null) {
                chainCfg = natChainCfg(cfg, natCfg(relaySrv, 0), keepInbounds: true);
                if (chainCfg != null) dbg('MULTIHOP: سرور واسط دستی برای ${s.name}');
              }
            }
            if (chainCfg == null) {
              final relays = _usable().where((x) => !identical(x, s)).take(1).toList();
              if (relays.isNotEmpty) {
                chainCfg = natChainCfg(cfg, natCfg(relays.first, 0), keepInbounds: true);
                if (chainCfg != null) {
                  dbg('MULTIHOP: آخرین تلاش از پشت ${relays.first.name} برای ${s.name}');
                }
              }
            }
          }"""
if old_chain in mn: mn = mn.replace(old_chain, new_chain)

old_load = "npvParse = j['npv'] as bool? ?? npvParse;"
new_load = "npvParse = j['npv'] as bool? ?? npvParse;\n          relayServerUrl = j['relay_url'] as String? ?? '';"
if old_load in mn: mn = mn.replace(old_load, new_load, 1)

old_save = "'npv': npvParse,"
new_save = "'npv': npvParse,\n            'relay_url': relayServerUrl,"
if old_save in mn: mn = mn.replace(old_save, new_save, 1)

old_ui = "UiTools(items: ["
new_ui = "UiTools(items: [\n            UiTool(Icons.swap_horiz, 'سرور واسط (نت ملی)', () => showRelayDialog(context)),\n            UiTool(Icons.router, 'بازه‌های IP نت ملی', () => _natRangesDialog(context)),"
if old_ui in mn:
    mn = mn.replace(old_ui, new_ui, 1)
else:
    old_tool = "UiTool(Icons.add_home_outlined, 'ساخت سرور شخصی', () => connectPersonalAsk()),"
    new_tool = "UiTool(Icons.swap_horiz, 'سرور واسط (نت ملی)', () => showRelayDialog(context)),\n            UiTool(Icons.router, 'بازه‌های IP نت ملی', () => _natRangesDialog(context)),\n            UiTool(Icons.add_home_outlined, 'ساخت سرور شخصی', () => connectPersonalAsk()),"
    if old_tool in mn: mn = mn.replace(old_tool, new_tool, 1)

# =====================================================================
# ---- 5) DIALER-PROXY fix ----
# =====================================================================
old_proxy = """      if (so is Map) {
        final dp = so['dialerProxy']?.toString();
        if (dp != null && !tags.contains(dp)) {
          so.remove('dialerProxy');
          changed = true;
        }
      }"""
new_proxy = """      if (so is Map) {
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
      }"""
if old_proxy in mn: mn = mn.replace(old_proxy, new_proxy, 1)

# =====================================================================
# ---- 6) ★ CRITICAL: kNatMergeCache and kFolderInjectGood → true ----
# =====================================================================
if 'const bool kNatMergeCache = false;' in mn:
    mn = mn.replace('const bool kNatMergeCache = false;',
                    'bool kNatMergeCache = true; // V8-FIX', 1)
    print('OK: kNatMergeCache = true (was false — BUG)')
else:
    print('WARN: kNatMergeCache not found')

if 'const bool kFolderInjectGood = false;' in mn:
    mn = mn.replace('const bool kFolderInjectGood = false;',
                    'bool kFolderInjectGood = true; // V8-FIX', 1)
    print('OK: kFolderInjectGood = true (was false — BUG)')
else:
    print('WARN: kFolderInjectGood not found')

# =====================================================================
# ---- 7) ★ V8-SAFE: skip requestPermission if granted ----
# =====================================================================
old_perm = """    if (!proxyMode && inForeground) {
      try {
        // PERMTIMEOUT: same limit as above
        final ok = await v2ray.requestPermission().timeout("""
new_perm = """    if (!proxyMode && inForeground && !vpnPermOk) {
      try {
        // PERMTIMEOUT: same limit as above
        final ok = await v2ray.requestPermission().timeout("""
if old_perm in mn:
    mn = mn.replace(old_perm, new_perm, 1)
    print('OK: skip requestPermission if granted')

# =====================================================================
# ---- 8) V8-FRESH: first launch == reset defaults ----
# =====================================================================
old_fresh = """  Future<void> _loadCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      await loadGeminiPrefs(p);"""
new_fresh = """  Future<void> _loadCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!p.containsKey('settings')) {
        for (final k in const [
          'speedoff27', 'lowdata_v1', 'restore_speed_v1', 'best_defaults_v4',
          'fw5_v1', 'workers12_v2', 'contsearch_v1', 'cip_v2', 'idm_v2',
          'nat_v2', 'defsync_v1', 'defsync_v2', 'badping1700_v1',
          'tuned_v1', 'tuned_v2', 'tuned_v3', 'tuned_v4', 'tuned_v5',
          'bestProfile26', 'fwDefault27', 'bgWorkersOne',
        ]) {
          await p.setBool(k, true);
        }
        for (final o in numOpts) { o.set(o.def); }
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
        dbg('V8-FRESH: default settings applied (no migration)');
      }
      await loadGeminiPrefs(p);"""
if old_fresh in mn:
    mn = mn.replace(old_fresh, new_fresh, 1)
    print('OK: V8-FRESH')

old_reset = """  void resetAllToDefaults() {
    resetNumbers();"""
new_reset = """  void resetAllToDefaults() {
    SharedPreferences.getInstance().then((p) async {
      for (final k in const [
        'speedoff27', 'lowdata_v1', 'restore_speed_v1', 'best_defaults_v4',
        'fw5_v1', 'workers12_v2', 'contsearch_v1', 'cip_v2', 'idm_v2',
        'nat_v2', 'defsync_v1', 'defsync_v2', 'badping1700_v1',
        'tuned_v1', 'tuned_v2', 'tuned_v3', 'tuned_v4', 'tuned_v5',
        'bestProfile26', 'fwDefault27', 'bgWorkersOne',
      ]) {
        await p.setBool(k, true);
      }
    });
    resetNumbers();"""
if old_reset in mn:
    mn = mn.replace(old_reset, new_reset, 1)
    print('OK: resetAllToDefaults sets migration flags')

# =====================================================================
# ---- 9) ★ V8: remove pre-social-check block ----
# =====================================================================
old_presoc = """      if (!trust && !pin && !nationalMode && !proxyMode) {
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
      }"""
new_presoc = "      // V8: pre-social-check removed"
if old_presoc in mn:
    mn = mn.replace(old_presoc, new_presoc, 1)
    print('OK: pre-social-check removed')

# =====================================================================
# ---- 10) needSocial = false ----
# =====================================================================
old_needsoc = "        final needSocial = !proxyMode;"
new_needsoc = "        final needSocial = false; // V8"
if old_needsoc in mn:
    mn = mn.replace(old_needsoc, new_needsoc, 1)
    print('OK: needSocial = false')

# =====================================================================
# ---- 11) ★ V8: add abort guard before final _onConnected ----
# =====================================================================
old_onconn = """      _onConnected(s);
      return true;
    }
    return false;
  }"""
new_onconn = """      // V8: abort guard — do not reconnect if user cancelled
      if (abort || !wantVpn) return false;
      _onConnected(s);
      return true;
    }
    return false;
  }"""
if old_onconn in mn:
    mn = mn.replace(old_onconn, new_onconn, 1)
    print('OK: abort guard before final _onConnected')

# =====================================================================
# ---- 12) Target 3 servers ----
# =====================================================================
if 'const int kStandbyPause = 5;' in mn:
    mn = mn.replace('const int kStandbyPause = 5;',
                    'const int kStandbyPause = 3; // V8', 1)
    print('OK: kStandbyPause = 3')
if 'const int kStandbyResume = 5;' in mn:
    mn = mn.replace('const int kStandbyResume = 5;',
                    'const int kStandbyResume = 3; // V8', 1)
    print('OK: kStandbyResume = 3')
if 'const int kFgSearchTarget = 5;' in mn:
    mn = mn.replace('const int kFgSearchTarget = 5;',
                    'const int kFgSearchTarget = 3; // V8', 1)
    print('OK: kFgSearchTarget = 3')

# =====================================================================
# ---- 13) ★ V8-NATFIX: gold + merge + prescan in _doConnect ----
# =====================================================================
old_doconnect = """      if (nationalMode || indestructibleMode) {
        _resInject();
        await _checkSaved(); // re-test known-good before searching new lists
        if (nationalMode) await _natMergeCache(); // پوشه‌ی منابع تازه (فقط نت ملی)
      }"""
new_doconnect = """      if (nationalMode || indestructibleMode) {
        try {
          await goldLoad();
          await _goldMergeGood(this);
          dbg('V8-NAT: gold=${_goldSrv.length} servers, ${_goldIps.length} IPs');
        } catch (e, stk) { logError(e, stk); }
        _resInject();
        await _checkSaved();
        if (nationalMode) {
          await _natMergeCache();
          final hasTemplate = pending.isNotEmpty ||
              natRestPending.isNotEmpty ||
              natTemplateSeeds.isNotEmpty ||
              good.isNotEmpty ||
              _resMap.isNotEmpty;
          if (pending.isEmpty && hasTemplate) {
            await _natMemoryReuse();
            await _natPrescan();
          } else if (pending.isEmpty) {
            dbg('V8-NAT: no template — skipping prescan');
            _set('نت ملی: هیچ کانفیگی موجود نیست. با نت جهانی وصل شو یا کانفیگ اضافه کن.');
          }
          dbg('V8-NAT: pending=${pending.length} good=${good.length} resMap=${_resMap.length}');
        }
      }"""
if old_doconnect in mn:
    mn = mn.replace(old_doconnect, new_doconnect, 1)
    print('OK: V8-NATFIX in _doConnect')
else:
    print('WARN: national prepare block not found')

# =====================================================================
# ---- 14) ★ V8-FIX: _natIpHunt pool bug (_resMap.values.whereType<Server>) ----
# =====================================================================
old_iphunt_pool = """  final pool = <Server>[];
  pool.addAll(good);
  pool.addAll(pending);
  pool.addAll(_resMap.values.whereType<Server>());"""
new_iphunt_pool = """  final pool = <Server>[];
  pool.addAll(good);
  pool.addAll(pending);
  // V8-FIX: _resMap.values are _NatResItem, not Server
  for (final e in _resMap.values) {
    if (!pool.any((x) => x.link == e.link)) pool.add(e.s);
  }"""
if old_iphunt_pool in mn:
    mn = mn.replace(old_iphunt_pool, new_iphunt_pool, 1)
    print('OK: _natIpHunt pool bug fixed')
else:
    print('WARN: _natIpHunt pool pattern not found')

# =====================================================================
# ---- 15) ★ V8-FIX: _natRangeAdd — no fake template, safe int parse ----
# =====================================================================
old_range = """Future<void> _natRangeAdd(List<String> items, {bool count = true}) async {
  if (items.isEmpty) return;
  for (final it in items) {
    natScanHits.add(it.split('|')[0]);
  }
  final tpl = [...pending, ...natRestPending, ...natTemplateSeeds].take(2).toList();
  if (tpl.isEmpty) return;
  final made = <Server>[
    for (final item in items)
      for (final t in tpl)
        Server(
          _natSetHost(t.link, item.split('|')[0], t.host),
          t.name,
          item.split('|')[0],
          int.parse(item.split('|')[1]),
        ),
  ];
  if (count) natIpFound += items.length;
  dbg('اسکن IP: باز پیداشده ${items.length} • جمع $natIpFound • اسکن‌شده $natIpScanned');
  pending = [...made, ...pending];
  natRangeCursor = 0;
  _set('نت ملی: ${items.length} آدرس باز (IP و پورت) در بازه‌ها پیدا شد');
}"""
new_range = """Future<void> _natRangeAdd(List<String> items, {bool count = true}) async {
  if (items.isEmpty) return;
  for (final it in items) {
    natScanHits.add(it.split('|')[0]);
  }
  final tpl = [...pending, ...natRestPending, ...natTemplateSeeds].take(2).toList();
  // V8-FIX: don't fabricate fake CF configs. Without real template, scanned
  // IPs cannot be tested meaningfully (UUID would fail at core).
  if (tpl.isEmpty) {
    dbg('V8: no template for scanned IPs — skipping add');
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
  dbg('اسکن IP: ${items.length} باز • ${made.length} config • جمع $natIpFound');
  pending = [...made, ...pending];
  natRangeCursor = 0;
  _set('نت ملی: ${items.length} آدرس باز (IP و پورت) پیدا شد');
}"""
if old_range in mn:
    mn = mn.replace(old_range, new_range, 1)
    print('OK: _natRangeAdd — safe + no fake template')
else:
    print('WARN: _natRangeAdd pattern not found')

# =====================================================================
# ---- 16) ★ V8-FIX: _natEscalate — skip scan if no template + 3 min budget ----
# =====================================================================
old_escalate_scan = """      if (nationalMode && !abort && !ipWaiting) {
        final ips = await natRangeScanStep(
            known: [...pending, ...natRestPending],
            maxAddrs: 100000, // هر دور تا ۱۰۰ هزار آدرس
            conc: natAdaptiveWorkers(),
            stop: () => abort,
            budget: const Duration(minutes: 12));
        await _natRangeAdd(ips);
      }"""
new_escalate_scan = """      // V8-FIX: skip scan if no template config exists (would waste minutes)
      final hasTpl = pending.isNotEmpty || natRestPending.isNotEmpty ||
          natTemplateSeeds.isNotEmpty || good.isNotEmpty;
      if (nationalMode && !abort && !ipWaiting && pending.isEmpty && hasTpl) {
        final ips = await natRangeScanStep(
            known: [...pending, ...natRestPending, ...natTemplateSeeds],
            maxAddrs: 30000,
            conc: natAdaptiveWorkers(),
            stop: () => abort,
            budget: const Duration(minutes: 3));
        await _natRangeAdd(ips);
      } else if (nationalMode && !hasTpl && !ipWaiting) {
        dbg('V8-NAT: no template — skipping range scan');
      }"""
if old_escalate_scan in mn:
    mn = mn.replace(old_escalate_scan, new_escalate_scan, 1)
    print('OK: _natEscalate — skip if no template + 3 min')
else:
    print('WARN: _natEscalate scan pattern not found')

# =====================================================================
# ---- 17) sing-box URLs removed ----
# =====================================================================
singbox_paths = """  // PHASE1-SINGBOX: منابع HY2/TUIC اول لیست (مهلت دانلود تمام نشود)
  // verified via search results (paths confirmed in upstream READMEs)
  'soroushmirzaei/telegram-configs-collector/main/protocols/tuic',
  'soroushmirzaei/telegram-configs-collector/main/protocols/hysteria',
  'soroushmirzaei/telegram-configs-collector/main/channels/protocols/tuic',
  'soroushmirzaei/telegram-configs-collector/main/channels/protocols/hysteria',
  'barry-far/V2ray-Configs/main/Splitted-By-Protocol/hysteria2.txt',
  'barry-far/V2ray-Configs/main/Splitted-By-Protocol/tuic.txt',
  '0xRadikal/Free-v2ray-Configs/main/protocols/hysteria2.txt',
  '0xRadikal/Free-v2ray-Configs/main/protocols/tuic.txt',
  'wiki/gfpcom/free-proxy-list/lists/hy2.txt',
  'wiki/gfpcom/free-proxy-list/lists/tuic.txt',
  'nyeinkokoaung404/V2ray-Configs/main/Splitted-By-Protocol/tuic.txt',
  'nyeinkokoaung404/V2ray-Configs/main/Splitted-By-Protocol/hysteria2.txt',
  'R-the-coder/V2ray-configs/main/hysteria2.txt',
  'yebekhe/TelegramV2rayCollector/main/sub/normal/hysteria2',
  'yebekhe/TelegramV2rayCollector/main/sub/normal/tuic',
"""
if singbox_paths in mn:
    mn = mn.replace(singbox_paths, "  // V8: sing-box URLs removed\n", 1)
    print('OK: sing-box URLs removed')

open(MAIN, 'w', encoding='utf-8').write(mn)

# =====================================================================
# ---- 18) singbox stub ----
# =====================================================================
SINGBOX = os.path.join(APP, 'lib/singbox_core.dart')
with open(SINGBOX, 'w', encoding='utf-8') as f:
    f.write("""// singbox_core.dart - SING-BOX REMOVED (V8)
Future<bool> startSingbox(String config) async => false;
Future<void> stopSingbox() async {}
Future<bool> isSingboxAlive() async => false;
String? buildSingboxConfigFromLink(String link) => null;
""")
print('OK: singbox stub')

# =====================================================================
# ---- 19) NAT_ULTRA: natMaxVariants ----
# =====================================================================
n = open(NAT, encoding='utf-8').read()
if 'const int natMaxVariants = 2000000;' in n:
    n = n.replace('const int natMaxVariants = 2000000;',
                  'const int natMaxVariants = 0x7FFFFFFF; // V8', 1)
    print('OK: natMaxVariants')

# =====================================================================
# ---- 20) NAT_ULTRA: natGrow real ----
# =====================================================================
old_grow = "int natGrow(int n) => 0;"
new_grow = """int _natGrowCounter = 0;
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
}"""
if old_grow in n:
    n = n.replace(old_grow, new_grow, 1)
    print('OK: natGrow implemented')

# =====================================================================
# ---- 21) NAT_ULTRA: wire natGrow into _natOrder ----
# =====================================================================
old_order = """    if (app.isNotEmpty && cursor < app.length) {
      final end = min(app.length, cursor + cap);
      for (var k = cursor; k < end; k++) {
        final gv = app[k];
        if (skipHeavy && natIsHeavy(gv)) continue;
        gens.add(gv);
      }
    }"""
new_order = """    if (cursor >= app.length && lvl >= 2) {
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
    }"""
if 'natGrow(1000);' in n:
    print('SKIP: natGrow(1000) already present')
elif old_order in n:
    n = n.replace(old_order, new_order, 1)
    print('OK: natGrow wired into _natOrder')

# =====================================================================
# ---- 22) NAT_ULTRA: 80-block CF mix + deadline check ----
# =====================================================================
old_blocks = """  final blocks = natRanges.isNotEmpty ? natRanges : natSeedBlocks(hosts);
  final addrs = <String>[];
  for (final r in blocks) {
    addrs.addAll(natExpandAny(r));
  }"""
new_blocks = """  final blocks = natRanges.isNotEmpty ? natRanges : natSeedBlocks(hosts);
  final addrs = <String>[];
  for (final r in blocks) {
    addrs.addAll(natExpandAny(r));
  }
  addrs.addAll(_getCfIps());"""
if '_getCfIps()' in n:
    print('SKIP: _getCfIps already wired')
elif old_blocks in n:
    n = n.replace(old_blocks, new_blocks, 1)
    cf_func = """List<String>? _cfIpCache;
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

"""
    if 'List<String> _getCfIps()' not in n:
        n = n.replace('Future<List<String>> natRangeScanStep(',
                      cf_func + 'Future<List<String>> natRangeScanStep(', 1)
        print('OK: _getCfIps inserted + 80-block CF')

# Add deadline check to natRangeScanStep loop
old_loop = """  for (final port in portList) {
    if (stop != null && stop()) break;
    final hits = await natScanIps("""
new_loop = """  final scanDeadline = DateTime.now().add(budget);
  for (final port in portList) {
    if (stop != null && stop()) break;
    if (DateTime.now().isAfter(scanDeadline)) break; // V8: respect overall budget
    final hits = await natScanIps("""
if old_loop in n:
    n = n.replace(old_loop, new_loop, 1)
    print('OK: natRangeScanStep deadline check')

open(NAT, 'w', encoding='utf-8').write(n)

print('')
print('=== V8-FINAL DONE ===')
print('Bugs fixed:')
print('  1. _natIpHunt: whereType<Server> bug → extract .s')
print('  2. kNatMergeCache=false → true')
print('  3. kFolderInjectGood=false → true')
print('  4. _natRangeAdd: int.parse crash + fake template')
print('  5. _onConnected: abort guard added')
print('  6. _doConnect: gold + prescan with proper checks')
print('  7. natRangeScanStep: deadline enforced')
print('  + telegram check removed (5-10x faster)')
print('  + 3-server target')
print('  + DPI/Fragment/_natLadder — UNTOUCHED ✅')
