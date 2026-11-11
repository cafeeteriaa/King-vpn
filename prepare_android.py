import os
import re
import shutil
import random

APP = 'build_app'

# ---- 1) AndroidManifest permissions ------------------------------------------
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

# ---- 3) Fresh-sources folder ----
NAT = os.path.join(APP, 'lib/nat_ultra.dart')
MAIN = os.path.join(APP, 'lib/main.dart')

def patch_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit('ERROR: %s found %d times (must be 1). Build stopped.' % (label, count))
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
  } catch (e) {
    logError(e);
  }
}
Future<void> hotAutoFill() async {
  try {
    if (!(await Permission.manageExternalStorage.isGranted)) return;
  } catch (e) {
    logError(e);
    return;
  }
  await natHotEnsure();
}
Future<void> hotAutoStart() async {
  try {
    WidgetsBinding.instance.addObserver(HotResumeWatcher());
  } catch (e) {
    logError(e);
  }
  try {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool('hotAsked') ?? false)) {
      await p.setBool('hotAsked', true);
      await hotStorageAllow();
    }
  } catch (e) {
    logError(e);
  }
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
    n = patch_once(n, OLD_PATH, NEW_PATH, 'folder path')
    n = patch_once(n, OLD_ENSURE, NEW_ENSURE, 'folder ensure')
    if not n.endswith('\n'): n += '\n'
    n += APPEND
    open(NAT, 'w', encoding='utf-8').write(n)

mn = open(MAIN, encoding='utf-8').read()
if 'hotAutoStart()' not in mn:
    mn = patch_once(mn, 'void main() {\n', 'void main() {\n  Future.delayed(const Duration(seconds: 5), () => unawaited(hotAutoStart()));\n', 'main()')
    open(MAIN, 'w', encoding='utf-8').write(mn)

# ---- 4) Relay Server & IP Range buttons ----
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
                if (chainCfg != null) dbg('MULTIHOP: استفاده از سرور واسط دستی برای ${s.name}');
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

# ---- 5) DIALER-PROXY fix ----
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
if old_proxy in mn:
    mn = mn.replace(old_proxy, new_proxy, 1)
    print('OK: proxySettings removed')

# =====================================================================
# ---- 6) V8 MAIN PATCHES ----
# =====================================================================
print('Applying V8 main.dart patches...')

# 6a) V8-FRESH: on fresh install, apply canonical defaults (== resetAllToDefaults)
old_fresh = """  Future<void> _loadCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      await loadGeminiPrefs(p);"""
new_fresh = """  Future<void> _loadCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      // V8-FRESH: on fresh install, apply canonical defaults so first-launch
      // numbers match resetAllToDefaults(). All migrations are skipped.
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
        for (final o in numOpts) {
          o.set(o.def);
        }
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
        dbg('V8-FRESH: پیش‌فرض‌های استاندارد اعمال شد (بدون migration)');
      }
      await loadGeminiPrefs(p);"""
if old_fresh in mn:
    mn = mn.replace(old_fresh, new_fresh, 1)
    print('OK: V8-FRESH applied (fresh install = reset defaults)')
else:
    print('WARN: V8-FRESH anchor not found')

# 6b) Target 3 servers instead of 5
old_pause = "const int kStandbyPause = 5; // هدف همیشگی: ۵ سرور سالم، از اولین جستجو تا آخر"
new_pause = "const int kStandbyPause = 3; // V8: هدف ۳ سرور سالم"
if old_pause in mn:
    mn = mn.replace(old_pause, new_pause, 1)
    print('OK: kStandbyPause = 3')
else:
    print('WARN: kStandbyPause not found')

old_resume = "const int kStandbyResume = 5; // RESUME5: وقتی سالم‌ها زیر ۵ آمد جستجو دوباره روشن می‌شود"
new_resume = "const int kStandbyResume = 3; // V8: زیر ۳ جستجو دوباره روشن"
if old_resume in mn:
    mn = mn.replace(old_resume, new_resume, 1)
    print('OK: kStandbyResume = 3')
else:
    print('WARN: kStandbyResume not found')

old_fg = "const int kFgSearchTarget = 5; // FG5: تست سریع با ۵ سالم تمام می‌شود و وصل می‌شود"
new_fg = "const int kFgSearchTarget = 3; // V8: تست سریع با ۳ سالم تمام می‌شود"
if old_fg in mn:
    mn = mn.replace(old_fg, new_fg, 1)
    print('OK: kFgSearchTarget = 3')
else:
    print('WARN: kFgSearchTarget not found')

