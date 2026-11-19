# patch_plugin.py - fixes the VPN race in flutter_v2ray_client 3.5.0 (Android VPN mode).
# Run from build_app/ (the Flutter project folder) AFTER `flutter pub get`.
# This version matches code with flexible whitespace, and when a critical patch
# cannot be found it prints the nearby code so the problem can be diagnosed.
import glob, json, os, re, sys
from pathlib import Path
from urllib.parse import unquote, urljoin, urlparse

PUB = os.environ.get('PUB_CACHE', os.path.expanduser('~/.pub-cache'))

MAVEN_CENTRAL_MIRROR = 'https://maven-central.storage-download.googleapis.com/maven2/'


def patch_android_plugin_buildscript_repositories():
    """Add the trusted Maven Central mirror to Android plugin buildscript repos.

    Flutter plugins can resolve their own AGP/Kotlin classpaths from nested
    buildscript.repositories blocks. settings.gradle mirrors do not override
    those per-plugin buildscript repositories.
    """
    config = Path('.dart_tool/package_config.json')
    if not config.is_file():
        raise RuntimeError('Pub package_config.json missing; run flutter pub get first')
    data = json.loads(config.read_text(encoding='utf-8'))
    patched = 0
    for package in data.get('packages', []):
        root_uri = package.get('rootUri')
        if not root_uri:
            continue
        resolved = urljoin(config.resolve().parent.as_uri() + '/', root_uri)
        parsed = urlparse(resolved)
        if parsed.scheme != 'file':
            continue
        package_root = Path(unquote(parsed.path)).resolve()
        android_root = package_root / 'android'
        if not android_root.is_dir():
            continue
        for gradle_file in android_root.rglob('build.gradle*'):
            if gradle_file.name not in ('build.gradle', 'build.gradle.kts'):
                continue
            source = gradle_file.read_text(encoding='utf-8')
            if MAVEN_CENTRAL_MIRROR in source:
                continue
            if gradle_file.name.endswith('.kts'):
                entry = f'\\n        maven {{ url = uri("{MAVEN_CENTRAL_MIRROR}") }}'
            else:
                entry = f'\\n        maven {{ url "{MAVEN_CENTRAL_MIRROR}" }}'
            pattern = r'(buildscript\\s*\\{\\s*repositories\\s*\\{)'
            updated, count = re.subn(
                pattern,
                lambda match: match.group(1) + entry,
                source,
                count=1,
                flags=re.S,
            )
            if count:
                gradle_file.write_text(updated, encoding='utf-8')
                patched += 1
                print('OK: Maven Central mirror added to plugin buildscript:', gradle_file)
    print(f'OK: patched {patched} Android plugin buildscript repository block(s)')


patch_android_plugin_buildscript_repositories()


def plugin_android_java_root():
    # Resolve the exact package selected by Pub. Never patch the first stale
    # copy found in ~/.pub-cache when multiple versions are present.
    config = Path('.dart_tool/package_config.json')
    if config.is_file():
        data = json.loads(config.read_text(encoding='utf-8'))
        for package in data.get('packages', []):
            if package.get('name') != 'flutter_v2ray_client':
                continue
            root_uri = package.get('rootUri')
            if not root_uri:
                break
            resolved = urljoin(config.resolve().parent.as_uri() + '/', root_uri)
            parsed = urlparse(resolved)
            if parsed.scheme != 'file':
                raise RuntimeError('Unsupported flutter_v2ray_client rootUri: ' + resolved)
            package_root = Path(unquote(parsed.path))
            java_root = package_root / 'android' / 'src' / 'main' / 'java'
            if java_root.is_dir():
                return str(java_root)
            raise RuntimeError('Resolved plugin has no Android Java source: ' + str(java_root))

    # Fallback only when package_config is unavailable; ambiguity is an error.
    roots = sorted(glob.glob(os.path.join(PUB, 'hosted/*/flutter_v2ray_client-3.5.0/android/src/main/java')))
    if not roots:
        roots = sorted(glob.glob(os.path.join(PUB, '**/flutter_v2ray_client-3.5.0/android/src/main/java'), recursive=True))
    roots = list(dict.fromkeys(roots))
    if len(roots) != 1:
        raise RuntimeError('Expected exactly one fallback flutter_v2ray_client 3.5.0 source, found %d' % len(roots))
    return roots[0]


try:
    base = plugin_android_java_root()
except Exception as exc:
    print('ERROR resolving flutter_v2ray_client Android source:', exc)
    sys.exit(1)
