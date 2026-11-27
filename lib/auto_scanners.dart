part of 'main.dart';

// AUTOSCAN: کشف SNI، پورت و ALPN از inventory مستقل و قالب‌های موجود.
// خروجی‌ها candidate هستند؛ TLS/TCP handshake به‌تنهایی سلامت Core یا TUN را ثابت نمی‌کند.
const List<String> kAutoSniDomains = [
  'www.google.com', 'www.youtube.com', 'www.instagram.com', 'www.microsoft.com',
  'www.apple.com', 'www.cloudflare.com', 'speed.cloudflare.com', 'www.digikala.com',
  'www.aparat.com', 'www.snapp.ir', 'www.divar.ir', 'www.wikipedia.org',
  'www.amazon.com', 'dl.google.com', 'www.whatsapp.com', 'www.telegram.org',
  'www.spotify.com', 'www.github.com',
];
const List<int> kAutoPorts = [
  443, 8443, 2053, 2083, 2087, 2096, 80, 8080, 8880, 2052, 2082, 2086,
  2095, 8444, 9443, 4443, 5443, 6443, 7443, 10443, 2222, 8000, 8008,
  8888, 3128, 1080,
];

bool _autoScanRunning = false;
bool _autoScanStop = false;
const String _natAutoScanCandidatesKey = 'nat_auto_scan_candidates_v1';
bool _natAutoScanLoaded = false;
final Map<String, List<String>> _natAutoScanCandidates = <String, List<String>>{
  'sni': <String>[],
  'port': <String>[],
  'tls': <String>[],
};

Future<void> _natAutoScanLoad() async {
  if (_natAutoScanLoaded) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_natAutoScanCandidatesKey);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final key in const <String>['sni', 'port', 'tls']) {
          final values = decoded[key];
          if (values is List) {
            _natAutoScanCandidates[key] = values
                .whereType<String>()
                .toSet()
                .toList(growable: false);
          }
        }
      }
    }
    _natAutoScanLoaded = true;
  } catch (error, stackTrace) {
    logError(error, stackTrace);
  }
}

Future<void> _natAutoScanSave() async {
  final snapshot = <String, List<String>>{
    for (final key in const <String>['sni', 'port', 'tls'])
      key: List<String>.unmodifiable(_natAutoScanCandidates[key]!),
  };
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_natAutoScanCandidatesKey, jsonEncode(snapshot));
  } catch (error, stackTrace) {
    logError(error, stackTrace);
  }
}

// SNI must be a DNS hostname; an IP literal is never a valid SNI candidate.
bool _autoValidSni(String value) {
  final host = value.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  if (host.isEmpty || host.length > 253 ||
      InternetAddress.tryParse(host) != null) return false;
  final labels = host.split('.');
  return labels.length >= 2 && labels.every((label) =>
      label.isNotEmpty &&
      label.length <= 63 &&
      RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label));
}

// A successful TLS handshake with normal certificate validation is an SNI
// candidate. Sockets are always destroyed, including timeout/error paths.
Future<int?> _autoSniOk(String ip, int port, String sni) async {
  final sw = Stopwatch()..start();
  Socket? raw;
  SecureSocket? secure;
  try {
    raw = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
    secure = await SecureSocket.secure(raw, host: sni)
        .timeout(const Duration(seconds: 4));
    return sw.elapsedMilliseconds;
  } catch (_) {
    return null;
  } finally {
    try { secure?.destroy(); } catch (e, st) { logError(e, st); }
    try { raw?.destroy(); } catch (e, st) { logError(e, st); }
  }
}

// ALPN negotiation is a TLS candidate only; it is not a Core/TUN health test.
Future<String?> _autoAlpnOk(String ip, int port, String sni, String alpn) async {
  Socket? raw;
  SecureSocket? secure;
  try {
    raw = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
    secure = await SecureSocket.secure(
      raw,
      host: sni,
      supportedProtocols: <String>[alpn],
    ).timeout(const Duration(seconds: 4));
    return secure.selectedProtocol;
  } catch (_) {
    return null;
  } finally {
    try { secure?.destroy(); } catch (e, st) { logError(e, st); }
    try { raw?.destroy(); } catch (e, st) { logError(e, st); }
  }
}