# 6c) Remove pre-social-check block (before connect)
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
new_presoc = "      // V8: pre-social-check removed (connect directly like v2rayNG)"
if old_presoc in mn:
    mn = mn.replace(old_presoc, new_presoc, 1)
    print('OK: pre-social-check removed')
else:
    print('WARN: pre-social-check block not found')

# 6d) Remove ping/tun/social block AFTER coreUpCount++ in _connectLoop
# Strategy: use regex from coreUpCount++ to _onConnected(s) in _connectLoop
pattern_post = re.compile(
    r'(      coreUpCount\+\+; // CORE-SYSTEMIC: the core started for this config\n)'
    r'.*?'
    r'(      _onConnected\(s\);\n      return true;\n)',
    re.DOTALL,
)
replacement_post = (
    r'\1'
    r'      // V8: extra checks removed (start already verified traffic via pingAny)\n'
    r'\2'
)
mn, n_post = pattern_post.subn(replacement_post, mn, count=1)
if n_post == 1:
    print('OK: post-connect ping/tun/social checks removed')
else:
    print('WARN: post-connect checks pattern matched %d times' % n_post)

# 6e) Remove stopSingbox() call in _stopV2
old_stopsb = "      try { await stopSingbox(); } catch (_) {} // SINGBOX: هر دو هسته خاموش شوند\n"
if old_stopsb in mn:
    mn = mn.replace(old_stopsb, '', 1)
    print('OK: stopSingbox() call removed from _stopV2')
else:
    print('WARN: stopSingbox() call not found')

open(MAIN, 'w', encoding='utf-8').write(mn)

# =====================================================================
# ---- 7) SINGBOX STUB ----
# =====================================================================
SINGBOX = os.path.join(APP, 'lib/singbox_core.dart')
if os.path.exists(SINGBOX):
    with open(SINGBOX, 'w', encoding='utf-8') as f:
        f.write("""// singbox_core.dart - SING-BOX SUPPORT REMOVED
// Kept as compile-only stub. kSingboxEnabled is false everywhere,
// so none of these are ever called at runtime.

Future<bool> startSingbox(String config) async => false;
Future<void> stopSingbox() async {}
Future<bool> isSingboxAlive() async => false;
String? buildSingboxConfigFromLink(String link) => null;
""")
    print('OK: singbox_core.dart replaced with stub')

# =====================================================================
# ---- 8) NAT_ULTRA PATCHES ----
# =====================================================================
print('Applying nat_ultra.dart patches...')
n = open(NAT, encoding='utf-8').read()

# 8a) natMaxVariants: no cap
if 'const int natMaxVariants = 2000000;' in n:
    n = n.replace('const int natMaxVariants = 2000000;',
                  'const int natMaxVariants = 0x7FFFFFFF; // V8: no cap', 1)
    print('OK: natMaxVariants bumped')

# 8b) natGrow: stub -> real
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
      fp: fp, alpn: alpn, frag: frag,
      port: port, portIdx: portIdx,
      clean: clean, cleanIdx: cleanIdx,
      v4: v4, tfo: tfo, keep: keep, doh: doh,
    ));
    added++;
  }
  if (added > 0) {
    _natNamesC = null;
    _natGenRankKey = '';
  }
  return added;
}"""
if old_grow in n:
    n = n.replace(old_grow, new_grow, 1)
    print('OK: natGrow implemented')

# 8c) _natOrder: call natGrow when cursor exhausted
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
if old_order in n:
    n = n.replace(old_order, new_order, 1)
    print('OK: natGrow(1000) wired into _natOrder')
else:
    print('WARN: _natOrder pattern not found')

# 8d) 80/20 mix: 80 CF blocks × 2000 IPs (safe on 6GB, ~160k strings)
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
  // V8-MIX-80: 80 Cloudflare blocks × 2000 random IPs = 160k total
  // (safe on 6GB RAM; full /13 expansion = 5.2M = OOM)
  final rndMix = Random(42);
  for (final cidr in _cfRanges.take(80)) {
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
    for (var i = 0; i < 2000; i++) {
      final v = base + rndMix.nextInt(span);
      addrs.add('${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}');
    }
  }"""
if old_blocks in n:
    n = n.replace(old_blocks, new_blocks, 1)
    print('OK: 80/20 mix applied (80 CF blocks × 2000 IPs)')
else:
    print('WARN: natRangeScanStep blocks pattern not found')

open(NAT, 'w', encoding='utf-8').write(n)
print('All V8 patches done.')
