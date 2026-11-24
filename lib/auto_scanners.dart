part of 'main.dart';

// AUTOSCAN: اسکنر خودکار SNI و پورت. بدون ورودی دستی؛ IPهای تمیز پوشه‌ی جهانی را تست می‌کند
// و نتیجه را همان‌جا ذخیره می‌کند (کلیدهای 'sni' و 'port').
// Broad seed catalog. This is only one source: the scanner also merges the
// full project DNS inventory, front-SNI/relay catalogs and saved server hosts.
const List<String> kAutoSniDomains = [
  // Global infrastructure, software and content delivery.
  'www.google.com', 'www.youtube.com', 'www.gstatic.com', 'fonts.googleapis.com',
  'fonts.gstatic.com', 'dl.google.com', 'accounts.google.com', 'drive.google.com',
  'www.googleusercontent.com', 'www.googleapis.com', 'android.com',
  'www.microsoft.com', 'login.microsoftonline.com', 'www.office.com',
  'www.live.com', 'www.bing.com', 'edge.microsoft.com', 'www.azure.com',
  'www.apple.com', 'icloud.com', 'www.icloud.com', 'apps.apple.com',
  'developer.apple.com', 'www.cloudflare.com', 'cloudflare.com',
  'www.cloudflarestatus.com', 'speed.cloudflare.com', 'one.one.one.one',
  'www.amazon.com', 'aws.amazon.com', 'www.amazontrust.com',
  'www.github.com', 'github.com', 'raw.githubusercontent.com',
  'objects.githubusercontent.com', 'githubusercontent.com',
  'www.fastly.com', 'www.akamai.com', 'www.akamaized.net',
  'www.jsdelivr.com', 'cdn.jsdelivr.net', 'unpkg.com', 'cdnjs.cloudflare.com',
  'www.digitalocean.com', 'www.oracle.com', 'www.ibm.com', 'www.intel.com',
  'www.nvidia.com', 'www.docker.com', 'hub.docker.com',
  // Communication, social, media and collaboration.
  'www.instagram.com', 'instagram.com', 'www.facebook.com', 'www.meta.com',
  'www.whatsapp.com', 'web.whatsapp.com', 'www.messenger.com',
  'www.telegram.org', 'telegram.org', 'web.telegram.org',
  'www.reddit.com', 'reddit.com', 'www.x.com', 'x.com', 'twitter.com',
  'www.linkedin.com', 'linkedin.com', 'www.discord.com', 'discord.com',
  'www.slack.com', 'slack.com', 'www.zoom.us', 'zoom.us',
  'www.spotify.com', 'open.spotify.com', 'www.soundcloud.com',
  'www.netflix.com', 'www.twitch.tv', 'www.primevideo.com',
  'www.disneyplus.com', 'www.pinterest.com', 'www.tiktok.com',
  'www.snapchat.com', 'www.dropbox.com', 'www.notion.so',
  // Search, documentation, package and developer services.
  'wikipedia.org', 'www.wikimedia.org',
  'www.stackoverflow.com', 'stackoverflow.com', 'serverfault.com',
  'www.python.org', 'pypi.org', 'www.npmjs.com', 'registry.npmjs.org',
  'pub.dev', 'dart.dev', 'flutter.dev', 'www.rust-lang.org',
  'go.dev', 'pkg.go.dev', 'www.gnu.org', 'www.kernel.org',
  'www.mozilla.org', 'developer.mozilla.org', 'www.chromium.org',
  // Iranian public services and high-availability content sites.
  'www.digikala.com', 'digikala.com', 'www.aparat.com', 'aparat.com',
  'www.snapp.ir', 'snapp.ir', 'www.divar.ir', 'divar.ir',
  'www.telewebion.com', 'www.tasnimnews.com', 'www.isna.ir',
  'www.irna.ir', 'www.mehrnews.com', 'www.khabaronline.ir',
  'www.varzesh3.com', 'www.zoomit.ir', 'www.zdnet.com',
  'www.sheypoor.com', 'www.bale.ai', 'web.eitaa.com',
  'www.namasha.com', 'www.filimo.com', 'www.namava.ir',
  'www.torob.com', 'www.basalam.com', 'www.alibaba.ir',
  'www.irancell.ir', 'www.mci.ir', 'www.rightel.ir',
  // Additional globally distributed sites.
  'www.yandex.com', 'yandex.com', 'www.baidu.com', 'www.qq.com',
  'www.wikipedia.org', 'www.nytimes.com', 'www.bbc.com', 'www.cnn.com',
  'www.reuters.com', 'www.theguardian.com', 'www.weather.com',
  'www.booking.com', 'www.airbnb.com', 'www.ebay.com', 'www.paypal.com',
  'www.shopify.com', 'www.salesforce.com', 'www.atlassian.com',
  'www.canva.com', 'www.figma.com', 'www.openai.com',
];
const List<int> kAutoPorts = [443, 8443, 2053, 2083, 2087, 2096];
// AUTOFALLBACK: IPهای داخلی برای وقتی پوشه‌ی جهانی هنوز IP تمیز ندارد
const List<String> kAutoFallbackIps = [
  '104.16.0.1', '104.17.0.1', '104.18.0.1', '104.19.0.1', '104.20.0.1',
  '172.67.0.1', '162.159.0.1', '188.114.96.1', '188.114.97.1', '141.101.113.1',
];

