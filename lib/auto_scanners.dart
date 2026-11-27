part of 'main.dart';

// AUTOSCAN: اسکنر خودکار SNI و پورت. بدون ورودی دستی؛ IPهای تمیز پوشه‌ی جهانی را تست می‌کند
// و نتیجه را همان‌جا ذخیره می‌کند (کلیدهای 'sni' و 'port').
const List<String> kAutoSniDomains = [
  'www.google.com', 'www.youtube.com', 'www.instagram.com', 'www.microsoft.com',
  'www.apple.com', 'www.cloudflare.com', 'speed.cloudflare.com', 'www.digikala.com',
  'www.aparat.com', 'www.snapp.ir', 'www.divar.ir', 'www.wikipedia.org',
  'www.amazon.com', 'dl.google.com', 'www.whatsapp.com', 'www.telegram.org',
  'www.spotify.com', 'www.github.com',
];
const List<int> kAutoPorts = [443, 8443, 2053, 2083, 2087, 2096];

bool _autoScanRunning = false;
bool _autoScanStop = false;

// SNI must be a DNS hostname; an IP literal is never a valid SNI candidate.
bool _autoValidSni(String value) {
  final host = value.trim().toLowerCase().replaceFirst(RegExp(r'\\.
  final sw = Stopwatch()..start();
  Socket? raw;
  SecureSocket? secure;
  try {
    raw = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
    secure = await SecureSocket.secure(raw,
        host: sni)
        .timeout(const Duration(seconds: 4));
    return sw.elapsedMilliseconds;
  } catch (_) {
    return null;
  } finally {
    try { secure?.destroy(); } catch (e, st) { logError(e, st); }
    try { raw?.destroy(); } catch (e, st) { logError(e, st); }
  }
}

// ALPN (پروتکل لایه‌ی TLS): خروجی خود نام پروتکل است، مثل h2 یا http/1.1
Future<String?> _autoAlpnOk(String ip, int port, String sni, String alpn) async {
  Socket? raw;
  SecureSocket? secure;
  try {
    raw = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
    secure = await SecureSocket.secure(raw,
        host: sni,
        supportedProtocols: [alpn])
        .timeout(const Duration(seconds: 4));
    return secure.selectedProtocol;
  } catch (_) {
    return null;
  } finally {
    try { secure?.destroy(); } catch (e, st) { logError(e, st); }
    try { raw?.destroy(); } catch (e, st) { logError(e, st); }
  }
}

Future<bool> _autoPortOk(String ip, int port) async {
  try {
    final s = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 1500));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> autoScanRun(void Function(String) say,
    {bool Function()? isVpnActive,
    bool Function()? isVpnWanted,
    List<Server> configuredServers = const <Server>[],
    List<String> frontSnis = const <String>[]}) async {
  bool vpnActive() => isVpnActive?.call() ?? false;
  bool vpnWanted() => isVpnWanted?.call() ?? false;
  // Scanning through an active VPN tunnel can produce misleading direct-IP results
  // and compete with the live tunnel; keep diagnostics idle until it is disconnected.
  if (vpnActive() || vpnWanted()) {
    say('برای جلوگیری از اختلال، ابتدا VPN را قطع کنید');
    return;
  }
  if (_autoScanRunning || dnsxManualBusy || _dnsxAutoBusy || ipAutoBusy || _natRangeScanBusy) {
    say('اسکن دیگری در حال اجراست');
    return;
  }
  _autoScanRunning = true;
  dnsxManualBusy = true;
  _autoScanStop = false;
  final scanNationalMode = nationalMode;
  bool cancelled() =>
      _autoScanStop || vpnActive() || vpnWanted() || nationalMode != scanNationalMode;
  String cancellationMessage() =>
      (vpnActive() || vpnWanted())
          ? 'با شروع اتصال VPN، اسکن برای جلوگیری از تداخل متوقف شد؛ نتایج ناقص ذخیره نشد'
          : 'اسکن متوقف شد؛ نتایج ناقص ذخیره نشد';
  try {
    if (scanNationalMode) {
      await natNationalIpMemLoad();
      await natNationalDomMemLoad();
      await natRelayHostsLoad();
    } else {
      await goldLoad();
      await natIpMemLoad();
      await natDomMemLoad();
    }
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // Discover templates from the independent public source inventory as well
    // as user-provided profiles. Keep protocol/credential-distinct links.
    final sourceTemplates = <Server>[];
    try {
      if (scanNationalMode) {
        sourceTemplates.addAll(await natHotAll(fetch: false));
      } else {
        sourceTemplates.addAll(await fetchServers(stop: () => cancelled()));
      }
    } catch (error, stackTrace) {
      logError(error, stackTrace);
    }
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    final templates = <Server>[];
    final templateKeys = <String>{};
    for (final server in [...configuredServers, ...sourceTemplates]) {
      if (templateKeys.add(server.link.trim())) templates.add(server);
    }
    if (templates.isEmpty) {
      say('هیچ قالب مستقلی از منابع یا پروفایل‌های کاربر برای بررسی پیدا نشد');
      return;
    }

    // Build an exact endpoint inventory. Resolve hostnames from fresh feed
    // templates and saved domain memories; never expand neighboring subnets.
    final ipSet = <String>{
      if (scanNationalMode) ...natNationalIpMemHosts() else ..._goldIps.keys,
      if (!scanNationalMode) ...natIpMemHosts(),
      if (scanNationalMode) ...natScanHits,
    };
    final domainSources = <String>{
      if (scanNationalMode) ...natNationalDomMemHosts(),
      if (scanNationalMode) ...natRelayHosts,
      if (!scanNationalMode)
        for (final entry in natDomMem)
          (entry['h'] ?? '').toString(),
    };
    final sniCandidates = <String>{
      ...kAutoSniDomains,
      ...frontSnis,
      for (final server in templates) server.sni,
      for (final server in templates)
        if (!server.isIp) server.host,
      ...domainSources,
    };
    final domainHosts = <String>{...domainSources};
    for (final server in templates) {
      if (server.isIp) {
        ipSet.add(server.host);
      } else {
        domainHosts.add(server.host);
      }
    }
    final resolveHosts = domainHosts
        .map((host) => host.trim())
        .where((host) => host.isNotEmpty && InternetAddress.tryParse(host) == null)
        .toSet()
        .toList(growable: false);
    // Bounded DNS fan-out controls transient sockets, not total source coverage.
    for (var offset = 0; offset < resolveHosts.length; offset += 16) {
      if (cancelled()) break;
      final batch = resolveHosts.skip(offset).take(16).toList(growable: false);
      final resolved = await Future.wait<List<String>>(batch.map((host) async {
        try {
          return await nipResolveAll(host)
              .timeout(const Duration(seconds: 4));
        } catch (error, stackTrace) {
          logError(error, stackTrace);
          return const <String>[];
        }
      }));
      for (final addresses in resolved) {
        ipSet.addAll(addresses);
      }
    }
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    final ips = ipSet
        .map((ip) => ip.trim())
        .where((ip) => InternetAddress.tryParse(ip) != null)
        .toList(growable: false);
    final sniDomains = sniCandidates
        .map((value) => value.trim().toLowerCase())
        .where(_autoValidSni)
        .toSet()
        .toList(growable: false);
    if (ips.isEmpty) {
      say('هیچ IP دقیقی از منابع مستقل یا حافظهٔ همین حالت برای بررسی وجود ندارد');
      return;
    }
    final ports = <int>{
      ...kAutoPorts,
      ...natAutoPorts(templates),
      for (final server in templates)
        if (server.port >= 1 && server.port <= 65535) server.port,
    }.toList()..sort();
    if (ports.isEmpty) {
      say('هیچ پورت معتبر از منابع پیدا نشد');
      return;
    }
    say('بررسی منابع مستقل و پروفایل‌ها: ${templates.length} قالب • ${ips.length} IP دقیق • ${sniDomains.length} نام SNI • ${ports.length} پورت');
    // SNI: خروجی خود دامنه‌هاست. هر دامنه یک بار؛ به محض یک IP سالم، همان دامنه ثبت می‌شود
    final sniHits = <String>[];
    var n = 0;
    sniLoop:
    for (final d in sniDomains) {
      n++;
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break sniLoop;
      }
      var ok = false;
      for (final port in ports) {
        for (final ip in ips) {
          if (cancelled()) break sniLoop;
          if (await _autoSniOk(ip, port, d) != null) {
            ok = true;
            break;
          }
        }
        if (ok) break;
      }
      if (ok) sniHits.add(d);
      say('SNI $n/${sniDomains.length} • گواهی معتبر: ${sniHits.length}');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // پورت: خروجی خود شماره‌ی پورت است. هر پورت یک بار؛ به محض یک IP سالم، همان پورت ثبت می‌شود
    final portHits = <String>[];
    final nationalPortEndpoints = <String>[];
    var m = 0;
    portLoop:
    for (final p in ports) {
      m++;
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break portLoop;
      }
      var ok = false;
      for (final ip in ips) {
        if (cancelled()) break portLoop;
        if (await _autoPortOk(ip, p)) {
          ok = true;
          if (scanNationalMode) nationalPortEndpoints.add('$ip|$p');
          else break;
        }
      }
      if (ok) portHits.add('$p');
      say('پورت $m/${ports.length} • پاسخ TCP: ${portHits.length}');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // TLS/ALPN: خروجی نام پروتکل‌های TLS است؛ روی اولین دامنه‌ی سالم (یا پیش‌فرض) تست می‌شود
    final tlsHits = <String>[];
    final tlsSni = sniHits.isNotEmpty ? sniHits.first : 'www.google.com';
    for (final alpn in const ['h2', 'http/1.1']) {
      if (cancelled()) break;
      var ok = false;
      for (final port in ports) {
        for (final ip in ips) {
          if (cancelled()) break;
          final sel = await _autoAlpnOk(ip, port, tlsSni, alpn);
          if (sel != null && sel.isNotEmpty) {
            if (!tlsHits.contains(sel)) tlsHits.add(sel);
            ok = true;
            break;
          }
        }
        if (ok) break;
      }
      if (ok) say('TLS: $alpn ✓');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    // Commit the three result groups together only after every scan phase completes.
    if (scanNationalMode) {
      for (final domain in sniHits) {
        if (cancelled()) return;
        await natNationalDomMemSave(domain, 443);
      }
      for (final endpoint in nationalPortEndpoints) {
        if (cancelled()) return;
        final ip = endpoint.split('|').first;
        // TCP-open is only a candidate; keep it out of the verified IP memory.
        natScanHits.add(ip);
      }
    } else {
      final saved = await goldAddScans(
        {'tls': tlsHits, 'sni': sniHits, 'port': portHits},
        shouldAbort: () => cancelled(),
      );
      if (!saved) {
        say(cancellationMessage());
        return;
      }
    }
    say('تمام شد: ${sniHits.length} نام دارای گواهی معتبر و ${portHits.length} پورت پاسخ‌گو در ${scanNationalMode ? 'حافظه مستقل نت ملی' : 'پوشه جهانی'} ذخیره شد');
  } catch (e, stk) {
    logError(e, stk);
    say('خطا در اسکن خودکار');
  } finally {
    _autoScanRunning = false;
    dnsxManualBusy = false;
  }
}

Future<void> autoScanSheet(BuildContext context,
    {bool Function()? isVpnActive,
    bool Function()? isVpnWanted,
    List<Server> configuredServers = const <Server>[],
    List<String> frontSnis = const <String>[]}) async {
  var status = _autoScanRunning ? 'در حال اجرا...' : 'آماده';
  var open = true;
  StateSetter? setS;
  void say(String t) {
    status = t;
    if (open && setS != null) setS!(() {});
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx2, ss) {
      setS = ss;
      return AlertDialog(
        title: const Text('اسکن خودکار SNI و پورت'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('منابع مستقل و پروفایل‌های کاربر بررسی می‌شوند؛ خروجی SNI/Port/TLS فقط candidate است و سلامت Core/TUN را به‌تنهایی ثابت نمی‌کند.'),
              const SizedBox(height: 8),
              Text(status),
              const SizedBox(height: 8),
              Text('SNI: ${(_goldScan['sni'] ?? const []).length} • پورت: ${(_goldScan['port'] ?? const []).length} • TLS: ${(_goldScan['tls'] ?? const []).length}'),
              // SCANSHOW: نتایج همین‌جا روی صفحه با دکمه‌ی کپی
              for (final k in const ['sni', 'port', 'tls'])
                if ((_goldScan[k] ?? const <String>[]).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(k == 'sni' ? 'SNIهای دارای TLS handshake:' : (k == 'port' ? 'پورت‌های پاسخ‌گو (TCP):' : 'ALPNهای مذاکره‌شده:')),
                  SelectableText((_goldScan[k] ?? const <String>[]).join('\n')),
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(
                        text: (_goldScan[k] ?? const <String>[]).join('\n'))),
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text('کپی ${k == 'sni' ? 'SNIها' : (k == 'port' ? 'پورت‌ها' : 'TLSها')}'),
                  ),
                ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _autoScanRunning
                ? null
                : () => autoScanRun(say,
                    isVpnActive: isVpnActive,
                    isVpnWanted: isVpnWanted,
                    configuredServers: configuredServers,
                    frontSnis: frontSnis),
            child: const Text('شروع'),
          ),
          TextButton(
            onPressed: () => _autoScanStop = true,
            child: const Text('توقف'),
          ),
          TextButton(
            onPressed: () => goldShowList(context),
            child: const Text('پوشه‌ی جهانی'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('بستن'),
          ),
        ],
      );
    }),
  );
  // Closing the dialog is also a cancellation request; do not leave background
  // socket probes running after the user has dismissed the scanner.
  _autoScanStop = true;
  open = false;
}
), '');
  if (host.isEmpty || host.length > 253 ||
      InternetAddress.tryParse(host) != null) return false;
  final labels = host.split('.');
  return labels.length >= 2 && labels.every((label) =>
      label.isNotEmpty &&
      label.length <= 63 &&
      RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?
  final sw = Stopwatch()..start();
  Socket? raw;
  SecureSocket? secure;
  try {
    raw = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
    secure = await SecureSocket.secure(raw,
        host: sni)
        .timeout(const Duration(seconds: 4));
    return sw.elapsedMilliseconds;
  } catch (_) {
    return null;
  } finally {
    try { secure?.destroy(); } catch (e, st) { logError(e, st); }
    try { raw?.destroy(); } catch (e, st) { logError(e, st); }
  }
}