Future<bool> _autoPortOk(String ip, int port) async {
  Socket? socket;
  try {
    socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 1500));
    return true;
  } catch (_) {
    return false;
  } finally {
    try { socket?.destroy(); } catch (e, st) { logError(e, st); }
  }
}

// Bounded fan-out limits concurrent sockets, never the number of inventory items.
const int _autoProbeConcurrency = 8;

Future<bool> _autoAnyAddress(
  List<String> addresses,
  Future<bool> Function(String ip) probe, {
  bool Function()? shouldStop,
}) async {
  if (addresses.isEmpty) return false;
  var cursor = 0;
  var matched = false;
  Future<void> worker() async {
    while (!matched && !(shouldStop?.call() ?? false)) {
      final index = cursor++;
      if (index >= addresses.length) return;
      if (await probe(addresses[index])) matched = true;
    }
  }

  final workers = <Future<void>>[];
  for (var i = 0; i < addresses.length && i < _autoProbeConcurrency; i++) {
    workers.add(worker());
  }
  await Future.wait(workers);
  return matched;
}

Future<List<String>> _autoCollectAddresses(
  List<String> addresses,
  Future<bool> Function(String ip) probe, {
  bool Function()? shouldStop,
}) async {
  if (addresses.isEmpty) return const <String>[];
  var cursor = 0;
  final matched = <String>[];
  Future<void> worker() async {
    while (!(shouldStop?.call() ?? false)) {
      final index = cursor++;
      if (index >= addresses.length) return;
      final ip = addresses[index];
      if (await probe(ip)) matched.add(ip);
    }
  }

  final workers = <Future<void>>[];
  for (var i = 0; i < addresses.length && i < _autoProbeConcurrency; i++) {
    workers.add(worker());
  }
  await Future.wait(workers);
  return List<String>.unmodifiable(matched);
}