print('Plugin source folder:', base)


def patch_dart_source(name, transform):
    package_root = Path(base).parents[3]
    path = package_root / 'lib' / 'url' / name
    if not path.is_file():
        raise RuntimeError('Expected Dart parser source not found: ' + str(path))
    src = path.read_text(encoding='utf-8')
    updated = transform(src)
    if updated != src:
        path.write_text(updated, encoding='utf-8')
        print('OK: Dart parser hardening:', name)
    else:
        print('OK: Dart parser already hardened:', name)


def replace_once_or_already(src, old, new, label):
    if new in src:
        return src
    count = src.count(old)
    if count != 1:
        raise RuntimeError('%s: expected one source pattern, found %d' % (label, count))
    return src.replace(old, new, 1)


def patch_url_dart(src):
    if "import 'dart:io';" not in src:
        src = replace_once_or_already(src, "import 'dart:convert';", "import 'dart:convert';\nimport 'dart:io';", 'SNI IP validation import')
    helper = """  /// IP literals are not valid TLS SNI names.
  String fallbackSni(String candidate) {
    final value = candidate.trim();
    if (value.isEmpty || InternetAddress.tryParse(value) != null) return '';
    return value;
  }
"""
    if 'String fallbackSni(' not in src:
        src = replace_once_or_already(src, '  final String url;\n', '  final String url;\n\n' + helper, 'SNI hostname validator')
    start = src.find("    } else if (transport == 'ws') {")
    end = src.find("    } else if (transport == 'h2' || transport == 'http') {", start)
    if start < 0 or end < 0:
        if "'path': (path == null || path.isEmpty) ? '/' : path," in src:
            return src
        raise RuntimeError('WebSocket transport block not found')
    block = src[start:end]
    block = replace_once_or_already(
        block, "'path': path ?? ['/'],",
        "'path': (path == null || path.isEmpty) ? '/' : path,",
        'WebSocket path schema')
    return src[:start] + block + src[end:]


def patch_vmess_dart(src):
    src = replace_once_or_already(
        src, 'var raw = url.substring(8);',
        "var raw = url.substring(8).replaceAll('-', '+').replaceAll('_', '/');",
        'VMess URL-safe base64')
    src = replace_once_or_already(
        src, 'rawConfig = jsonDecode(utf8.decode(base64Decode(raw)));',
        "final decoded = jsonDecode(utf8.decode(base64Decode(raw)));\n"
        "      if (decoded is! Map) throw const FormatException('VMess payload must be a JSON object');\n"
        "      rawConfig = Map<String, dynamic>.from(decoded);\n"
        "      rawConfig['net'] = (rawConfig['net'] ?? 'tcp').toString();",
        'VMess map validation and TCP default')
    src = replace_once_or_already(
        src,
        "sni: rawConfig['sni']?.toString().isNotEmpty == true\n"
        "          ? rawConfig['sni'].toString()\n"
        "          : sni,",
        "sni: super.fallbackSni(\n"
        "          rawConfig['sni']?.toString().isNotEmpty == true\n"
        "              ? rawConfig['sni'].toString()\n"
        "              : (sni.isNotEmpty ? sni : (rawConfig['add'] ?? '').toString())),",
        'VMess SNI fallback')
    return src


def patch_vless_dart(src):
    return replace_once_or_already(
        src, "sni: uri.queryParameters['sni'] ?? sni,",
        "sni: super.fallbackSni(\n"
        "          (uri.queryParameters['sni'] ?? '').isNotEmpty\n"
        "              ? uri.queryParameters['sni']!\n"
        "              : (sni.isNotEmpty ? sni : uri.host)),",
        'VLESS SNI fallback')


def patch_trojan_dart(src):
    src = replace_once_or_already(
        src, "sni: uri.queryParameters['sni'] ?? sni,",
        "sni: super.fallbackSni(\n"
        "            (uri.queryParameters['sni'] ?? '').isNotEmpty\n"
        "                ? uri.queryParameters['sni']!\n"
        "                : (sni.isNotEmpty ? sni : uri.host)),",
        'Trojan SNI fallback')
    src = replace_once_or_already(src, "        sni: '',", "        sni: super.fallbackSni(uri.host),", 'Trojan endpoint SNI fallback')
    return src