// ALPN (پروتکل لایه‌ی TLS): خروجی خود نام پروتکل است، مثل h2 یا http/1.1
Future<String?> _autoAlpnOk(String ip, int port, String sni, String alpn) async {
  Socket? raw;
  SecureSocket? secure;
  try {
    raw = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
    secure = await SecureSocket.secure(raw,
        host: sni,
        supportedProtocols: [alpn])
        .timeout(const Duration(seconds: 4));
    return secure.selectedProtocol;
  } catch (_) {
    return null;
  } finally {
    try { secure?.destroy(); } catch (e, st) { logError(e, st); }
    try { raw?.destroy(); } catch (e, st) { logError(e, st); }
  }
}

Future<bool> _autoPortOk(String ip, int port) async {
  try {
    final s = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 1500));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> autoScanRun(void Function(String) say,
    {bool Function()? isVpnActive,
    bool Function()? isVpnWanted,
    List<Server> configuredServers = const <Server>[],
    List<String> frontSnis = const <String>[]}) async {
  bool vpnActive() => isVpnActive?.call() ?? false;
  bool vpnWanted() => isVpnWanted?.call() ?? false;
  // Scanning through an active VPN tunnel can produce misleading direct-IP results
  // and compete with the live tunnel; keep diagnostics idle until it is disconnected.
  if (vpnActive() || vpnWanted()) {
    say('برای جلوگیری از اختلال، ابتدا VPN را قطع کنید');
    return;
  }
  if (_autoScanRunning || dnsxManualBusy || _dnsxAutoBusy || ipAutoBusy || _natRangeScanBusy) {
    say('اسکن دیگری در حال اجراست');
    return;
  }
  _autoScanRunning = true;
  dnsxManualBusy = true;
  _autoScanStop = false;
  final scanNationalMode = nationalMode;
  bool cancelled() =>
      _autoScanStop || vpnActive() || vpnWanted() || nationalMode != scanNationalMode;
  String cancellationMessage() =>
      (vpnActive() || vpnWanted())
          ? 'با شروع اتصال VPN، اسکن برای جلوگیری از تداخل متوقف شد؛ نتایج ناقص ذخیره نشد'
          : 'اسکن متوقف شد؛ نتایج ناقص ذخیره نشد';
  try {
    if (scanNationalMode) {
      await natNationalIpMemLoad();
      await natNationalDomMemLoad();
      await natRelayHostsLoad();
    } else {
      await goldLoad();
      await natIpMemLoad();
      await natDomMemLoad();
    }
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    // Scan the complete saved IP inventory and exact endpoints from the user's
    // own server profiles. Do not synthesize fallback IPs or expand unrelated
    // public/neighboring subnets.
    final ipSet = <String>{
      if (scanNationalMode) ...natNationalIpMemHosts() else ..._goldIps.keys,
      if (scanNationalMode) ...natRelayHosts,
      for (final server in configuredServers)
        if (server.isIp) server.host,
    };
    for (final server in configuredServers) {
      if (cancelled()) break;
      if (server.isIp) continue;
      ipSet.addAll(await nipResolveAll(server.host));
    }
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    final ips = ipSet.toList(growable: false);
    if (ips.isEmpty) {
      say('هیچ IP ذخیره‌شده یا endpoint مشخصی برای بررسی وجود ندارد؛ ابتدا منابع و سرورهای خودت را وارد کن');
      return;
    }
    final ports = <int>{
      ...kAutoPorts,
      ...natAutoPorts(configuredServers),
      for (final server in configuredServers)
        if (server.port >= 1 && server.port <= 65535) server.port,
    }.toList()..sort();
    final sniDomains = <String>{
      ...kAutoSniDomains,
      ...frontSnis,
      if (scanNationalMode) ...natNationalDomMemHosts(),
      if (!scanNationalMode) ...natDomMemHosts().map((entry) => entry.split(':').first),
    }.toList(growable: false);
    say('بررسی کامل موجودی: ${ips.length} IP • ${sniDomains.length} نام SNI • ${ports.length} پورت');
    // SNI: خروجی خود دامنه‌هاست. هر دامنه یک بار؛ به محض یک IP سالم، همان دامنه ثبت می‌شود
    final sniHits = <String>[];
    var n = 0;
    sniLoop:
    for (final d in sniDomains) {
      n++;
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break sniLoop;
      }
      var ok = false;
      for (final port in ports) {
        for (final ip in ips) {
          if (cancelled()) break sniLoop;
          if (await _autoSniOk(ip, port, d) != null) {
            ok = true;
            break;
          }
        }
        if (ok) break;
      }
      if (ok) sniHits.add(d);
      say('SNI $n/${sniDomains.length} • گواهی معتبر: ${sniHits.length}');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // پورت: خروجی خود شماره‌ی پورت است. هر پورت یک بار؛ به محض یک IP سالم، همان پورت ثبت می‌شود
    final portHits = <String>[];
    final nationalPortEndpoints = <String>[];
    var m = 0;
    portLoop:
    for (final p in ports) {
      m++;
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break portLoop;
      }
      var ok = false;
      for (final ip in ips) {
        if (cancelled()) break portLoop;
        if (await _autoPortOk(ip, p)) {
          ok = true;
          if (scanNationalMode) nationalPortEndpoints.add('$ip|$p');
          else break;
        }
      }
      if (ok) portHits.add('$p');
      say('پورت $m/${ports.length} • پاسخ TCP: ${portHits.length}');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // TLS/ALPN: خروجی نام پروتکل‌های TLS است؛ روی اولین دامنه‌ی سالم (یا پیش‌فرض) تست می‌شود
    final tlsHits = <String>[];
    final tlsSni = sniHits.isNotEmpty ? sniHits.first : 'www.google.com';
    for (final alpn in const ['h2', 'http/1.1']) {
      if (cancelled()) break;
      var ok = false;
      for (final port in ports) {
        for (final ip in ips) {
          if (cancelled()) break;
          final sel = await _autoAlpnOk(ip, port, tlsSni, alpn);
          if (sel != null && sel.isNotEmpty) {
            if (!tlsHits.contains(sel)) tlsHits.add(sel);
            ok = true;
            break;
          }
        }
        if (ok) break;
      }
      if (ok) say('TLS: $alpn ✓');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    // Commit the three result groups together only after every scan phase completes.
    if (scanNationalMode) {
      for (final domain in sniHits) {
        if (cancelled()) return;
        await natNationalDomMemSave(domain, 443);
      }
      for (final endpoint in nationalPortEndpoints) {
        if (cancelled()) return;
        final parts = endpoint.split('|');
        final ip = parts.first;
        final port = int.tryParse(parts.last) ?? 0;
        await natNationalIpMemSave(ip, port);
      }
    } else {
      final saved = await goldAddScans(
        {'tls': tlsHits, 'sni': sniHits, 'port': portHits},
        shouldAbort: () => cancelled(),
      );
      if (!saved) {
        say(cancellationMessage());
        return;
      }
    }
    say('تمام شد: ${sniHits.length} نام دارای گواهی معتبر و ${portHits.length} پورت پاسخ‌گو در ${scanNationalMode ? 'حافظه مستقل نت ملی' : 'پوشه جهانی'} ذخیره شد');
  } catch (e, stk) {
    logError(e, stk);
    say('خطا در اسکن خودکار');
  } finally {
    _autoScanRunning = false;
    dnsxManualBusy = false;
  }
}

Future<void> autoScanSheet(BuildContext context,
    {bool Function()? isVpnActive,
    bool Function()? isVpnWanted,
    List<Server> configuredServers = const <Server>[],
    List<String> frontSnis = const <String>[]}) async {
  var status = _autoScanRunning ? 'در حال اجرا...' : 'آماده';
  var open = true;
  StateSetter? setS;
  void say(String t) {
    status = t;
    if (open && setS != null) setS!(() {});
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx2, ss) {
      setS = ss;
      return AlertDialog(
        title: const Text('اسکن خودکار SNI و پورت'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('بدون ورودی دستی: IPهای تمیز پوشه‌ی جهانی تست می‌شوند و نتیجه همان‌جا ذخیره می‌شود.'),
              const SizedBox(height: 8),
              Text(status),
              const SizedBox(height: 8),
              Text('SNI: ${(_goldScan['sni'] ?? const []).length} • پورت: ${(_goldScan['port'] ?? const []).length} • TLS: ${(_goldScan['tls'] ?? const []).length}'),
              // SCANSHOW: نتایج همین‌جا روی صفحه با دکمه‌ی کپی
              for (final k in const ['sni', 'port', 'tls'])
                if ((_goldScan[k] ?? const <String>[]).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(k == 'sni' ? 'SNIهای سالم:' : (k == 'port' ? 'پورت‌های سالم:' : 'TLSهای سالم:')),
                  SelectableText((_goldScan[k] ?? const <String>[]).join('\n')),
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(
                        text: (_goldScan[k] ?? const <String>[]).join('\n'))),
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text('کپی ${k == 'sni' ? 'SNIها' : (k == 'port' ? 'پورت‌ها' : 'TLSها')}'),
                  ),
                ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _autoScanRunning
                ? null
                : () => autoScanRun(say,
                    isVpnActive: isVpnActive,
                    isVpnWanted: isVpnWanted,
                    configuredServers: configuredServers,
                    frontSnis: frontSnis),
            child: const Text('شروع'),
          ),
          TextButton(
            onPressed: () => _autoScanStop = true,
            child: const Text('توقف'),
          ),
          TextButton(
            onPressed: () => goldShowList(context),
            child: const Text('پوشه‌ی جهانی'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('بستن'),
          ),
        ],
      );
    }),
  );
  // Closing the dialog is also a cancellation request; do not leave background
  // socket probes running after the user has dismissed the scanner.
  _autoScanStop = true;
  open = false;
}
).hasMatch(label));
}

