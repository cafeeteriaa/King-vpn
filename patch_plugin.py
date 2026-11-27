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
    """Add Maven Central mirror inside each plugin's own buildscript repositories.

    Do not treat a mirror in allprojects/dependencyResolutionManagement as
    proof that the buildscript classpath can see it: Gradle scopes are separate.
    """
    config = Path('.dart_tool/package_config.json')
    if not config.is_file():
        raise RuntimeError('Pub package_config.json missing; run flutter pub get first')
    data = json.loads(config.read_text(encoding='utf-8'))
    patched = 0
    inspected = 0

    def matching_brace(source, open_pos):
        depth = 0
        quote = None
        escaped = False
        for pos in range(open_pos, len(source)):
            char = source[pos]
            if quote:
                if escaped:
                    escaped = False
                elif char == '\\':
                    escaped = True
                elif char == quote:
                    quote = None
                continue
            if char in ("'", '"'):
                quote = char
            elif char == '{':
                depth += 1
            elif char == '}':
                depth -= 1
                if depth == 0:
                    return pos
        return -1

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
            pattern = r'buildscript\s*\{\s*repositories\s*\{'
            match = re.search(pattern, source, flags=re.S)
            if not match:
                continue
            inspected += 1
            repo_open = match.end() - 1
            repo_close = matching_brace(source, repo_open)
            if repo_close < 0:
                raise RuntimeError('Malformed buildscript.repositories block: ' + str(gradle_file))
            repo_body = source[repo_open + 1:repo_close]
            if MAVEN_CENTRAL_MIRROR in repo_body:
                continue
            if gradle_file.name.endswith('.kts'):
                entry = f'\n        maven {{ url = uri("{MAVEN_CENTRAL_MIRROR}") }}'
            else:
                entry = f'\n        maven {{ url "{MAVEN_CENTRAL_MIRROR}" }}'
            updated = source[:repo_open + 1] + entry + source[repo_open + 1:]
            gradle_file.write_text(updated, encoding='utf-8')
            patched += 1
            print('OK: Maven Central mirror added to plugin buildscript:', gradle_file)
    print(f'OK: inspected {inspected} plugin buildscript block(s); patched {patched}')


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


# 4e) Active FlutterV2ray path: do not continue with a partial IPv6 TUN.
#     The upstream plugin logs and swallows IPv6 address/route failures, then may establish
#     only IPv4. Since this plugin path is the app default, fail the interface setup closed.
exact_replace(vpn, '''        // Force IPv4 path: sinkhole IPv6 so apps don't bypass a broken dual-stack route.
        try {
            builder.addAddress("fd00:1:fd00:1:fd00:1:fd00:1", 126);
            builder.addRoute("::", 0);
        } catch (Exception e) {
            Log.w("V2rayVPNService", "IPv6 sinkhole not supported", e);
        }''', '''        // FIX: IPv6 is part of the default tunnel contract. Never establish an IPv4-only
        // interface after IPv6 address/route setup failed, because that can leak IPv6 traffic.
        try {
            builder.addAddress("fd00:1:fd00:1:fd00:1:fd00:1", 126);
            builder.addRoute("::", 0);
        } catch (Exception e) {
            Log.e("V2rayVPNService", "IPv6 TUN setup failed; refusing partial VPN", e);
            return false;
        }''', 'Active FlutterV2ray path refuses partial IPv6 TUN');

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



# 6) Lifecycle hardening for the active 3.5.0 plugin services.
# Promote before any TUN/core work, and make every stop/failure release the service.
# The generic notification is replaced by the rich connection notification after startup.
exact_replace(core, '''    public void promoteForStop(Service service) {
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
    }''', '''    public boolean promoteForStop(Service service) {
        try {
            if (service == null) return false;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                NotificationManager nm = (NotificationManager) service.getSystemService(Context.NOTIFICATION_SERVICE);
                if (nm == null) return false;
                NotificationChannel ch = new NotificationChannel(
                        STOP_CHANNEL_ID, "VPN", NotificationManager.IMPORTANCE_MIN);
                nm.createNotificationChannel(ch);
            }
            Notification n = new NotificationCompat.Builder(service, STOP_CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.ic_lock_lock)
                    .setContentTitle("VPN")
                    .setPriority(NotificationCompat.PRIORITY_MIN)
                    .setOngoing(true)
                    .build();
            service.startForeground(NOTIFICATION_ID, n);
            return true;
        } catch (Exception e) {
            Log.e("V2rayCoreManager", "Foreground promotion failed", e);
            return false;
        }
    }''', 'Lifecycle foreground promotion reports success/failure');

