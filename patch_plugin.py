# patch_plugin.py - fixes the VPN race in flutter_v2ray_client 3.5.0 (Android VPN mode).
# Run from build_app/ (the Flutter project folder) AFTER `flutter pub get`.
# This version matches code with flexible whitespace, and when a critical patch
# cannot be found it prints the nearby code so the problem can be diagnosed.
import glob, os, re, sys

PUB = os.environ.get('PUB_CACHE', os.path.expanduser('~/.pub-cache'))

roots = glob.glob(os.path.join(PUB, 'hosted/*/flutter_v2ray_client-3.5.0/android/src/main/java'))
if not roots:
    roots = glob.glob(os.path.join(PUB, '**/flutter_v2ray_client-3.5.0/android/src/main/java'), recursive=True)
if not roots:
    print('ERROR: flutter_v2ray_client 3.5.0 not found in pub cache')
    sys.exit(1)
base = roots[0]
print('Plugin source folder:', base)


def find_java(name):
    """Find a Java file by its file name anywhere under the plugin source."""
    hits = glob.glob(os.path.join(base, '**', name), recursive=True)
    if not hits:
        print(f'ERROR: {name} not found under {base}')
        sys.exit(1)
    return hits[0]


core = find_java('V2rayCoreManager.java')
vpn = find_java('V2rayVPNService.java')
print('Core file:', core)
print('VPN file :', vpn)


def show_context(src, keyword, width=400):
    """Print the code around the first occurrence of keyword (for diagnosis)."""
    i = src.find(keyword)
    if i < 0:
        print(f'   (keyword "{keyword}" not present in file)')
        return
    print('   --- nearby code ---')
    print(src[max(0, i - width // 2): i + width // 2])
    print('   -------------------')


def patch_regex(path, pattern, repl, label, critical, keyword_hint=''):
    src = open(path, encoding='utf-8').read()
    matches = re.findall(pattern, src, flags=re.DOTALL)
    if len(matches) != 1:
        level = 'ERROR' if critical else 'WARN'
        print(f'{level}: {label}: found {len(matches)} times (expected 1).')
        if keyword_hint:
            show_context(src, keyword_hint)
        if critical:
            sys.exit(1)
        return False
    new_src = re.sub(pattern, repl, src, count=1, flags=re.DOTALL)
    open(path, 'w', encoding='utf-8').write(new_src)
    print(f'OK: {label}')
    return True


# 1) The core's shutdown callback must NOT clear the service reference.
#    The 3.5.0 plugin may already contain this fix. If the "= null" line is
#    gone (or the fix comment is present), nothing needs to change.
shutdown_pattern = r'(stopService\(\)\s*;[\s\S]{0,300}?)v2rayServicesListener\s*=\s*null\s*;'
shutdown_repl = r'\1/* VPNRACE: keep the reference */'
src_core = open(core, encoding='utf-8').read()
if re.search(r'VPNRACE|keep the reference', src_core):
    print('OK: shutdown keeps listener (already fixed in plugin)')
elif not re.search(r'stopService\(\)\s*;[\s\S]{0,300}?v2rayServicesListener\s*=\s*null', src_core):
    print('OK: shutdown keeps listener (no reference clearing found, nothing to patch)')
else:
    patch_regex(core, shutdown_pattern, shutdown_repl,
                'shutdown keeps listener', critical=True,
                keyword_hint='stopService')

# 2) Re-register the current service right before the native core starts.
#    Try a few anchors, because the comment text may differ.
REG = ('// VPNRACE: make sure the core knows THIS service instance before starting\n'
       '            V2rayCoreManager.getInstance().setUpListener(this);\n\n')
anchors = [
    r'(\n[ \t]*)(//\s*1\)\s*Establish VpnService TUN first)',
    r'(\n[ \t]*)(V2rayCoreManager\.getInstance\(\)\.startCore)',
    r'(\n[ \t]*)(startCore\()',
]
done = False
src = open(vpn, encoding='utf-8').read()
for a in anchors:
    if len(re.findall(a, src)) >= 1 and 'setUpListener(this)' not in src:
        # Insert before the first matching anchor only.
        src = re.sub(a, lambda m: m.group(1) + REG + m.group(2), src, count=1)
        open(vpn, 'w', encoding='utf-8').write(src)
        print('OK: re-register listener before start (anchor: ' + a[:30] + ')')
        done = True
        break
if not done:
    if 'setUpListener(this)' in src:
        print('OK: re-register listener already present')
    else:
        print('ERROR: re-register listener before start: no anchor found.')
        show_context(src, 'startCore')
        sys.exit(1)

# 3) DELAYPOOL: the plugin's latency-test queue has DELAY_THREADS = 2.
#    We raise it to DELAY_THREADS_NEW (this is the real limit for simultaneous tests).
DELAY_THREADS_NEW = 32  # C1-FIX: was 1000. Conservative cap chosen by judgment, NOT measured on device.
try:
    src = open(core, encoding='utf-8').read()
    pat = re.compile(r'(DELAY_THREADS\s*=\s*)(\d+)(\s*;)')
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

print('patch_plugin.py finished OK')
