# patch_plugin.py — patches flutter_v2ray_client 3.5.0 (Android) before the build.
# Run from the repo root AFTER `flutter pub get`.
#  1) V2rayCoreManager.java: replaced by plugin_patch/V2rayCoreManager.java
#     (VPN race fix + bounded, time-limited delay test; see DELAYFIX in the file).
#  2) V2rayVPNService.java: re-register the listener before the core starts.
import glob, os, shutil, sys
PUB = os.environ.get('PUB_CACHE', os.path.expanduser('~/.pub-cache'))
HERE = os.path.dirname(os.path.abspath(__file__))

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
        print(f'ERROR: {label}: found {n} times (must be 1). Build stopped.'); sys.exit(1)
    open(path, 'w', encoding='utf-8').write(s.replace(old, new, 1))
    print(f'OK: {label}')

# 1) whole file replaced (contains the VPN race fix and the delay fix)
shutil.copyfile(os.path.join(HERE, 'V2rayCoreManager.java'), core)
print('OK: V2rayCoreManager.java replaced')

# 2) re-register the current service right before the native core starts.
patch(vpn,
      "            // 1) Establish VpnService TUN first (v2rayNG order).",
      "            // VPNRACE: make sure the core knows THIS service instance before starting\n"
      "            V2rayCoreManager.getInstance().setUpListener(this);\n\n"
      "            // 1) Establish VpnService TUN first (v2rayNG order).",
      're-register listener before start')