# StartCore: reject invalid state before timer creation; all failed starts reset state/timer.
exact_replace(core, '''    public boolean startCore(final V2rayConfig v2rayConfig, int tunFd) {
        makeDurationTimer(v2rayServicesListener.getService().getApplicationContext(),
                v2rayConfig.ENABLE_TRAFFIC_STATICS);
        V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_CONNECTING;
        if (!isLibV2rayCoreInitialized) {
            Log.e(V2rayCoreManager.class.getSimpleName(),
                    "startCore failed => LibV2rayCore should be initialize before start.");
            return false;
        }''', '''    private boolean failStart(String reason) {
        Log.e(V2rayCoreManager.class.getSimpleName(), "startCore failed => " + reason);
        try {
            if (coreController != null && coreController.getIsRunning()) {
                coreController.stopLoop();
            }
        } catch (Exception stopError) {
            Log.w(V2rayCoreManager.class.getSimpleName(), "Failed to stop partially started core", stopError);
        }
        if (countDownTimer != null) {
            countDownTimer.cancel();
            countDownTimer = null;
        }
        V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_DISCONNECTED;
        SERVICE_DURATION = "00:00:00";
        seconds = 0;
        minutes = 0;
        hours = 0;
        uploadSpeed = 0;
        downloadSpeed = 0;
        try {
            sendDisconnectedBroadCast();
        } catch (Exception e) {
            Log.w("V2rayCoreManager", "Failed to publish failed-start state", e);
        }
        return false;
    }

    public boolean startCore(final V2rayConfig v2rayConfig, int tunFd) {
        if (v2rayConfig == null || v2rayServicesListener == null ||
                v2rayServicesListener.getService() == null) {
            return failStart("missing config or service listener");
        }
        if (countDownTimer != null) {
            countDownTimer.cancel();
            countDownTimer = null;
        }
        V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_CONNECTING;
        if (!isLibV2rayCoreInitialized) {
            return failStart("LibV2rayCore is not initialized");
        }
        // Duration reporting starts only after the native core is confirmed running.''', 'P1-27 start failure state and timer reset');

exact_replace(core, '''            if (coreController == null) {
                Log.e(V2rayCoreManager.class.getSimpleName(), "startCore failed => coreController is null.");
                return false;
            }''', '''            if (coreController == null) {
                return failStart("coreController is null");
            }''', 'P1-27 null core controller cleanup');

exact_replace(core, '''        } catch (Exception e) {
            Log.e(V2rayCoreManager.class.getSimpleName(), "startCore failed =>", e);
            return false;
        }
        return true;
    }

    public void stopCore()''', '''        } catch (Exception e) {
            Log.e(V2rayCoreManager.class.getSimpleName(), "startCore failed =>", e);
            return failStart("core startup exception");
        }
        return true;
    }

    public void stopCore()''', 'P1-27 exception cleanup');

# A native startLoop call can return without throwing while the controller is not
# actually running. Never publish CONNECTED or report a successful service start
# unless the core's own running state confirms that startup completed.
# The duration ticker should wake once per second for a two-hour interval, not
# restart every 7.2 seconds. Use elapsed-time boundaries so displayed time does
# not roll over one second/minute early.
exact_replace(core, '''        countDownTimer = new CountDownTimer(7200, 1000) {''',
'''        countDownTimer = new CountDownTimer(7200L * 1000L, 1000L) {''',
'P1-35 duration timer interval is two hours');

exact_replace(core, '''                seconds++;
                if (seconds == 59) {
                    minutes++;
                    seconds = 0;
                }
                if (minutes == 59) {
                    minutes = 0;
                    hours++;
                }
                if (hours == 23) {
                    hours = 0;
                }''', '''                seconds++;
                if (seconds >= 60) {
                    minutes++;
                    seconds = 0;
                }
                if (minutes >= 60) {
                    minutes = 0;
                    hours++;
                }
                if (hours >= 24) {
                    hours = 0;
                }''', 'P1-35 duration clock uses full minute and day boundaries');