// TLS با SNI مشخص: اگر هندشیک کامل شود، SNI برای آن IP قابل استفاده است
Future<int?> _autoSniOk(String ip, int port, String sni) async {
  final sw = Stopwatch()..start();
  Socket? raw;
  SecureSocket? secure;
  try {
    raw = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
    secure = await SecureSocket.secure(raw,
        host: sni)
        .timeout(const Duration(seconds: 4));
    return sw.elapsedMilliseconds;
  } catch (_) {
    return null;
  } finally {
    try { secure?.destroy(); } catch (e, st) { logError(e, st); }
    try { raw?.destroy(); } catch (e, st) { logError(e, st); }
  }
}

// ALPN (پروتکل لایه‌ی TLS): خروجی خود نام پروتکل است، مثل h2 یا http/1.1
Future<String?> _autoAlpnOk(String ip, int port, String sni, String alpn) async {
  Socket? raw;
  SecureSocket? secure;
  try {
    raw = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
    secure = await SecureSocket.secure(raw,
        host: sni,
        supportedProtocols: [alpn])
        .timeout(const Duration(seconds: 4));
    return secure.selectedProtocol;
  } catch (_) {
    return null;
  } finally {
    try { secure?.destroy(); } catch (e, st) { logError(e, st); }
    try { raw?.destroy(); } catch (e, st) { logError(e, st); }
  }
}

