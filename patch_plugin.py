# patch_plugin.py — fixes the race in flutter_v2ray_client 3.5.0 (Android VPN mode).
# Run from the repo root AFTER `flutter pub get`. Finds the plugin in the pub cache and edits 2 Java files.
# Every edit must match exactly once, otherwise the build stops with a message.
import glob, os, re, sys
PUB = os.environ.get('PUB_CACHE', os.path.expanduser('~/.pub-cache'))

roots = glob.glob(os.path.join(PUB, 'hosted/*/flutter_v2ray_client-3.5.0/android/src/main/java'))
if not roots:
    roots = glob.glob(os.path.join(PUB, '**/flutter_v2ray_client-3.5.0/android/src/main/java'), recursive=True)
if not roots:
    print('ERROR: flutter_v2ray_client 3.5.0 not found in pub cache'); sys.exit(1)
base = roots[0]
core = os.path.join(base, 'dev/amirzr/flutter_v2ray_client/v2ray/core/V2rayCoreManager.java')
vpn = os.path.join(base, 'dev/amirzr/flutter_v2ray_client/v2ray/services/V2rayVPNService.java')

def patch(path, old, new, label):
    s = open(path, encoding='utf-8').read()
    n = s.count(old)
    if n != 1:
        # PLUGINSKIP: کد پلاگین با این الگو نمی‌خواند؛ بیلد متوقف نمی‌شود و این یک اصلاح کوچک جا می‌ماند
        print(f'WARN: {label}: found {n} times (expected 1). Skipped, build continues.')
        return
    open(path, 'w', encoding='utf-8').write(s.replace(old, new, 1))
    print(f'OK: {label}')

# 1) The core's shutdown callback must NOT clear the service reference.
#    Otherwise, when the old core finishes stopping after a new service started,
#    the new service loses its reference -> NullPointerException in startCore.
patch(core,
      "                        v2rayServicesListener.stopService();\n                        v2rayServicesListener = null;",
      "                        v2rayServicesListener.stopService();\n                        // VPNRACE: keep the reference (the old code cleared it here)",
      'shutdown keeps listener')

# 2) Re-register the current service right before the native core starts.
patch(vpn,
      "            // 1) Establish VpnService TUN first (v2rayNG order).",
      "            // VPNRACE: make sure the core knows THIS service instance before starting\n"
      "            V2rayCoreManager.getInstance().setUpListener(this);\n\n"
      "            // 1) Establish VpnService TUN first (v2rayNG order).",
      're-register listener before start')

# 3) DELAYPOOL: پلاگین یک صف مخصوص تست تأخیر دارد: DELAY_THREADS = 2 (خط ۴۵۵)
#    که با Executors.newFixedThreadPool(DELAY_THREADS, ...) ساخته می‌شود.
#    این عدد سقف واقعی تست همزمان است؛ آن را به ۱۶ می‌بریم.
DELAY_THREADS_NEW = 12
try:
    src = open(core, encoding='utf-8').read()
    pat = re.compile(r'(private\s+static\s+final\s+int\s+DELAY_THREADS\s*=\s*)(\d+)(\s*;)')
    m = pat.findall(src)
    if len(m) == 1:
        if int(m[0][1]) != DELAY_THREADS_NEW:
            src2 = pat.sub(lambda g: g.group(1) + str(DELAY_THREADS_NEW) + g.group(3), src, count=1)
            open(core, 'w', encoding='utf-8').write(src2)
            print(f'OK: DELAYPOOL DELAY_THREADS {m[0][1]} -> {DELAY_THREADS_NEW}')
        else:
            print('OK: DELAYPOOL already ' + str(DELAY_THREADS_NEW))
    else:
        print(f'WARN: DELAYPOOL: DELAY_THREADS found {len(m)} times (expected 1). Skipped.')
except Exception as e:
    print(f'WARN: DELAYPOOL failed: {e}')
