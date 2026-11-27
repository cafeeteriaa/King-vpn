part of 'main.dart';

// AUTOSCAN: اسکنر خودکار SNI و پورت از feedهای مستقل و پروفایل‌های موجود.
// خروجی‌ها candidate هستند؛ TLS/TCP handshake به‌تنهایی اثبات سلامت Core یا TUN نیست.
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
  var host = value.trim().toLowerCase();
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  if (host.isEmpty || host.length > 253 ||
      InternetAddress.tryParse(host) != null) return false;
  final labels = host.split('.');
  return labels.length >= 2 && labels.every((label) =>
      label.isNotEmpty &&
      label.length <= 63 &&
      RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label));
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
  if (vpnActive() || vpnWanted()) {
    say('برای جلوگیری از اختلال، ابتدا VPN را قطع کنید');
    return;
  }
  if (_autoScanRunning || dnsxManualBusy || _dnsxAutoBusy ||
      ipAutoBusy || _natRangeScanBusy) {
    say('اسکن دیگری در حال اجراست');
    return;
  }

  _autoScanRunning = true;
  dnsxManualBusy = true;
  _autoScanStop = false;
  final scanNationalMode = nationalMode;
  bool cancelled() => _autoScanStop || vpnActive() || vpnWanted() || nationalMode != scanNationalMode;
  String cancellationMessage() => (vpnActive() || vpnWanted())
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

    // Discover fresh independent feeds, retaining protocol/credential-distinct
    // links even when their endpoint host:port is shared.
    final sourceTemplates = <Server>[];
    try {
      if (scanNationalMode) {
        sourceTemplates.addAll(await natHotAll(fetch: true));
      } else {
        sourceTemplates.addAll(await fetchServers(
          stop: () => cancelled(),
          dedupeByLink: true,
        ));
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
      final key = server.link.trim();
      if (key.isNotEmpty && templateKeys.add(key)) templates.add(server);
    }
    if (templates.isEmpty) {
      say('از منابع مستقل یا پروفایل‌های کاربر هیچ قالب قابل‌بررسی پیدا نشد');
      return;
    }

    // Exact IP inventory only: source hostnames resolve to returned A/AAAA
    // addresses; no neighboring subnet or synthetic fallback is generated.
    final ips = <String>{
      if (scanNationalMode) ...natNationalIpMemHosts() else ..._goldIps.keys,
      if (!scanNationalMode) ...natIpMemHosts(),
      if (scanNationalMode) ...natScanHits,
    };
    final hostnames = <String>{
      if (scanNationalMode) ...natNationalDomMemHosts(),
      if (scanNationalMode) ...natRelayHosts,
      if (!scanNationalMode)
        ...natDomMemHosts().map((entry) => entry.split(':').first),
    };
    final sniCandidates = <String>{
      ...kAutoSniDomains,
      ...frontSnis,
      if (scanNationalMode) ...natNationalDomMemHosts(),
      if (!scanNationalMode)
        ...natDomMemHosts().map((entry) => entry.split(':').first),
      for (final server in templates) server.sni,
    };
    for (final server in templates) {
      if (cancelled()) break;
      final host = server.host.trim();
      if (host.isEmpty) continue;
      final literal = InternetAddress.tryParse(host);
      if (literal != null) {
        ips.add(literal.address);
      } else {
        hostnames.add(host);
        sniCandidates.add(host);
      }
    }
    for (final host in hostnames) {
      final literal = InternetAddress.tryParse(host.trim());
      if (literal != null) ips.add(literal.address);
    }

    final resolveHosts = hostnames
        .map((host) => host.trim())
        .where((host) => host.isNotEmpty && InternetAddress.tryParse(host) == null)
        .toSet()
        .toList(growable: false);
    for (var offset = 0; offset < resolveHosts.length; offset += 16) {
      if (cancelled()) break;
      final batch = resolveHosts.skip(offset).take(16).toList(growable: false);
      final resolved = await Future.wait<List<String>>(batch.map((host) async {
        try {
          return await nipResolveAll(host).timeout(const Duration(seconds: 4));
        } catch (error, stackTrace) {
          logError(error, stackTrace);
          return const <String>[];
        }
      }));
      for (final addresses in resolved) {
        ips.addAll(addresses);
      }
    }
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    final validIps = ips
        .map((value) => value.trim())
        .where((value) => InternetAddress.tryParse(value) != null)
        .map((value) => InternetAddress.tryParse(value)!.address)
        .toSet()
        .toList(growable: false);
    final sniDomains = sniCandidates
        .map((value) {
          var host = value.trim().toLowerCase();
          if (host.endsWith('.')) host = host.substring(0, host.length - 1);
          return host;
        })
        .where(_autoValidSni)
        .toSet()
        .toList(growable: false);
    final ports = <int>{
      ...kAutoPorts,
      ...natAutoPorts(templates),
      for (final server in templates)
        if (server.port >= 1 && server.port <= 65535) server.port,
    }.where((port) => port >= 1 && port <= 65535).toSet().toList()..sort();

    if (validIps.isEmpty || ports.isEmpty || sniDomains.isEmpty) {
      say('موجودی کافی نیست: \${validIps.length} IP دقیق، \${sniDomains.length} SNI معتبر و \${ports.length} پورت');
      return;
    }
    say('کشف مستقل کامل شد: \${templates.length} قالب • \${validIps.length} IP • \${sniDomains.length} SNI • \${ports.length} پورت');

    // TLS success proves only the tested IP:port:SNI tuple, not Core/TUN.
    final sniHits = <String>[];
    var checkedSni = 0;
    sniLoop:
    for (final domain in sniDomains) {
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break sniLoop;
      }
      if (cancelled()) break sniLoop;
      var matched = false;
      for (final port in ports) {
        if (cancelled()) break;
        for (final ip in validIps) {
          if (cancelled()) break sniLoop;
          if (await _autoSniOk(ip, port, domain) != null) {
            matched = true;
            break;
          }
        }
        if (matched) break;
      }
      if (matched) sniHits.add(domain);
      checkedSni++;
      if (checkedSni % 4 == 0) {
        say('بررسی SNI: $checkedSni/\${sniDomains.length} • candidate: \${sniHits.length}');
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    final portHits = <String>[];
    final nationalPortEndpoints = <String>{};
    var checkedPorts = 0;
    portLoop:
    for (final port in ports) {
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break portLoop;
      }
      if (cancelled()) break portLoop;
      var matched = false;
      for (final ip in validIps) {
        if (cancelled()) break portLoop;
        if (await _autoPortOk(ip, port)) {
          matched = true;
          if (scanNationalMode) {
            nationalPortEndpoints.add('$ip|$port');
          } else {
            break;
          }
        }
      }
      if (matched) portHits.add('$port');
      checkedPorts++;
      if (checkedPorts % 4 == 0) {
        say('بررسی TCP: $checkedPorts/\${ports.length} • candidate: \${portHits.length}');
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    final tlsHits = <String>[];
    final tlsSni = sniHits.isNotEmpty ? sniHits.first : sniDomains.first;
    for (final alpn in const ['h2', 'http/1.1']) {
      if (cancelled()) break;
      var matched = false;
      for (final port in ports) {
        if (cancelled()) break;
        for (final ip in validIps) {
          if (cancelled()) break;
          final selected = await _autoAlpnOk(ip, port, tlsSni, alpn);
          if (selected != null && selected.isNotEmpty) {
            if (!tlsHits.contains(selected)) tlsHits.add(selected);
            matched = true;
            break;
          }
        }
        if (matched) break;
      }
    }
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // Persist only after all probe phases finish. These are candidates only;
    // no active configuration field is rewritten by this diagnostic scanner.
    if (scanNationalMode) {
      for (final domain in sniHits) {
        await natNationalDomMemSave(domain, 443);
      }
      for (final endpoint in nationalPortEndpoints) {
        final parts = endpoint.split('|');
        final port = int.tryParse(parts.last) ?? 0;
        await natNationalIpMemSave(parts.first, port);
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
      if (cancelled()) {
        say(cancellationMessage());
        return;
      }
    }
    say('تمام شد: \${sniHits.length} SNI با TLS handshake، \${portHits.length} پورت TCP و \${tlsHits.length} ALPN candidate ذخیره شد؛ Core/TUN باید جداگانه اعتبارسنجی شود');
  } catch (error, stackTrace) {
    logError(error, stackTrace);
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
              const Text('منابع مستقل و پروفایل‌های کاربر بررسی می‌شوند؛ خروجی TLS/TCP فقط candidate است و سلامت Core/TUN را ثابت نمی‌کند.'),
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