bool _autoScanRunning = false;
bool _autoScanStop = false;
const String _autoScanCdnCursorKey = 'auto_scan_cdn_cursors_v1';
const String _autoScanDomainCursorKey = 'auto_scan_domain_cursor_v1';
const String _autoScanPortCursorKey = 'auto_scan_port_cursor_v1';
const int _autoScanCdnBatchSize = 8;
const int _autoScanDomainBatchSize = 18;
const int _autoScanPortBatchSize = 24; // full SNI/port/TLS pass fits the shared four-minute budget

// SNI discovery checks endpoint-level HTTPS reachability. It does NOT prove
// that the Android VPN tunnel carries this traffic; only the core/TUN validation
// in the connection path can promote a server to a usable route.
Future<int?> _autoSniOk(String ip, int port, String sni) async {
  final sw = Stopwatch()..start();
  Socket? raw;
  SecureSocket? secure;
  try {
    raw = await Socket.connect(ip, port, timeout: const Duration(seconds: 4));
    secure = await SecureSocket.secure(
      raw,
      host: sni,
      supportedProtocols: const ['http/1.1'],
      onBadCertificate: (_) => true,
    ).timeout(const Duration(seconds: 4));
    secure.write(
      'GET / HTTP/1.1\r\n'
      'Host: $sni\r\n'
      'User-Agent: KING-VPN-Connectivity-Probe/1.0\r\n'
      'Accept: */*\r\n'
      'Connection: close\r\n\r\n',
    );
    await secure.flush().timeout(const Duration(seconds: 3));
    final statusLine = await utf8.decoder
        .bind(secure)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 4));
    final match = RegExp(r'^HTTP/1\.[01]\s+(\d{3})').firstMatch(statusLine);
    final status = int.tryParse(match?.group(1) ?? '');
    if (status == null || status < 200 || status >= 400) return null;
    return sw.elapsedMilliseconds;
  } catch (_) {
    return null;
  } finally {
    try { secure?.destroy(); } catch (e, st) { logError(e, st); }
    try { raw?.destroy(); } catch (e, st) { logError(e, st); }
  }
}