exact_replace(core, '''            coreController.startLoop(config, tunFd);
            V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_CONNECTED;
            if (isV2rayCoreRunning()) {
                showNotification(v2rayConfig);
            }''', '''            coreController.startLoop(config, tunFd);
            if (!isV2rayCoreRunning()) {
                return failStart("native core did not enter running state");
            }
            synchronized (durationTimerLock) {
                V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_CONNECTED;
                makeDurationTimer(v2rayServicesListener.getService().getApplicationContext(),
                        v2rayConfig.ENABLE_TRAFFIC_STATICS);
            }
            showNotification(v2rayConfig);''', 'P1-34 verify native core running before connected');


# Stop the duration ticker before publishing DISCONNECTED. Cancelling after
# the broadcast leaves a small race in which onTick can publish stale CONNECTING
# or CONNECTED state after the disconnect event.
exact_replace(core, '''    private void sendDisconnectedBroadCast() {
        V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_DISCONNECTED;''', '''    private void sendDisconnectedBroadCast() {
        if (countDownTimer != null) {
            countDownTimer.cancel();
            countDownTimer = null;
        }
        V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_DISCONNECTED;''', 'P1-36 cancel duration ticker before disconnect broadcast');

exact_replace(core, '''        if (countDownTimer != null) {
            countDownTimer.cancel();
        }
    }

    private String createNotificationChannelID''', '''    }

    private String createNotificationChannelID''', 'P1-36 remove late duration ticker cancellation');



# P1-37: serialize duration timer callbacks and disconnect under one lock.
exact_replace(core, '''    private CountDownTimer countDownTimer;''',
'''    private CountDownTimer countDownTimer;
    private final Object durationTimerLock = new Object();''',
'P1-37 duration timer lifecycle lock');

exact_replace(core, '''    private void makeDurationTimer(final Context context, final boolean enable_traffic_statics) {
        countDownTimer = new CountDownTimer(7200L * 1000L, 1000L) {''',
'''    private void makeDurationTimer(final Context context, final boolean enable_traffic_statics) {
        synchronized (durationTimerLock) {
            if (V2RAY_STATE != AppConfigs.V2RAY_STATES.V2RAY_CONNECTED ||
                    !isV2rayCoreRunning()) {
                return;
            }
            if (countDownTimer != null) {
                countDownTimer.cancel();
                countDownTimer = null;
            }
            countDownTimer = new CountDownTimer(7200L * 1000L, 1000L) {''',
'P1-37 timer creation serialized and state-gated');

exact_replace(core, '''            public void onTick(long millisUntilFinished) {

                seconds++;''',
'''            public void onTick(long millisUntilFinished) {
                synchronized (durationTimerLock) {
                    if (countDownTimer != this ||
                            V2RAY_STATE != AppConfigs.V2RAY_STATES.V2RAY_CONNECTED ||
                            !isV2rayCoreRunning()) {
                        return;
                    }
                    seconds++;''',
'P1-37 tick verifies timer identity and live connection');

exact_replace(core, '''                } catch (Exception e) {
                    Log.w("V2rayCoreManager", "Failed to send connection info broadcast", e);
                }
            }

            public void onFinish() {
                countDownTimer.cancel();
                if (V2rayCoreManager.getInstance().isV2rayCoreRunning())
                    makeDurationTimer(context, enable_traffic_statics);
            }
        }.start();
    }

    /**
     * Parses''',
'''                } catch (Exception e) {
                    Log.w("V2rayCoreManager", "Failed to send connection info broadcast", e);
                }
                }
            }

            public void onFinish() {
                synchronized (durationTimerLock) {
                    if (countDownTimer != this) {
                        return;
                    }
                    countDownTimer = null;
                    if (V2RAY_STATE == AppConfigs.V2RAY_STATES.V2RAY_CONNECTED &&
                            isV2rayCoreRunning()) {
                        makeDurationTimer(context, enable_traffic_statics);
                    }
                }
            }
        }.start();
        }
    }

    /**
     * Parses''',
'P1-37 finish callback is identity-safe and serialized');

exact_replace(core, '''    private void sendDisconnectedBroadCast() {
        if (countDownTimer != null) {
            countDownTimer.cancel();
            countDownTimer = null;
        }
        V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_DISCONNECTED;''',
'''    private void sendDisconnectedBroadCast() {
        synchronized (durationTimerLock) {
            if (countDownTimer != null) {
                countDownTimer.cancel();
                countDownTimer = null;
            }
            V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_DISCONNECTED;
''',
'P1-37 disconnect serializes timer cancellation and state change');