Future<void> autoScanRun(
  void Function(String) say, {
  bool Function()? isVpnActive,
  bool Function()? isVpnWanted,
  List<Server> configuredServers = const <Server>[],
  List<String> frontSnis = const <String>[],
}) async {
  bool vpnActive() => isVpnActive?.call() ?? false;
  bool vpnWanted() => isVpnWanted?.call() ?? false;
  if (vpnActive() || vpnWanted()) {
    say('برای جلوگیری از تداخل، ابتدا VPN را قطع کنید');
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
  bool cancelled() => _autoScanStop || vpnActive() || vpnWanted() || nationalMode != scanNationalMode;
  String cancellationMessage() =>
      (vpnActive() || vpnWanted())
          ? 'با شروع اتصال VPN، اسکن برای جلوگیری از تداخل متوقف شد؛ نتایج ناقص ذخیره نشد'
          : 'اسکن متوقف شد؛ نتایج ناقص ذخیره نشد';

  try {
    if (scanNationalMode) {
      await _natAutoScanLoad();
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

    // Discover templates independently of the currently selected config.
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
    for (final server in <Server>[...configuredServers, ...sourceTemplates]) {
      if (templateKeys.add(server.link.trim())) templates.add(server);
    }

    // Exact saved IPs plus exact IP endpoints from templates. Hostnames are
    // resolved to returned A/AAAA records; no neighboring subnet is invented.
    final ipSet = <String>{
      if (scanNationalMode) ...natNationalIpMemHosts() else ..._goldIps.keys,
      if (!scanNationalMode) ...natIpMemHosts(),
      if (scanNationalMode) ...natScanHits,
    };
    final domainHosts = <String>{
      if (scanNationalMode) ...natNationalDomMemHosts(),
      if (scanNationalMode) ...natRelayHosts,
      if (!scanNationalMode) ...natDomMemHosts(),
    };
    final sniCandidates = <String>{
      ...kAutoSniDomains,
      ...frontSnis,
      if (scanNationalMode) ...natRelayHosts,
      if (scanNationalMode) ...natNationalDomMemHosts(),
      if (!scanNationalMode) ...natDomMemHosts(),
    };

    for (final server in configuredServers) {
      if (cancelled()) break;
      if (server.isIp) {
        ipSet.add(server.host);
      } else {
        domainHosts.add(server.host);
        sniCandidates.add(server.host);
      }
      if (server.sni.trim().isNotEmpty) sniCandidates.add(server.sni);
    }
    for (final server in sourceTemplates) {
      if (cancelled()) break;
      if (server.isIp) {
        ipSet.add(server.host);
      } else {
        domainHosts.add(server.host);
        sniCandidates.add(server.host);
      }
      if (server.sni.trim().isNotEmpty) sniCandidates.add(server.sni);
    }

    final resolveHosts = domainHosts
        .map((host) => host.trim())
        .where((host) => host.isNotEmpty && InternetAddress.tryParse(host) == null)
        .toSet()
        .toList(growable: false);
    // Bounded DNS fan-out controls simultaneous sockets, not inventory size.
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
    final ports = <int>{
      ...kAutoPorts,
      ...natAutoPorts(templates),
      for (final server in templates)
        if (server.port >= 1 && server.port <= 65535) server.port,
    }.where((port) => port >= 1 && port <= 65535).toList()..sort();

    if (ips.isEmpty) {
      say('هیچ IP دقیقی از منابع مستقل یا حافظهٔ همین حالت برای بررسی وجود ندارد');
      return;
    }
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    say('قالب‌ها: ${templates.length} • IP دقیق: ${ips.length} • SNI: ${sniDomains.length} • پورت: ${ports.length}');

    // SNI candidates: each domain is tested against all known IP/port pairs.
    final sniHits = <String>[];
    final sniHitPorts = <String, int>{};
    var sniIndex = 0;
    sniLoop:
    for (final domain in sniDomains) {
      sniIndex++;
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break sniLoop;
      }
      var successPort = 0;
      for (final port in ports) {
        if (cancelled()) break sniLoop;
        final matched = await _autoAnyAddress(
          ips,
          (ip) async => await _autoSniOk(ip, port, domain) != null,
          shouldStop: cancelled,
        );
        if (matched) {
          successPort = port;
          break;
        }
      }
      if (successPort != 0) {
        sniHits.add(domain);
        sniHitPorts[domain] = successPort;
      }
      say('SNI $sniIndex/${sniDomains.length} • TLS handshake: ${sniHits.length}');
    }
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // TCP-open ports are candidates only; retain exact national IP endpoints.
    final portHits = <String>[];
    final nationalPortEndpoints = <String>[];
    var portIndex = 0;
    portLoop:
    for (final port in ports) {
      portIndex++;
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break portLoop;
      }
      bool success;
      if (scanNationalMode) {
        final openIps = await _autoCollectAddresses(
          ips,
          (ip) => _autoPortOk(ip, port),
          shouldStop: cancelled,
        );
        for (final ip in openIps) {
          nationalPortEndpoints.add('$ip|$port');
        }
        success = openIps.isNotEmpty;
      } else {
        success = await _autoAnyAddress(
          ips,
          (ip) => _autoPortOk(ip, port),
          shouldStop: cancelled,
        );
      }
      if (cancelled()) break portLoop;
      if (success) portHits.add('$port');
      say('Port $portIndex/${ports.length} • TCP candidates: ${portHits.length}');
    }
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // ALPN candidates use a valid SNI (or default) and TLS port 443.
    final tlsHits = <String>[];
    final tlsSni = sniHits.isNotEmpty ? sniHits.first : 'www.google.com';
    for (final alpn in const <String>['h2', 'http/1.1']) {
      if (cancelled()) break;
      final success = await _autoAnyAddress(
        ips,
        (ip) async {
          final selected = await _autoAlpnOk(ip, 443, tlsSni, alpn);
          if (selected == null || selected.isEmpty) return false;
          if (!tlsHits.contains(selected)) tlsHits.add(selected);
          return true;
        },
        shouldStop: cancelled,
      );
      if (success) say('ALPN: $alpn ✓');
    }
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // Commit only after all phases complete; national and global inventories
    // remain separate.
    if (scanNationalMode) {
      final nationalDomains = <String>{...sniHits};
      for (final endpoint in nationalPortEndpoints) {
        final parts = endpoint.split('|');
        final ip = parts.first;
        final port = int.tryParse(parts.last) ?? 0;
        natScanHits.add(ip);
        await natNationalIpMemSave(ip, port);
      }
      for (final domain in nationalDomains) {
        await natNationalDomMemSave(domain, sniHitPorts[domain] ?? 443);
      }
      _natAutoScanCandidates['sni'] = <String>{
        ..._natAutoScanCandidates['sni']!,
        ...sniHits,
      }.toList(growable: false);
      _natAutoScanCandidates['port'] = <String>{
        ..._natAutoScanCandidates['port']!,
        ...portHits,
      }.toList(growable: false);
      _natAutoScanCandidates['tls'] = <String>{
        ..._natAutoScanCandidates['tls']!,
        ...tlsHits,
      }.toList(growable: false);
      await _natAutoScanSave();
    } else {
      final saved = await goldAddScans(
        <String, List<String>>{'tls': tlsHits, 'sni': sniHits, 'port': portHits},
        shouldAbort: () => cancelled(),
      );
      if (!saved) {
        say(cancellationMessage());
        return;
      }
    }
    say('تمام شد: ${sniHits.length} SNI candidate، ${portHits.length} پورت TCP و ${tlsHits.length} ALPN candidate؛ هیچ فیلد کانفیگی خودکار جایگزین نشد.');
  } catch (error, stackTrace) {
    logError(error, stackTrace);
    say('خطا در اسکن SNI/Port/TLS');
  } finally {
    _autoScanRunning = false;
    dnsxManualBusy = false;
  }
}