// ALPN (پروتکل لایه‌ی TLS): خروجی خود نام پروتکل است، مثل h2 یا http/1.1
Future<String?> _autoAlpnOk(String ip, String sni, String alpn) async {
  Socket? raw;
  SecureSocket? secure;
  try {
    raw = await Socket.connect(ip, 443, timeout: const Duration(seconds: 4));
    secure = await SecureSocket.secure(raw,
        host: sni,
        supportedProtocols: [alpn],
        onBadCertificate: (_) => true)
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
    final socket = await Socket.connect(
      ip,
      port,
      timeout: const Duration(milliseconds: 1500),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

// Port reachability is limited to the exact host:port pairs present in
// saved server configurations. Never sweep arbitrary ports across public CDN/IP ranges.
Future<Map<int, List<String>>> _autoConfiguredPortTargets(
    {bool Function()? cancelled}) async {
  final byPort = <int, Set<String>>{};
  for (final entry in _goldSrv.values) {
    if (cancelled?.call() ?? false) break;
    final server = Server.parse(entry.link);
    if (server == null || server.port < 1 || server.port > 65535) continue;
    final addresses = server.isIp
        ? <String>[server.host]
        : await nipResolveAll(server.host);
    if (cancelled?.call() ?? false) break;
    for (final address in addresses) {
      final parsed = InternetAddress.tryParse(address);
      if (parsed == null ||
          (parsed.type != InternetAddressType.IPv4 &&
              parsed.type != InternetAddressType.IPv6)) continue;
      (byPort[server.port] ??= <String>{}).add(parsed.address);
    }
  }
  return <int, List<String>>{
    for (final entry in byPort.entries)
      entry.key: (entry.value.toList()..sort()),
  };
}

/// Resolve the project's SNI names to both IPv4 and IPv6 endpoints in small cancellable batches.
/// The hostname remains the TLS SNI; only the TCP destination is the AAAA address.
Future<List<String>> _autoResolveDualStackTargets({required List<String> domains, bool Function()? cancelled}) async {
  final out = <String>{};
  const batchSize = 4;
  for (var offset = 0; offset < domains.length; offset += batchSize) {
    if (cancelled?.call() ?? false) break;
    final batch = domains.skip(offset).take(batchSize);
    final resolved = await Future.wait(batch.map((domain) async {
      try {
        return await InternetAddress.lookup(
          domain,
          type: InternetAddressType.any,
        ).timeout(const Duration(seconds: 2));
      } catch (_) {
        return const <InternetAddress>[];
      }
    }));
    if (cancelled?.call() ?? false) break;
    for (final addresses in resolved) {
      for (final address in addresses) {
        if ((address.type == InternetAddressType.IPv4 ||
                address.type == InternetAddressType.IPv6) &&
            !_privateIp(address)) {
          out.add(address.address);
        }
      }
    }
  }
  return out.toList(growable: false);
}

Future<void> autoScanRun(void Function(String) say,
    {bool Function()? isVpnActive, bool Function()? isVpnWanted}) async {
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
  // Chunking and persisted cursors, not a wall-clock cutoff, govern scan progress.
  // Socket timeouts and bounded concurrency protect the device while later runs
  // resume the complete inventory.
  bool cancelled() =>
      _autoScanStop || vpnActive() || vpnWanted() || nationalMode != scanNationalMode;
  String cancellationMessage() =>
      (vpnActive() || vpnWanted())
          ? 'با شروع اتصال VPN، اسکن برای جلوگیری از تداخل متوقف شد؛ پیشرفت دستهٔ کامل‌شده حفظ می‌شود'
          : 'اسکن متوقف شد؛ پیشرفت دستهٔ کامل‌شده حفظ می‌شود';
  try {
    await goldLoad();
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    // Keep the discovered pool and CDN inventory independent, then rotate
    // through every configured CDN range with persisted per-range cursors.
    // Each run handles a memory-safe slice; later runs resume at the next IP.
    final base = [for (final entry in _goldIps.values) entry.ip];
    final prefs = await SharedPreferences.getInstance();
    final savedCursorJson = prefs.getString(_autoScanCdnCursorKey);
    final cdnCursors = <String, dynamic>{};
    if (savedCursorJson != null && savedCursorJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedCursorJson);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.value is num || entry.value is String) {
              cdnCursors['${entry.key}'] = entry.value;
            }
          }
        }
      } catch (e, stk) {
        logError(e, stk);
      }
    }
    final stagedCdnCursors = Map<String, dynamic>.of(cdnCursors);
    // Use the entire project domain inventory, not only the small seed list.
    // A persisted last-domain cursor rotates through it across completed runs.
    // SNI inventory is federated from independent project sources: dedicated
    // SNI seeds, the complete DNS/domain catalog, front-SNI candidates, relay
    // hosts, and hostnames already present in the saved working server pool.
    // A failed handshake never removes a name; the persisted cursor rotates
    // through the complete merged inventory on subsequent completed runs.
    final domainSources = <String>{
      ...kAutoSniDomains,
      ...dnsxFullDomains(),
      ...natFrontSnis,
      ...natRelayHosts,
    };
    for (final entry in _goldSrv.values) {
      final server = Server.parse(entry.link);
      if (server != null && !server.isIp) domainSources.add(server.host);
    }
    final domainInventory = domainSources
        .map((domain) => domain.trim().toLowerCase())
        .where((domain) => domain.isNotEmpty && domain.contains('.'))
        .toList()..sort();
    final savedDomainCursor = prefs.getString(_autoScanDomainCursorKey);
    final previousDomainIndex = savedDomainCursor == null
        ? -1
        : domainInventory.indexOf(savedDomainCursor);
    final domainStart = previousDomainIndex < 0
        ? 0
        : (previousDomainIndex + 1) % domainInventory.length;
    final domainBatch = <String>[
      for (var i = 0; i < min(_autoScanDomainBatchSize, domainInventory.length); i++)
        domainInventory[(domainStart + i) % domainInventory.length],
    ];
    final stagedDomainCursor = domainBatch.isEmpty ? savedDomainCursor : domainBatch.last;
    // Port candidates come only from exact endpoints in saved server configs.
    // The scanner must not sweep 65,535 ports over unrelated public/CDN hosts.
    final configuredPortTargets = await _autoConfiguredPortTargets(
      cancelled: cancelled,
    );
    final priorityPorts = <int>{
      ...kAutoPorts.where(configuredPortTargets.containsKey),
    };
    final portInventory = <int>{
      ...priorityPorts,
      ...configuredPortTargets.keys,
    }.toList()..sort();
    final savedPortCursor = prefs.getInt(_autoScanPortCursorKey) ?? 0;
    final previousPortIndex = portInventory.indexOf(savedPortCursor);
    final portStart = previousPortIndex < 0
        ? 0
        : (previousPortIndex + 1) % portInventory.length;
    final portBatch = <int>[
      for (var i = 0; i < min(_autoScanPortBatchSize, portInventory.length); i++)
        portInventory[(portStart + i) % portInventory.length],
    ];
    final stagedPortCursor = portBatch.isEmpty ? savedPortCursor : portBatch.last;
    final cdnRanges = _liveCdnRanges.isNotEmpty ? _liveCdnRanges : [..._cfRanges, ..._cfRangesV6];
    unawaited(refreshCdnRanges());
    // Add AAAA answers from the same project SNI inventory. Combine exact
    // A/AAAA endpoints and CDN CIDRs in one fair cursor iterator so no source
    // is permanently starved by the order of a concatenated list.
    final dnsResolvedIps = await _autoResolveDualStackTargets(
      domains: domainBatch,
      cancelled: cancelled,
    );
    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    final targetRanges = <String>{
      ...base,
      ...dnsResolvedIps,
      ...cdnRanges,
      if (base.isEmpty && dnsResolvedIps.isEmpty && cdnRanges.isEmpty)
        ...kAutoFallbackIps,
    }.toList()..sort();
    final ips = _getCfIps(
      batchSize: _autoScanCdnBatchSize,
      liveRanges: targetRanges,
      cursors: stagedCdnCursors,
    );
    say('تست با ${ips.length} IP از IPv4 و IPv6 (پوشه جهانی / CDN مستقل از نت ملی)');

    // SNI: خروجی خود دامنه‌هاست. هر دامنه یک بار؛ به محض یک IP سالم، همان دامنه ثبت می‌شود
    final sniHits = <String>[];
    var n = 0;
    sniLoop:
    for (final d in domainBatch) {
      n++;
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break sniLoop;
      }
      var ok = false;
      // Bounded parallel probes reduce worst-case scan time without creating
      // an unbounded socket burst on low-memory/mobile networks.
      for (var offset = 0; offset < ips.length; offset += 8) {
        if (cancelled()) break sniLoop;
        final batch = ips.skip(offset).take(8);
        final checks = await Future.wait(
          batch.map((ip) => _autoSniOk(ip, 443, d)),
        );
        if (checks.any((latency) => latency != null)) {
          ok = true;
          break;
        }
      }
      if (ok) sniHits.add(d);
      say('SNI $n/${domainBatch.length} • سالم: ${sniHits.length}');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // پورت: خروجی خود شماره‌ی پورت است. هر پورت یک بار؛ به محض یک IP سالم، همان پورت ثبت می‌شود
    final portHits = <String>[];
    var m = 0;
    portLoop:
    for (final p in portBatch) {
      m++;
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break portLoop;
      }
      var ok = false;
      final portIps = configuredPortTargets[p] ?? const <String>[];
      // Probe only the configured server's resolved addresses on its declared port.
      for (var offset = 0; offset < portIps.length; offset += 8) {
        if (cancelled()) break portLoop;
        final batch = portIps.skip(offset).take(8);
        final checks = await Future.wait(
          batch.map((ip) => _autoPortOk(ip, p)),
        );
        if (checks.any((reachable) => reachable)) {
          ok = true;
          break;
        }
      }
      if (ok) portHits.add('$p');
      say('پورت $m/${portBatch.length} • سالم: ${portHits.length}');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // TLS/ALPN: خروجی نام پروتکل‌های TLS است؛ روی اولین دامنه‌ی سالم (یا پیش‌فرض) تست می‌شود
    final tlsHits = <String>[];
    final tlsSni = sniHits.isNotEmpty
        ? sniHits.first
        : (domainBatch.isNotEmpty ? domainBatch.first : 'www.google.com');
    for (final alpn in const ['h2', 'http/1.1']) {
      if (cancelled()) break;
      var ok = false;
      for (var offset = 0; offset < ips.length; offset += 8) {
        if (cancelled()) break;
        final batch = ips.skip(offset).take(8);
        final selected = await Future.wait(
          batch.map((ip) => _autoAlpnOk(ip, tlsSni, alpn)),
        );
        for (final protocol in selected.whereType<String>()) {
          if (protocol.isNotEmpty && !tlsHits.contains(protocol)) {
            tlsHits.add(protocol);
            ok = true;
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
    final saved = await goldAddScans(
      {'tls': tlsHits, 'sni': sniHits, 'port': portHits},
      shouldAbort: () => cancelled(),
    );
    if (!saved) {
      say(cancellationMessage());
      return;
    }
    // Advance the CDN inventory only after the scan results have been committed.
    await prefs.setString(_autoScanCdnCursorKey, jsonEncode(stagedCdnCursors));
    if (stagedDomainCursor != null) {
      await prefs.setString(_autoScanDomainCursorKey, stagedDomainCursor);
    }
    if (stagedPortCursor != null) {
      await prefs.setInt(_autoScanPortCursorKey, stagedPortCursor);
    }
    say('تمام شد: ${sniHits.length} نام SNI و ${portHits.length} پورتِ مربوط به endpointهای تنظیم‌شده ذخیره شد؛ این نتایج کاندیدا هستند، نه تأیید نهایی تونل.');
  } catch (e, stk) {
    logError(e, stk);
    say('خطا در اسکن خودکار');
  } finally {
    _autoScanRunning = false;
    dnsxManualBusy = false;
  }
}

Future<void> autoScanSheet(BuildContext context,
    {bool Function()? isVpnActive, bool Function()? isVpnWanted}) async {
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
              const Text('کشف SNI و بررسی پورت‌های تعریف‌شده در کانفیگ‌های ذخیره‌شده؛ تأیید نهایی مسیر فقط با عبور واقعی ترافیک از تونل انجام می‌شود.'),
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
                    isVpnActive: isVpnActive, isVpnWanted: isVpnWanted),
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