# VPN service: promote before establishing TUN / starting Xray.
exact_replace(vpn, '''            if (v2rayConfig == null) {
                Log.w("V2rayVPNService", "V2RAY_CONFIG is null, cannot start service");
                this.onDestroy();
                return START_NOT_STICKY;
            }
            if (V2rayCoreManager.getInstance().isV2rayCoreRunning()) {''', '''            if (v2rayConfig == null) {
                Log.w("V2rayVPNService", "V2RAY_CONFIG is null, cannot start service");
                stopAllProcess();
                return START_NOT_STICKY;
            }
            if (!V2rayCoreManager.getInstance().promoteForStop(this)) {
                Log.e("V2rayVPNService", "Foreground promotion failed; refusing to start core");
                stopAllProcess();
                return START_NOT_STICKY;
            }
            if (V2rayCoreManager.getInstance().isV2rayCoreRunning()) {''', 'P1-31 VPN foreground before TUN/core startup');

# Proxy-only service: add an idempotent cleanup helper and promote before core startup.
exact_replace(proxy_svc, '''            if (v2rayConfig == null) {
                Log.w("V2rayProxyOnlyService", "V2RAY_CONFIG is null, cannot start service");
                this.onDestroy();
                return START_NOT_STICKY;
            }
            if (V2rayCoreManager.getInstance().isV2rayCoreRunning()) {''', '''            if (v2rayConfig == null) {
                Log.w("V2rayProxyOnlyService", "V2RAY_CONFIG is null, cannot start service");
                stopAllProcess();
                return START_NOT_STICKY;
            }
            if (!V2rayCoreManager.getInstance().promoteForStop(this)) {
                Log.e("V2rayProxyOnlyService", "Foreground promotion failed; refusing to start core");
                stopAllProcess();
                return START_NOT_STICKY;
            }
            if (V2rayCoreManager.getInstance().isV2rayCoreRunning()) {''', 'P1-31 proxy foreground before core startup');

exact_replace(proxy_svc, '''    @Override
    public void onDestroy() {
        super.onDestroy();
    }''', '''    private void stopAllProcess() {
        try {
            stopForeground(true);
        } catch (Exception e) {
            Log.w("V2rayProxyOnlyService", "stopForeground cleanup failed", e);
        }
        try {
            stopSelf();
        } catch (Exception e) {
            Log.w("V2rayProxyOnlyService", "stopSelf cleanup failed", e);
        }
    }

    @Override
    public void onDestroy() {
        // The proxy-only service shares its process with the native core. If Android
        // destroys this service outside the normal STOP command, release the core too.
        try {
            if (V2rayCoreManager.getInstance().isV2rayCoreRunning()) {
                V2rayCoreManager.getInstance().stopCore();
            }
        } catch (Exception e) {
            Log.e("V2rayProxyOnlyService", "onDestroy core cleanup failed", e);
        }
        try {
            stopForeground(true);
        } catch (Exception e) {
            Log.w("V2rayProxyOnlyService", "onDestroy foreground cleanup failed", e);
        }
        super.onDestroy();
    }''', 'P1-29 proxy-only service cleanup helper');

# Do not invoke lifecycle callbacks directly; request normal service shutdown instead.
def replace_all_service_calls(path, label):
    src = open(path, encoding='utf-8').read()
    count = src.count('this.onDestroy();')
    if count == 0:
        if 'stopAllProcess();' in src:
            print('OK: ' + label + ' (already applied)')
            return
        print('ERROR: ' + label + ': expected onDestroy calls not found')
        sys.exit(1)
    open(path, 'w', encoding='utf-8').write(src.replace('this.onDestroy();', 'stopAllProcess();'))
    print('OK: ' + label + ' (' + str(count) + ' call sites)')

replace_all_service_calls(vpn, 'P1-29 VPN direct onDestroy calls replaced')
replace_all_service_calls(proxy_svc, 'P1-29 proxy direct onDestroy calls replaced');

# STOP must release the service even when the native core is already down.
for svc_path, svc_name in ((vpn, 'VPN'), (proxy_svc, 'ProxyOnly')):
    exact_replace(svc_path, '''            V2rayCoreManager.getInstance().stopCore();
            AppConfigs.V2RAY_CONFIG = null;''', '''            try {
                V2rayCoreManager.getInstance().stopCore();
            } finally {
                AppConfigs.V2RAY_CONFIG = null;
                stopAllProcess();
            }
            return START_NOT_STICKY;''', 'P1-28 ' + svc_name + ' STOP always cleans up service');

