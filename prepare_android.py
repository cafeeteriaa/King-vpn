import os
import re

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

import shutil
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

# ---- 2) Gradle: minSdk 24, compileSdk 37 ----
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

# ---- 3) Fresh-sources folder and automatic start ----
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
mn = open(MAIN, encoding='utf-8').read()
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

# ---- 5) AUTO IP MIX (50% Cloudflare + 50% User/Auto) ----
old_blocks = "final blocks = natRanges.isNotEmpty ? natRanges : (natSeedBlocks(hosts).isNotEmpty ? natSeedBlocks(hosts) : _cfRanges.take(5).toList());"
new_blocks = """final autoBlocks = natSeedBlocks(hosts);
  final mixBlocks = <String>{};
  if (natRanges.isNotEmpty) {
    mixBlocks.addAll(natRanges);
  } else {
    mixBlocks.addAll(autoBlocks);
  }
  mixBlocks.addAll(_cfRanges);
  final blocks = mixBlocks.toList()..shuffle();"""
if old_blocks in n:
    n = n.replace(old_blocks, new_blocks, 1)
    open(NAT, 'w', encoding='utf-8').write(n)

# ---- 6) FIX DIALER-PROXY & VLESS ----
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

old_vless = """  if (security != 'tls' && security != 'reality') {
    final ipv4 = RegExp(r'^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$').hasMatch(uri.host);
    if (ipv4 && !_isPrivateIpv4(uri.host)) {
      return 'VLESS بدون TLS روی IP عمومی';
    }
  }"""
new_vless = """  if (security != 'tls' && security != 'reality') {
    final ipv4 = RegExp(r'^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$').hasMatch(uri.host);
    final isPrivate = ipv4 && _isPrivateIpv4(uri.host);
    if (!isPrivate) {
      return 'VLESS بدون TLS (هسته Xray این را ممنوع کرده)';
    }
  }"""
if old_vless in mn: mn = mn.replace(old_vless, new_vless, 1)
open(MAIN, 'w', encoding='utf-8').write(mn)


# ---- 7) RESTORE MASSIVE MATRIX & INFINITE GROWTH ----
print('Applying Infinite Matrix patch...')

n = open(NAT, encoding='utf-8').read()

# 7a) Generate 100k variants
old_gen = """  for (final g in rest) {
    add(_natMk(frag: g, fp: 'firefox'));
  }
  return out;
}"""
new_gen = """  for (final g in rest) {
    add(_natMk(frag: g, fp: 'firefox'));
  }
  
  // V7-MASSIVE-MATRIX: Generate hundreds of thousands of variants to reach the 2M goal.
  for (final g in _natFrags.take(40)) {
    final fi = _natFrags.indexOf(g);
    for (final p in fps) {
      for (final a in alpns) {
        for (final portIdx in [0, 1, 2, 3, 4, 5]) {
          for (final d in _natDnsList.take(5)) {
            add(_natMk(frag: fi, fp: p, alpn: a, port: true, portIdx: portIdx, doh: d));
          }
        }
      }
    }
  }
  for (final g in _natFrags.take(20)) {
    final fi = _natFrags.indexOf(g);
    for (final p in ['chrome', 'firefox', 'randomized']) {
      for (final d in _natDnsList.take(10)) {
        for (final clIdx in [0, 1, 2, 3, 4]) {
          add(_natMk(frag: fi, fp: p, clean: true, cleanIdx: clIdx, doh: d));
        }
      }
    }
  }
  return out;
}"""

if old_gen in n:
    n = n.replace(old_gen, new_gen, 1)
else:
    print('WARN: _natGenerate target not found (already patched?)')

# 7b) Replace the disabled natGrow with an infinite generator using ALL building blocks
old_grow = "int natGrow(int n) => 0;"
new_grow = """
int _natSeedCounter = 0;
int natGrow(int n) {
  // V7-INFINITE: Generates `n` new random variants and adds them to _natSpecs.
  // Uses every possible building block (ports, DNS, Frag, FP, ALPN, Clean IP, SNI, Mux, etc.)
  if (_natSpecs.length > 5000000) _natSpecs.removeRange(100, 2000000); // Memory safety cap
  final rnd = Random(DateTime.now().millisecondsSinceEpoch + _natSeedCounter++);
  final existingSigs = {for (final x in _natSpecs) _natSig(x)};
  var added = 0;
  const fps = ['chrome', 'firefox', 'randomized', 'ios', 'android', 'safari', 'edge', 'random', 'qq', '360'];
  const alpns = [null, 'h2', 'http/1.1', 'h2,http/1.1'];
  for (var i = 0; i < n; i++) {
    final fp = fps[rnd.nextInt(fps.length)];
    final alpn = alpns[rnd.nextInt(alpns.length)];
    final frag = rnd.nextInt(_natFrags.length);
    final port = rnd.nextBool();
    final portIdx = port ? rnd.nextInt(_natCfPorts.length) : null;
    final clean = rnd.nextBool();
    final cleanIdx = clean ? rnd.nextInt(10) : null;
    final doh = rnd.nextBool() ? _natDnsList.elementAt(rnd.nextInt(_natDnsList.length)) : null;
    final other = rnd.nextBool();
    final sniHost = rnd.nextBool();
    final v4 = rnd.nextBool();
    final tfo = rnd.nextBool();
    final nodelay = rnd.nextBool();
    final keep = rnd.nextBool() ? rnd.nextInt(30) + 1 : null;
    final mss = rnd.nextBool() ? [1240, 1280, 1320, 1360].elementAt(rnd.nextInt(4)) : null;
    final ed = rnd.nextBool();
    final edN = ed ? [512, 1024, 2048, 4096].elementAt(rnd.nextInt(4)) : null;
    
    final newSpec = _NatSpec('Dynamic ${_natSpecs.length + 1}',
      other: other, fp: fp, alpn: alpn, frag: frag, port: port, portIdx: portIdx,
      clean: clean, cleanIdx: cleanIdx, sniHost: sniHost, v4: v4, tfo: tfo,
      nodelay: nodelay, doh: doh, keep: keep, mss: mss, ed: ed, edN: edN);
    
    final sig = _natSig(newSpec);
    if (existingSigs.add(sig)) {
      _natSpecs.add(newSpec);
      added++;
    }
  }
  if (added > 0) {
    _natNamesC = null; // Invalidate name cache
    _natGenRankKey = ''; // Force re-ranking
    // ignore: avoid_print
    print('NATGROW: Generated \\$added new dynamic variants. Total: \\${_natSpecs.length}');
  }
  return added;
}
"""
if old_grow in n:
    n = n.replace(old_grow, new_grow, 1)
else:
    print('WARN: natGrow target not found (already patched?)')

# 7c) Patch _natOrder to call natGrow when exhausted
old_order = """        if (app.isNotEmpty && cursor < app.length) {
          final end = min(app.length, cursor + cap);
          for (var k = cursor; k < end; k++) {
            final gv = app[k];
            if (skipHeavy && natIsHeavy(gv)) continue;
            gens.add(gv);
          }
        }"""
new_order = """        if (cursor >= app.length && lvl >= 2) {
          natGrow(1000); // Generate 1000 more variants!
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
else:
    print('WARN: _natOrder target not found (already patched?)')

# 7d) Set natMaxVariants to infinite (32-bit max)
n = n.replace("const int natMaxVariants = 2000000;", "const int natMaxVariants = 0x7FFFFFFF; // V7: Infinite")

open(NAT, 'w', encoding='utf-8').write(n)