Future<void> autoScanSheet(
  BuildContext context, {
  bool Function()? isVpnActive,
  bool Function()? isVpnWanted,
  List<Server> configuredServers = const <Server>[],
  List<String> frontSnis = const <String>[],
}) async {
  await _natAutoScanLoad();
  if (nationalMode) await natNationalIpMemLoad();
  var status = _autoScanRunning ? 'در حال اجرا...' : 'آماده';
  var open = true;
  StateSetter? setS;
  void say(String value) {
    status = value;
    if (open && setS != null) setS!(() {});
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx2, setStateDialog) {
        setS = setStateDialog;
        final results = nationalMode ? _natAutoScanCandidates : _goldScan;
        return AlertDialog(
          title: const Text('اسکن خودکار SNI / Port / TLS'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('نتایج SNI/TLS و پورت فقط candidate هستند؛ سلامت Core و TUN باید جداگانه تأیید شود.'),
                const SizedBox(height: 8),
                Text(status),
                const SizedBox(height: 8),
                Text('IP: ${nationalMode ? natNationalIpMemHosts().length : 0} • SNI: ${(results['sni'] ?? const <String>[]).length} • Port: ${(results['port'] ?? const <String>[]).length} • TLS: ${(results['tls'] ?? const <String>[]).length}'),
                for (final key in const <String>['sni', 'port', 'tls'])
                  if ((results[key] ?? const <String>[]).isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(key == 'sni'
                        ? 'SNI handshake candidates:'
                        : key == 'port'
                            ? 'TCP-open port candidates:'
                            : 'ALPN candidates:'),
                    SelectableText((results[key] ?? const <String>[]).join('\n')),
                    TextButton.icon(
                      onPressed: () => Clipboard.setData(ClipboardData(
                        text: (results[key] ?? const <String>[]).join('\n'),
                      )),
                      icon: const Icon(Icons.copy, size: 16),
                      label: Text('کپی ${key == 'sni' ? 'SNIها' : key == 'port' ? 'پورت‌ها' : 'TLSها'}'),
                    ),
                  ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: _autoScanRunning
                  ? null
                  : () => autoScanRun(
                        say,
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
              onPressed: () {
                if (!nationalMode) {
                  goldShowList(context);
                } else {
                  say('نتایج ملی در حافظهٔ مستقل حالت ملی نگهداری می‌شوند.');
                }
              },
              child: Text(nationalMode ? 'حافظهٔ نت ملی' : 'پوشهٔ جهانی'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('بستن'),
            ),
          ],
        );
      },
    ),
  );
  // Closing the dialog is also a cancellation request.
  _autoScanStop = true;
  open = false;
}
