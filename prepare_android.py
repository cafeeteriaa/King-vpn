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
         '    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>\n'
         '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
         '    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>\n    ')
if 'QUERY_ALL_PACKAGES' not in m:
    m = m.replace('<application', perms + '<application', 1)
open(mp, 'w', encoding='utf-8').write(m)
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
  } catch (_) {
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

NEW_ENSURE = ("  if (_hotBusy) return;\n"
              "  if (force) await hotStorageAllow(); // HOTVISIBLE: asks when the user taps the row\n"
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