def patch_shadowsocks_dart(src):
    src = replace_once_or_already(
        src, 'var raw = uri.userInfo;',
        "var raw = uri.userInfo.replaceAll('-', '+').replaceAll('_', '/');",
        'Shadowsocks URL-safe base64')
    old = """        method = methodpass.split(':')[0];
        password = methodpass.substring(method.length + 1);"""
    new = """        final separator = methodpass.indexOf(':');
        if (separator <= 0 || separator >= methodpass.length - 1) {
          throw const FormatException('Shadowsocks credentials must be method:password');
        }
        method = methodpass.substring(0, separator).trim();
        password = methodpass.substring(separator + 1);
        if (method.toLowerCase() == 'none' ||
            !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$').hasMatch(method) ||
            password.isEmpty) {
          throw const FormatException('Invalid Shadowsocks method/password');
        }"""
    src = replace_once_or_already(src, old, new, 'Shadowsocks credential validation')
    src = replace_once_or_already(
        src, '      } catch (_) {}',
        "      } catch (_) {\n        throw ArgumentError('Shadowsocks credentials are invalid');\n      }",
        'Shadowsocks malformed credential rejection')
    if "if (method == 'none' || password.isEmpty)" not in src:
        src = replace_once_or_already(
            src, '    if (uri.queryParameters.isNotEmpty) {',
            "    if (method == 'none' || password.isEmpty) {\n"
            "      throw ArgumentError('Shadowsocks method/password are required');\n"
            "    }\n\n    if (uri.queryParameters.isNotEmpty) {",
            'Shadowsocks required credentials')
    return src


try:
    patch_dart_source('url.dart', patch_url_dart)
    patch_dart_source('vmess.dart', patch_vmess_dart)
    patch_dart_source('vless.dart', patch_vless_dart)
    patch_dart_source('trojan.dart', patch_trojan_dart)
    patch_dart_source('shadowsocks.dart', patch_shadowsocks_dart)
except Exception as exc:
    print('ERROR hardening flutter_v2ray_client Dart parsers:', exc)
    sys.exit(1)



def find_java(name):
    """Find a Java file by its file name anywhere under the plugin source."""
    hits = glob.glob(os.path.join(base, '**', name), recursive=True)
    if len(hits) != 1:
        print(f'ERROR: expected one {name} under {base}, found {len(hits)}')
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

# 3) DELAYPOOL (حذف شد): این مرحله به ثابت DELAY_THREADS اشاره می‌کرد که در
#    flutter_v2ray_client 3.5.0 وجود ندارد (بررسی شد). تست تأخیر در پلاگین با
#    Libv2ray.measureOutboundDelay انجام می‌شود و صف جاوا ندارد؛ هشدار همیشگی بی‌فایده بود.


# 4) V3 FIXES (review items #8, #56, #86). Exact text replacements. Each one is skipped when
#    its new text is already present; a missing anchor is reported as an ERROR and stops the build.
def exact_replace(path, old, new, label):
    src = open(path, encoding='utf-8').read()
    if new in src:
        print(f'OK: {label} (already applied)')
        return
    n = src.count(old)
    if n != 1:
        print(f'ERROR: {label}: anchor found {n} times (expected 1).')
        show_context(src, old[:40])
        sys.exit(1)
    open(path, 'w', encoding='utf-8').write(src.replace(old, new, 1))
    print(f'OK: {label}')


v2_ctrl = find_java('V2rayController.java')
proxy_svc = find_java('V2rayProxyOnlyService.java')

# 4a) #56 + #8: the stop button targets the running service class, and uses the stop intent.
exact_replace(core, '''        Intent stopIntent;
        if (AppConfigs.V2RAY_CONNECTION_MODE == AppConfigs.V2RAY_CONNECTION_MODES.PROXY_ONLY) {
            stopIntent = new Intent(context, V2rayProxyOnlyService.class);
        } else if (AppConfigs.V2RAY_CONNECTION_MODE == AppConfigs.V2RAY_CONNECTION_MODES.VPN_TUN) {
            stopIntent = new Intent(context, V2rayVPNService.class);
        } else {
            return;
        }
        stopIntent.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE);
''', '''        // FIX #56: the service runs in its own process, where the static
        // AppConfigs.V2RAY_CONNECTION_MODE is not the value the app set. The stop button must
        // target the class that is actually running (VPN or proxy-only), so take it from here.
        Intent stopIntent = new Intent(context, context.getClass());
        stopIntent.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE);
''', 'V3 #56 stop intent from running class')