# VPN permission revocation must always close the TUN and stop the service.
exact_replace(vpn, '''    public void onRevoke() {
        try {
            V2rayCoreManager.getInstance().stopCore();
        } catch (Exception e) {
            stopAllProcess();
        }
    }''', '''    public void onRevoke() {
        try {
            V2rayCoreManager.getInstance().stopCore();
        } catch (Exception e) {
            Log.w("V2rayVPNService", "Core stop failed after VPN permission revoke", e);
        } finally {
            stopAllProcess();
        }
    }''', 'P1-30 VPN revoke always releases TUN/service');



# 7) Delay probe crosses the plugin's :RunSoLibV2RayDaemon process boundary.
# The complete function replacement below handles receiver registration and
# uses the API-33 flagged overload only where Android requires it.

exact_replace(v2_ctrl, '''import android.os.Build;''', '''import android.os.Build;

import android.util.Log;''', 'P1-33 controller Log import');

exact_replace(v2_ctrl, '''        final long[] delay = { -1 };

        final CountDownLatch latch = new CountDownLatch(1);
        check_delay.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.MEASURE_DELAY);
        context.startService(check_delay);
        BroadcastReceiver receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context arg0, Intent arg1) {
                String delayString = arg1.getExtras().getString("DELAY");
                delay[0] = Long.parseLong(delayString);
                context.unregisterReceiver(this);
                latch.countDown();
            }
        };

        // Use package-specific intent filter to isolate broadcasts per app
        String packageName = context.getPackageName();
        IntentFilter delayIntentFilter = new IntentFilter(packageName + ".CONNECTED_V2RAY_SERVER_DELAY");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.registerReceiver(receiver, delayIntentFilter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            context.registerReceiver(receiver, delayIntentFilter);
        }

        try {
            boolean received = latch.await(3000, TimeUnit.MILLISECONDS);
            if (!received) {
                return -1;
            }
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
        return delay[0];''', '''        final long[] delay = { -1 };
        final CountDownLatch latch = new CountDownLatch(1);
        check_delay.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.MEASURE_DELAY);
        check_delay.putExtra("DELAY_URL", AppConfigs.DELAY_URL);

        BroadcastReceiver receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context arg0, Intent arg1) {
                String delayString = arg1.getStringExtra("DELAY");
                try {
                    if (delayString != null) delay[0] = Long.parseLong(delayString);
                } catch (NumberFormatException e) {
                    Log.w("V2rayController", "Invalid connected delay response", e);
                } finally {
                    latch.countDown();
                }
            }
        };

        // Register before dispatch so a fast service response cannot be missed.
        String packageName = context.getPackageName();
        IntentFilter delayIntentFilter = new IntentFilter(packageName + ".CONNECTED_V2RAY_SERVER_DELAY");
        final boolean[] receiverRegistered = { false };
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, delayIntentFilter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            context.registerReceiver(receiver, delayIntentFilter);
        }
        receiverRegistered[0] = true;

        try {
            context.startService(check_delay);
            boolean received = latch.await(3000, TimeUnit.MILLISECONDS);
            return received ? delay[0] : -1;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return -1;
        } finally {
            if (receiverRegistered[0]) {
                try {
                    context.unregisterReceiver(receiver);
                } catch (IllegalArgumentException ignored) {
                    // Receiver was already unregistered by Android during teardown.
                }
            }
        }''', 'P1-33 delay URL handoff and receiver-before-dispatch');

exact_replace(vpn, '''        } else if (startCommand.equals(AppConfigs.V2RAY_SERVICE_COMMANDS.MEASURE_DELAY)) {
            new Thread(() -> {''', '''        } else if (startCommand.equals(AppConfigs.V2RAY_SERVICE_COMMANDS.MEASURE_DELAY)) {
            // DELAY_URL is process-local; restore it from the Intent sent by the app process.
            AppConfigs.DELAY_URL = intent.getStringExtra("DELAY_URL");
            new Thread(() -> {''', 'P1-33 VPN service receives delay URL');

exact_replace(proxy_svc, '''        } else if (startCommand.equals(AppConfigs.V2RAY_SERVICE_COMMANDS.MEASURE_DELAY)) {
            new Thread(() -> {''', '''        } else if (startCommand.equals(AppConfigs.V2RAY_SERVICE_COMMANDS.MEASURE_DELAY)) {
            // DELAY_URL is process-local; restore it from the Intent sent by the app process.
            AppConfigs.DELAY_URL = intent.getStringExtra("DELAY_URL");
            new Thread(() -> {''', 'P1-33 ProxyOnly service receives delay URL');

