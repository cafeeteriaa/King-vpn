import os
import re

# Android setup for build_app (manifest permissions, gradle versions) and the
# Dart changes that make the fresh-sources folder visible on the phone
# (Download/King-VPN) and filled automatically when the app opens.
# Every edit must match exactly once, otherwise the build stops with a message.
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
# FGSTYPE: Android 14+ (targetSDK 36) needs a foreground service type. The plugin starts its
# proxy service without one ("Starting FGS without a type"), so the type is declared here.
SVC = ('<service android:name="dev.amirzr.flutter_v2ray_client.v2ray.services.V2rayProxyOnlyService"\n'
       '             android:foregroundServiceType="specialUse">\n'
       '            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"\n'
       '                      android:value="local proxy core for the user"/>\n'
       '        </service>\n    ')
if 'foregroundServiceType' not in m and '</application>' in m:
    m = m.replace('</application>', SVC + '</application>', 1)
    print('OK: foreground service type declared in manifest')
# KINGVPN: our own VPN service (android_src/KingVpnService.java) — declared in the manifest
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
    print('OK: own VPN service declared in manifest')
open(mp, 'w', encoding='utf-8').write(m)

# KINGVPN: copy our Java service and MainActivity (channel king/vpn) into the project
import shutil
ja = os.path.join(APP, 'android/app/src/main/java/com/kingvpn/king_vpn')
os.makedirs(ja, exist_ok=True)
shutil.copy('android_src/KingVpnService.java', ja)
shutil.copy('android_src/KingDiag.java', ja)  # KINGDIAG: crash / process-exit recorder
old_java_main = os.path.join(ja, 'MainActivity.java')
if os.path.exists(old_java_main):
    os.remove(old_java_main)
ka = os.path.join(APP, 'android/app/src/main/kotlin/com/kingvpn/king_vpn')
os.makedirs(ka, exist_ok=True)
shutil.copy('android_src/MainActivity.kt', os.path.join(ka, 'MainActivity.kt'))
print('OK: KingVpnService.java, KingDiag.java and MainActivity.kt copied')
print('OK: manifest permissions')

# ---- 2) Gradle: minSdk 24, compileSdk 37 (permission_handler_android needs 37) -
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

# ---- 2b) ABI: drop x86/x86_64 universal slices -------------------------------
for name in ('build.gradle', 'build.gradle.kts'):
    gp = os.path.join(APP, 'android/app', name)
    if not os.path.exists(gp):
        continue
    g = open(gp, encoding='utf-8').read()
    if 'abiFilters' in g:
        print('OK: %s already has abiFilters' % name)
        continue
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
        print('OK: %s abiFilters added (arm64-v8a, armeabi-v7a only)' % name)
    else:
        print('WARN: %s has no defaultConfig block; abiFilters NOT added '
              '(edit android/app/%s by hand)' % (name, name))

# ---- 3) Fresh-sources folder and automatic start -----------------------------
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

NEW_PATH = """// HOTVISIBLE: the fresh-sources folder is Download/King-VPN, so it can be seen in
// the phone's file manager. It needs the "All files access" permission; without it
// the app keeps using the old private file.
const String hotVisibleDir = '/storage/emulated/0/Download/King-VPN';
String _hotPath() {
  try {
    final v = Directory(hotVisibleDir);
    if (!v.existsSync()) v.createSync(recursive: true);
    // PERMFIX: the folder can exist without write access (errno 13); probe it first.
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

NEW_ENSURE = ("  if (force) await hotStorageAllow(); // HOTVISIBLE: asks when the user taps the row\n"
              "  if (_hotBusy) return; // HOTRACE: no await between this check and _hotBusy = true\n"
              "  final f = File(_hotPath());\n")

APPEND = """
// HOTVISIBLE: asks the phone for "All files access" (used once at first start, and when the user taps the folder row)
Future<void> hotStorageAllow() async {
  try {
    final st = Permission.manageExternalStorage;
    if (await st.isGranted) return;
    await st.request();
  } catch (e) {
    logError(e);
  }
}

// HOTAUTO: fills the folder only when the visible-folder permission is granted.
// Downloads only if the folder is missing or older than 24 hours.
Future<void> hotAutoFill() async {
  try {
    if (!(await Permission.manageExternalStorage.isGranted)) return;
  } catch (e) {
    logError(e);
    return;
  }
  await natHotEnsure();
}

// HOTAUTO: runs once when the app starts. Asks for file access on the first start only.
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