exact_replace(core, '''                    .addAction(0, v2rayConfig.NOTIFICATION_DISCONNECT_BUTTON_NAME, notificationContentPendingIntent)''',
'''                    // FIX #8: the disconnect button must stop the service, not open the app.
                    .addAction(0, v2rayConfig.NOTIFICATION_DISCONNECT_BUTTON_NAME, pendingIntent)''',
'V3 #8 disconnect button uses stop intent')

# 4b) #86: promoteForStop helper (5 s foreground rule for stops that arrive via startForegroundService)
exact_replace(core, '''    public boolean isV2rayCoreRunning() {''', '''    private static final String STOP_CHANNEL_ID = "king_vpn_stop";

    /**
     * FIX #86: a stop can arrive through startForegroundService (when startService is refused
     * in the background). Android then requires startForeground() within 5 seconds, even when
     * the service is only stopping. Call this at the start of the STOP branch.
     */
    public void promoteForStop(Service service) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                NotificationManager nm = (NotificationManager) service.getSystemService(Context.NOTIFICATION_SERVICE);
                if (nm != null) {
                    NotificationChannel ch = new NotificationChannel(
                            STOP_CHANNEL_ID, "VPN", NotificationManager.IMPORTANCE_MIN);
                    nm.createNotificationChannel(ch);
                }
            }
            Notification n = new NotificationCompat.Builder(service, STOP_CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.ic_lock_lock)
                    .setContentTitle("VPN")
                    .setPriority(NotificationCompat.PRIORITY_MIN)
                    .setOngoing(true)
                    .build();
            service.startForeground(NOTIFICATION_ID, n);
        } catch (Exception e) {
            Log.w("V2rayCoreManager", "promoteForStop failed", e);
        }
    }

    public boolean isV2rayCoreRunning() {''', 'V3 #86 promoteForStop helper')

# 4c) #86: StopV2ray falls back to startForegroundService when startService is refused
exact_replace(v2_ctrl, '''        stop_intent.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE);
        context.startService(stop_intent);
        AppConfigs.V2RAY_CONFIG = null;''', '''        stop_intent.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE);
        // FIX #86: startService is refused from the background on Android 8+ (IllegalStateException).
        // The service is already running, so a foreground start is allowed; the service promotes
        // itself in its STOP branch (promoteForStop).
        try {
            context.startService(stop_intent);
        } catch (IllegalStateException e) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(stop_intent);
            } else {
                throw e;
            }
        }
        AppConfigs.V2RAY_CONFIG = null;''', 'V3 #86 StopV2ray fallback')

# 4d) #86: both services promote themselves in the STOP branch
for svc_path, svc_name in ((vpn, 'VPN'), (proxy_svc, 'ProxyOnly')):
    exact_replace(svc_path, '''        } else if (startCommand.equals(AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE)) {
            V2rayCoreManager.getInstance().stopCore();''', '''        } else if (startCommand.equals(AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE)) {
            // FIX #86: satisfy the 5 s foreground rule for a stop started with startForegroundService
            V2rayCoreManager.getInstance().promoteForStop(this);
            V2rayCoreManager.getInstance().stopCore();''', f'V3 #86 {svc_name} STOP promotes')


# 5) FIX #49: the app is not excluded from the VPN (its own requests must go through the tunnel).
#    Only the core's outbound sockets are exempt, through protect() (see the protector below).
exact_replace(vpn, '''        // Keep this process outside the VPN so outbound sockets don't loop.
        try {
            builder.addDisallowedApplication(getPackageName());
        } catch (Exception e) {
            Log.w("V2rayVPNService", "Failed to exclude self from VPN", e);
        }
''', '''        // FIX #49: the app is NOT excluded from the tunnel. Its own requests (for example the
        // ASN lookup that uses DIRECT) must go through the VPN, otherwise they show the real IP.
        // The core's outbound sockets are exempt through protect() in the protector below.
''', 'V3 #49 do not exclude app from VPN')

# 5b) FIX #49: if the service reference is gone, protect must fail instead of returning true
#     (true without a real protect() sends the socket back into the tunnel: a loop).
exact_replace(core, '''                public boolean protect(long fd) {
                    if (v2rayServicesListener != null) {
                        return v2rayServicesListener.onProtect((int) fd);
                    }
                    return true;
                }''', '''                public boolean protect(long fd) {
                    if (v2rayServicesListener != null) {
                        return v2rayServicesListener.onProtect((int) fd);
                    }
                    // FIX #49: do not report success without protecting the socket
                    Log.w("V2rayCoreManager", "protect: no VPN service; socket not protected");
                    return false;
                }''', 'V3 #49 protector fails when service is missing')

print('patch_plugin.py finished OK')