print('patch_plugin.py finished OK')


# P1-38: hold the shared lifecycle lock until the full DISCONNECTED broadcast
# completes, and serialize CONNECTED state publication with timer creation.
exact_replace(core, '''        }
    }

    private String createNotificationChannelID''',
'''        }
        }
    }

    private String createNotificationChannelID''',
'P1-38 keep disconnect lock through broadcast');


# P1-39: publish the plugin-owned VPN state across the service process boundary.
# V2rayVPNService runs in :RunSoLibV2RayDaemon, so static fields are NOT shared
# with MainActivity. Persist an atomic state record and validate the service PID.
exact_replace(vpn, '''import android.util.Log;''', '''import android.util.Log;
import android.content.Context;
import android.util.AtomicFile;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;''', 'P1-39 cross-process state imports');

exact_replace(vpn, '''    private boolean vpnInterfaceReady = false;''', '''    private boolean vpnInterfaceReady = false;
    private static volatile boolean kingVpnTunnelActive = false;
    private static final String KING_VPN_STATE_FILE = "king_vpn_tunnel_state";

    private void setKingVpnTunnelActive(boolean active) {
        kingVpnTunnelActive = active;
        AtomicFile state = new AtomicFile(new File(getFilesDir(), KING_VPN_STATE_FILE));
        FileOutputStream stream = null;
        try {
            stream = state.startWrite();
            stream.write((active + "\\n" + android.os.Process.myPid()).getBytes("UTF-8"));
            state.finishWrite(stream);
        } catch (IOException e) {
            if (stream != null) state.failWrite(stream);
            Log.e("V2rayVPNService", "Unable to persist plugin tunnel state", e);
        }
    }

    public static boolean isKingVpnTunnelActive(Context context) {
        AtomicFile state = new AtomicFile(new File(context.getFilesDir(), KING_VPN_STATE_FILE));
        try (FileInputStream input = state.openRead()) {
            byte[] bytes = new byte[128];
            int count = input.read(bytes);
            if (count <= 0) return false;
            String[] fields = new String(bytes, 0, count, "UTF-8").trim().split("\\n");
            if (fields.length != 2 || !"true".equals(fields[0])) return false;
            int pid = Integer.parseInt(fields[1]);
            File cmdline = new File("/proc/" + pid + "/cmdline");
            try (FileInputStream process = new FileInputStream(cmdline)) {
                ByteArrayOutputStream output = new ByteArrayOutputStream();
                byte[] chunk = new byte[256];
                int read;
                while ((read = process.read(chunk)) > 0) output.write(chunk, 0, read);
                String processName = new String(output.toByteArray(), "UTF-8");
                return processName.contains(context.getPackageName() + ":RunSoLibV2RayDaemon");
            }
        } catch (Exception e) {
            return false;
        }
    }''', 'P1-39 process-safe plugin tunnel state');

exact_replace(vpn, '''        if (startCommand.equals(AppConfigs.V2RAY_SERVICE_COMMANDS.START_SERVICE)) {
            v2rayConfig =''', '''        if (startCommand.equals(AppConfigs.V2RAY_SERVICE_COMMANDS.START_SERVICE)) {
            setKingVpnTunnelActive(false);
            v2rayConfig =''', 'P1-39 clear stale state before new start');

exact_replace(vpn, '''                Log.i("V2rayVPNService", "onStartCommand success => native TUN core started.");''', '''                // Publish only after establish() and native Xray startup both succeeded.
                setKingVpnTunnelActive(true);
                Log.i("V2rayVPNService", "onStartCommand success => native TUN core started.");''', 'P1-39 publish active state after core start');

exact_replace(vpn, '''    private void stopAllProcess() {
        stopForeground(true);''', '''    private void stopAllProcess() {
        setKingVpnTunnelActive(false);
        stopForeground(true);''', 'P1-39 clear active state on stop');

exact_replace(vpn, '''    public void onDestroy() {
        Log.i("V2rayVPNService", "onDestroy called - cleaning up resources");''', '''    public void onDestroy() {
        setKingVpnTunnelActive(false);
        Log.i("V2rayVPNService", "onDestroy called - cleaning up resources");''', 'P1-39 clear active state on destroy');

exact_replace(vpn, '''    public void onRevoke() {
        try {''', '''    public void onRevoke() {
        setKingVpnTunnelActive(false);
        try {''', 'P1-39 clear active state on revoke');