Future<bool> _autoPortOk(String ip, int port) async {
  try {
    final s = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 1500));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> autoScanRun(void Function(String) say,
    {bool Function()? isVpnActive,
    bool Function()? isVpnWanted,
    List<Server> configuredServers = const <Server>[],
    List<String> frontSnis = const <String>[]}) async {
  bool vpnActive() => isVpnActive?.call() ?? false;
  bool vpnWanted() => isVpnWanted?.call() ?? false;
  // Scanning through an active VPN tunnel can produce misleading direct-IP results
  // and compete with the live tunnel; keep diagnostics idle until it is disconnected.
  if (vpnActive() || vpnWanted()) {
    say('برای جلوگیری از اختلال، ابتدا VPN را قطع کنید');
    return;
  }
  if (_autoScanRunning || dnsxManualBusy || _dnsxAutoBusy || ipAutoBusy || _natRangeScanBusy) {
    say('اسکن دیگری در حال اجراست');
    return;
  }
  _autoScanRunning = true;
  dnsxManualBusy = true;
  _autoScanStop = false;
  final scanNationalMode = nationalMode;
  bool cancelled() =>
      _autoScanStop || vpnActive() || vpnWanted() || nationalMode != scanNationalMode;
  String cancellationMessage() =>
      (vpnActive() || vpnWanted())
          ? 'با شروع اتصال VPN، اسکن برای جلوگیری از تداخل متوقف شد؛ نتایج ناقص ذخیره نشد'
          : 'اسکن متوقف شد؛ نتایج ناقص ذخیره نشد';
  try {
    if (scanNationalMode) {
      await natNationalIpMemLoad();
      await natNationalDomMemLoad();
      await natRelayHostsLoad();
    } else {
      await goldLoad();
      await natIpMemLoad();
      await natDomMemLoad();
    }
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    // Scan the complete saved IP inventory and exact endpoints from the user's
    // own server profiles. Do not synthesize fallback IPs or expand unrelated
    // public/neighboring subnets.
    final ipSet = <String>{
      if (scanNationalMode) ...natNationalIpMemHosts() else ..._goldIps.keys,
      if (scanNationalMode) ...natRelayHosts,
      for (final server in configuredServers)
        if (server.isIp) server.host,
    };
    for (final server in configuredServers) {
      if (cancelled()) break;
      if (server.isIp) continue;
      ipSet.addAll(await nipResolveAll(server.host));
    }
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    final ips = ipSet.toList(growable: false);
    if (ips.isEmpty) {
      say('هیچ IP ذخیره‌شده یا endpoint مشخصی برای بررسی وجود ندارد؛ ابتدا منابع و سرورهای خودت را وارد کن');
      return;
    }
    final ports = <int>{
      ...kAutoPorts,
      ...natAutoPorts(configuredServers),
      for (final server in configuredServers)
        if (server.port >= 1 && server.port <= 65535) server.port,
    }.toList()..sort();
    final sniDomains = <String>{
      ...kAutoSniDomains,
      ...frontSnis,
      if (scanNationalMode) ...natNationalDomMemHosts(),
      if (!scanNationalMode) ...natDomMemHosts().map((entry) => entry.split(':').first),
    }.toList(growable: false);
    say('بررسی کامل موجودی: ${ips.length} IP • ${sniDomains.length} نام SNI • ${ports.length} پورت');
    // SNI: خروجی خود دامنه‌هاست. هر دامنه یک بار؛ به محض یک IP سالم، همان دامنه ثبت می‌شود
    final sniHits = <String>[];
    var n = 0;
    sniLoop:
    for (final d in sniDomains) {
      n++;
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break sniLoop;
      }
      var ok = false;
      for (final port in ports) {
        for (final ip in ips) {
          if (cancelled()) break sniLoop;
          if (await _autoSniOk(ip, port, d) != null) {
            ok = true;
            break;
          }
        }
        if (ok) break;
      }
      if (ok) sniHits.add(d);
      say('SNI $n/${sniDomains.length} • گواهی معتبر: ${sniHits.length}');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // پورت: خروجی خود شماره‌ی پورت است. هر پورت یک بار؛ به محض یک IP سالم، همان پورت ثبت می‌شود
    final portHits = <String>[];
    final nationalPortEndpoints = <String>[];
    var m = 0;
    portLoop:
    for (final p in ports) {
      m++;
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break portLoop;
      }
      var ok = false;
      for (final ip in ips) {
        if (cancelled()) break portLoop;
        if (await _autoPortOk(ip, p)) {
          ok = true;
          if (scanNationalMode) nationalPortEndpoints.add('$ip|$p');
          else break;
        }
      }
      if (ok) portHits.add('$p');
      say('پورت $m/${ports.length} • پاسخ TCP: ${portHits.length}');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // TLS/ALPN: خروجی نام پروتکل‌های TLS است؛ روی اولین دامنه‌ی سالم (یا پیش‌فرض) تست می‌شود
    final tlsHits = <String>[];
    final tlsSni = sniHits.isNotEmpty ? sniHits.first : 'www.google.com';
    for (final alpn in const ['h2', 'http/1.1']) {
      if (cancelled()) break;
      var ok = false;
      for (final port in ports) {
        for (final ip in ips) {
          if (cancelled()) break;
          final sel = await _autoAlpnOk(ip, port, tlsSni, alpn);
          if (sel != null && sel.isNotEmpty) {
            if (!tlsHits.contains(sel)) tlsHits.add(sel);
            ok = true;
            break;
          }
        }
        if (ok) break;
      }
      if (ok) say('TLS: $alpn ✓');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    // Commit the three result groups together only after every scan phase completes.
    if (scanNationalMode) {
      for (final domain in sniHits) {
        if (cancelled()) return;
        await natNationalDomMemSave(domain, 443);
      }
      for (final endpoint in nationalPortEndpoints) {
        if (cancelled()) return;
        final parts = endpoint.split('|');
        final ip = parts.first;
        final port = int.tryParse(parts.last) ?? 0;
        await natNationalIpMemSave(ip, port);
      }
    } else {
      final saved = await goldAddScans(
        {'tls': tlsHits, 'sni': sniHits, 'port': portHits},
        shouldAbort: () => cancelled(),
      );
      if (!saved) {
        say(cancellationMessage());
        return;
      }
    }
    say('تمام شد: ${sniHits.length} نام دارای گواهی معتبر و ${portHits.length} پورت پاسخ‌گو در ${scanNationalMode ? 'حافظه مستقل نت ملی' : 'پوشه جهانی'} ذخیره شد');
  } catch (e, stk) {
    logError(e, stk);
    say('خطا در اسکن خودکار');
  } finally {
    _autoScanRunning = false;
    dnsxManualBusy = false;
  }
}

Future<void> autoScanSheet(BuildContext context,
    {bool Function()? isVpnActive,
    bool Function()? isVpnWanted,
    List<Server> configuredServers = const <Server>[],
    List<String> frontSnis = const <String>[]}) async {
  var status = _autoScanRunning ? 'در حال اجرا...' : 'آماده';
  var open = true;
  StateSetter? setS;
  void say(String t) {
    status = t;
    if (open && setS != null) setS!(() {});
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx2, ss) {
      setS = ss;
      return AlertDialog(
        title: const Text('اسکن خودکار SNI و پورت'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('بدون ورودی دستی: IPهای تمیز پوشه‌ی جهانی تست می‌شوند و نتیجه همان‌جا ذخیره می‌شود.'),
              const SizedBox(height: 8),
              Text(status),
              const SizedBox(height: 8),
              Text('SNI: ${(_goldScan['sni'] ?? const []).length} • پورت: ${(_goldScan['port'] ?? const []).length} • TLS: ${(_goldScan['tls'] ?? const []).length}'),
              // SCANSHOW: نتایج همین‌جا روی صفحه با دکمه‌ی کپی
              for (final k in const ['sni', 'port', 'tls'])
                if ((_goldScan[k] ?? const <String>[]).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(k == 'sni' ? 'SNIهای سالم:' : (k == 'port' ? 'پورت‌های سالم:' : 'TLSهای سالم:')),
                  SelectableText((_goldScan[k] ?? const <String>[]).join('\n')),
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(
                        text: (_goldScan[k] ?? const <String>[]).join('\n'))),
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text('کپی ${k == 'sni' ? 'SNIها' : (k == 'port' ? 'پورت‌ها' : 'TLSها')}'),
                  ),
                ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _autoScanRunning
                ? null
                : () => autoScanRun(say,
                    isVpnActive: isVpnActive,
                    isVpnWanted: isVpnWanted,
                    configuredServers: configuredServers,
                    frontSnis: frontSnis),
            child: const Text('شروع'),
          ),
          TextButton(
            onPressed: () => _autoScanStop = true,
            child: const Text('توقف'),
          ),
          TextButton(
            onPressed: () => goldShowList(context),
            child: const Text('پوشه‌ی جهانی'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('بستن'),
          ),
        ],
      );
    }),
  );
  // Closing the dialog is also a cancellation request; do not leave background
  // socket probes running after the user has dismissed the scanner.
  _autoScanStop = true;
  open = false;
}