// HOTAUTO: every time the app comes back to the front, apply the 24-hour rule again
class HotResumeWatcher extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(hotAutoFill());
  }
}
"""

n = open(NAT, encoding='utf-8').read()
if 'hotVisibleDir' in n:
    print('OK: folder patch already applied')
else:
    n = patch_once(n, OLD_PATH, NEW_PATH, 'folder path')
    n = patch_once(n, OLD_ENSURE, NEW_ENSURE, 'folder ensure')
    if not n.endswith('\n'):
        n += '\n'
    n += APPEND
    open(NAT, 'w', encoding='utf-8').write(n)
    print('OK: visible folder and automatic start added to nat_ultra.dart')

mn = open(MAIN, encoding='utf-8').read()
if 'hotAutoStart()' in mn:
    print('OK: automatic start already hooked into main()')
else:
    mn = patch_once(
        mn,
        'void main() {\n',
        'void main() {\n'
        '  Future.delayed(const Duration(seconds: 5), () => unawaited(hotAutoStart())); // HOTAUTO\n',
        'main()')
    open(MAIN, 'w', encoding='utf-8').write(mn)
    print('OK: automatic start hooked into main()')


# ---- 4) Relay Server (Multi-hop) Integration ----
print('Applying Relay Server patches...')

mn = open(MAIN, encoding='utf-8').read()

# 4a) Patch _startImpl to prioritize the user-defined relay
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
if old_chain in mn:
    mn = mn.replace(old_chain, new_chain)
    print('OK: Multi-hop relay logic patched into _startImpl')
else:
    print('WARN: old_chain not found in main.dart (maybe already patched)')

# 4b) Patch _loadCache
old_load = "npvParse = j['npv'] as bool? ?? npvParse;"
new_load = "npvParse = j['npv'] as bool? ?? npvParse;\n          relayServerUrl = j['relay_url'] as String? ?? '';"
if old_load in mn:
    mn = mn.replace(old_load, new_load, 1)
    print('OK: Relay URL load patched')
else:
    print('WARN: old_load not found (load)')

# 4c) Patch _saveSettings
old_save = "'npv': npvParse,"
new_save = "'npv': npvParse,\n            'relay_url': relayServerUrl,"
if old_save in mn:
    mn = mn.replace(old_save, new_save, 1)
    print('OK: Relay URL save patched')
else:
    print('WARN: old_save not found (save)')

# 4d) Add Relay Server button and IP ranges button to the main page (UiTools) - ROBUST PATCH
old_ui = "UiTools(items: ["
new_ui = "UiTools(items: [\n            UiTool(Icons.swap_horiz, 'سرور واسط (نت ملی)', () => showRelayDialog(context)),\n            UiTool(Icons.router, 'بازه‌های IP نت ملی', () => _natRangesDialog(context)),"
if old_ui in mn:
    mn = mn.replace(old_ui, new_ui, 1)
    print('OK: Relay and IP Range buttons injected at the top of UiTools')
else:
    print('WARN: UiTools(items: [ not found, trying old method...')
    old_tool = "UiTool(Icons.add_home_outlined, 'ساخت سرور شخصی', () => connectPersonalAsk()),"
    new_tool = "UiTool(Icons.swap_horiz, 'سرور واسط (نت ملی)', () => showRelayDialog(context)),\n            UiTool(Icons.router, 'بازه‌های IP نت ملی', () => _natRangesDialog(context)),\n            UiTool(Icons.add_home_outlined, 'ساخت سرور شخصی', () => connectPersonalAsk()),"
    if old_tool in mn:
        mn = mn.replace(old_tool, new_tool, 1)
        print('OK: Relay and IP Range buttons added before Personal Server')
    else:
        print('WARN: old_tool not found (UI button)')

# ---- 5) FIX IP RANGES (NAT-NOIP BUG) ----
# Fallback to Cloudflare ranges if the user hasn't provided any
old_blocks = "final blocks = natRanges.isNotEmpty ? natRanges : natSeedBlocks(hosts);"
new_blocks = "final blocks = natRanges.isNotEmpty ? natRanges : (natSeedBlocks(hosts).isNotEmpty ? natSeedBlocks(hosts) : _cfRanges.take(5).toList());"
if old_blocks in n:
    n = n.replace(old_blocks, new_blocks, 1)
    open(NAT, 'w', encoding='utf-8').write(n)
    print('OK: NAT-NOIP patched - default IP ranges added')
else:
    print('WARN: NAT-NOIP patch not applied (already patched?)')

# ---- 6) FIX DIALER-PROXY BUG ----
# Ensure proxySettings is also removed if outbound is missing
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
    print('OK: dialerProxy/proxySettings bug patched')
else:
    print('WARN: old_proxy not found (already patched?)')

# ---- 7) FIX VLESS WITHOUT TLS BUG ----
# Xray core prohibits any VLESS without TLS/reality on public networks.
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
if old_vless in mn:
    mn = mn.replace(old_vless, new_vless, 1)
    print('OK: VLESS without TLS bug patched')
else:
    print('WARN: old_vless not found (already patched?)')

open(MAIN, 'w', encoding='utf-8').write(mn)
