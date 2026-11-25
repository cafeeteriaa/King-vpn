part of 'main.dart';

// AUTOSCAN: inventories for SNI/IP candidates are generated independently of saved servers.
// Active SNI/TLS/port validation remains limited to configured KING VPN endpoint scope.
// Candidate inventory is never presented as a verified endpoint or healthy tunnel.
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
// Domestic-mode discovery seeds. Do not mix global CDN/front-SNI catalogs into
// the national-network candidate inventory; those addresses are commonly
// unreachable during international isolation. Saved server hosts are added
// separately because they are actual user/project endpoint candidates.
const List<String> kAutoNationalSniDomains = [
  'digikala.com', 'www.digikala.com', 'aparat.com', 'www.aparat.com',
  'snapp.ir', 'www.snapp.ir', 'divar.ir', 'www.divar.ir',
  'telewebion.com', 'www.telewebion.com', 'tasnimnews.com', 'www.tasnimnews.com',
  'isna.ir', 'www.isna.ir', 'irna.ir', 'www.irna.ir',
  'mehrnews.com', 'www.mehrnews.com', 'khabaronline.com',
  'varzesh3.com', 'zoomit.ir', 'sheypoor.com', 'torob.com',
  'basalam.com', 'filimo.com', 'namava.ir',
  'irancell.ir', 'mci.ir', 'rightel.ir',
  'bale.ai', 'web.eitaa.com',
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
      // Keep platform certificate validation enabled for trustworthy SNI evidence.
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
    // Any syntactically valid HTTP status proves the TLS/SNI request reached
    // an HTTP-speaking peer. 4xx/5xx are application outcomes, not SNI failure.
    if (status == null || status < 100 || status > 599) return null;
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
        supportedProtocols: [alpn],
        // Use the platform trust store for ALPN evidence.
      )
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

/// Collect only the exact IP addresses of saved VPN server endpoints.
/// The full TCP port inventory is tested against these configured VPN hosts;
/// discovered public DNS/CDN ranges are never converted into port-scan targets.
Future<List<String>> _autoConfiguredServerIps({
  Iterable<Server>? servers,
  bool Function()? cancelled,
}) async {
  final addresses = <String>{};
  final configured = servers ??
      _goldSrv.values
          .map((entry) => Server.parse(entry.link))
          .whereType<Server>();
  for (final server in configured) {
    if (cancelled?.call() ?? false) break;
    final resolved = server.isIp
        ? <String>[server.host]
        : await nipResolveAll(server.host);
    if (cancelled?.call() ?? false) break;
    for (final value in resolved) {
      final parsed = InternetAddress.tryParse(value);
      if (parsed != null &&
          (parsed.type == InternetAddressType.IPv4 ||
              parsed.type == InternetAddressType.IPv6)) {
        addresses.add(parsed.address);
      }
    }
  }
  return addresses.toList()..sort();
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
        // Passive DNS inventory retains every valid A/AAAA observation,
        // including private, link-local and ULA addresses. Address scope is
        // evidence, not a discovery filter; active probes remain separately gated.
        if (address.type == InternetAddressType.IPv4 ||
            address.type == InternetAddressType.IPv6) {
          out.add(address.address);
        }
      }
    }
  }
  return out.toList(growable: false);
}

Future<void> autoScanRun(void Function(String) say,
    {required Iterable<Server> goodServers,
    required Iterable<Server> pendingServers,
    bool Function()? isVpnActive,
    bool Function()? isVpnWanted}) async {
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
    // Keep every previously discovered IP in both modes. National mode changes
    // ordering only; it never removes global observations from the inventory.
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
      ...kAutoNationalSniDomains,
      ...kAutoSniDomains,
      ...dnsxFullDomains(),
      ...natFrontSnis,
      ...natRelayHosts,
    };
    final nationalEndpointServers = <Server>{
      ...natTemplateSeeds,
      ...goodServers,
      ...pendingServers,
    };
    final configuredSniServers = <Server>{...nationalEndpointServers};
    if (!scanNationalMode) {
      for (final entry in _goldSrv.values) {
        final server = Server.parse(entry.link);
        if (server != null) configuredSniServers.add(server);
      }
    }
    for (final server in configuredSniServers) {
      if (!server.isIp) domainSources.add(server.host);
    }
    final domainInventory = scanNationalMode
        ? dnsxNationalFirstDomains(extra: domainSources)
        : (domainSources
            .map((domain) => domain.trim().toLowerCase())
            .where((domain) => domain.isNotEmpty && domain.contains('.'))
            .toList()..sort());
    final savedDomainCursor = prefs.getString(_autoScanDomainCursorKey);
    final previousDomainIndex = savedDomainCursor == null
        ? -1
        : domainInventory.indexOf(savedDomainCursor);
    final domainStart = previousDomainIndex < 0
        ? 0
        : (previousDomainIndex + 1) % domainInventory.length;
    final domainBatch = <String>[
      for (var i = 0; i < domainInventory.length; i++)
        domainInventory[(domainStart + i) % domainInventory.length],
    ];
    final stagedDomainCursor = domainBatch.isEmpty ? savedDomainCursor : domainBatch.last;
    // Keep the full TCP port-number inventory (1..65535), independently
    // of the smaller set of ports already present in saved configs. Active
    // TCP checks use only exact IPs of saved VPN server endpoints.
    final portTargetIps = await _autoConfiguredServerIps(
      servers: scanNationalMode ? nationalEndpointServers : null,
      cancelled: cancelled,
    );
    final portInventory = natBuildFullPortInventory(kAutoPorts);
    final savedPortCursor = prefs.getInt(_autoScanPortCursorKey) ?? 0;
    final previousPortIndex = portInventory.indexOf(savedPortCursor);
    final portStart = previousPortIndex < 0
        ? 0
        : (previousPortIndex + 1) % portInventory.length;
    final portBatch = <int>[
      for (var i = 0; i < portInventory.length; i++)
        portInventory[(portStart + i) % portInventory.length],
    ];
    final stagedPortCursor = portBatch.isEmpty ? savedPortCursor : portBatch.last;
    // Refresh and retain CDN ranges in both modes. National-first ordering is
    // applied to domains and DNS observations; it does not discard global IP
    // or CDN inventory when the selected network is domestic.
    unawaited(refreshCdnRanges());
    final cdnRanges = _liveCdnRanges.isNotEmpty
        ? _liveCdnRanges
        : [..._cfRanges, ..._cfRangesV6];
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
    // Preserve source order: national-first DNS answers, then the complete
    // saved IP pool, then CDN ranges. Set insertion order deduplicates without
    // sorting away the domestic-first priority.
    final targetRanges = <String>{
      ...dnsResolvedIps,
      ...base,
      ...cdnRanges,
      if (base.isEmpty && dnsResolvedIps.isEmpty && cdnRanges.isEmpty)
        ...kAutoFallbackIps,
    }.toList();
    final ips = _getCfIps(
      batchSize: _autoScanCdnBatchSize,
      liveRanges: targetRanges,
      cursors: stagedCdnCursors,
    );
    final discoveredIpCandidates = <String>{
      ...base,
      ...dnsResolvedIps,
      ...ips,
    }.toList()..sort();
    say('موجودی مستقل کشف شد: ${domainInventory.length} دامنه و ${discoveredIpCandidates.length} IP کاندیدا (بدون تأیید اتصال)');

    // Passive DNS discovery covers the full domain inventory above. Active
    // TLS/SNI probes are narrower: only exact host:port endpoints in saved VPN
    // configurations are contacted, using each configuration's declared SNI.
    final sniTargets = <String, Set<String>>{};
    for (final server in configuredSniServers) {
      if (cancelled()) break;
      final host = server.host.trim();
      final sni = server.sni.trim().isNotEmpty ? server.sni.trim() : host;
      if (host.isEmpty || sni.isEmpty || server.port < 1 || server.port > 65535) continue;
      final resolved = await _autoResolveDualStackTargets(
        domains: [host],
        cancelled: cancelled,
      );
      final targets = sniTargets.putIfAbsent(sni, () => <String>{});
      for (final ip in resolved) {
        targets.add('$ip|${server.port}');
      }
    }

    final sniHits = <String>[];
    var n = 0;
    for (final entry in sniTargets.entries) {
      n++;
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break;
      }
      var ok = false;
      final endpoints = entry.value.toList(growable: false);
      for (var offset = 0; offset < endpoints.length; offset += 4) {
        if (cancelled()) break;
        final batch = endpoints.skip(offset).take(4);
        final checks = await Future.wait(batch.map((endpoint) async {
          final parts = endpoint.split('|');
          if (parts.length != 2) return null;
          final port = int.tryParse(parts[1]);
          if (port == null) return null;
          return _autoSniOk(parts[0], port, entry.key);
        }));
        if (checks.any((latency) => latency != null)) {
          ok = true;
          break;
        }
      }
      if (ok) sniHits.add(entry.key);
      say('SNI endpoint $n/${sniTargets.length} • پاسخ HTTPS (کانفیگ‌شده): ${sniHits.length}');
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
      final portIps = portTargetIps;
      // Probe each TCP port only on exact saved VPN server IPs, never on
      // arbitrary discovered CDN/DNS/public address ranges.
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
      say('پورت TCP $m/${portBatch.length} از موجودی کامل ۱..۶۵۵۳۵ • کاندیدا: ${portHits.length}');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }

    // ALPN probes use the same exact configured host:port/SNI tuples.
    final tlsHits = <String>[];
    for (final alpn in const ['h2', 'http/1.1']) {
      if (cancelled()) break;
      var ok = false;
      for (final entry in sniTargets.entries) {
        final endpoints = entry.value.toList(growable: false);
        for (var offset = 0; offset < endpoints.length; offset += 4) {
          if (cancelled()) break;
          final batch = endpoints.skip(offset).take(4);
          final selected = await Future.wait(batch.map((endpoint) async {
            final parts = endpoint.split('|');
            if (parts.length != 2) return null;
            final port = int.tryParse(parts[1]);
            if (port == null) return null;
            return _autoAlpnOk(parts[0], port, entry.key, alpn);
          }));
          for (final protocol in selected.whereType<String>()) {
            if (protocol.isNotEmpty && !tlsHits.contains(protocol)) {
              tlsHits.add(protocol);
              ok = true;
            }
          }
          if (ok) break;
        }
        if (ok) break;
      }
      if (ok) say('TLS/ALPN مشاهده شد: $alpn (کانفیگ‌شده)');
    }

    if (cancelled()) {
      say(cancellationMessage());
      return;
    }
    // Commit the three result groups together only after every scan phase completes.
    final saved = await goldAddScans(
      {
        'tls': tlsHits,
        'sni': sniHits,
        'port': portHits,
        // Passive discovery candidates are persisted even when no saved VPN
        // server exists; they are separate from actively verified SNI/IP data.
        'sni_candidates': domainInventory,
        'ip_candidates': discoveredIpCandidates,
      },
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
    say('تمام شد: ${domainInventory.length} دامنه و ${discoveredIpCandidates.length} IP کاندیدا مستقل ذخیره شد؛ ${sniHits.length} SNI و ${portHits.length} پورت نیز در محدودهٔ سرورهای تنظیم‌شده بررسی شدند. کاندیداها تأیید اتصال یا تونل نیستند.');
  } catch (e, stk) {
    logError(e, stk);
    say('خطا در اسکن خودکار');
  } finally {
    _autoScanRunning = false;
    dnsxManualBusy = false;
  }
}

Future<void> autoScanSheet(BuildContext context,
    {required Iterable<Server> goodServers,
    required Iterable<Server> pendingServers,
    bool Function()? isVpnActive,
    bool Function()? isVpnWanted}) async {
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
              const Text('کشف منابع SNI و بررسی چرخشی تمام پورت‌های TCP (۱ تا ۶۵۵۳۵) فقط روی IP میزبان‌های VPN ذخیره‌شده؛ موجودی UDP نیز جداگانه نگهداری می‌شود و تست آن باید پروتکل‌محور باشد. تأیید نهایی مسیر فقط با عبور واقعی ترافیک از تونل انجام می‌شود.'),
              const SizedBox(height: 8),
              Text(status),
              const SizedBox(height: 8),
              Text('کاندیدای SNI: ${(_goldScan['sni_candidates'] ?? const []).length} • کاندیدای IP: ${(_goldScan['ip_candidates'] ?? const []).length}'),
              Text('SNI پاسخ‌داده: ${(_goldScan['sni'] ?? const []).length} • پورت TCP پاسخ‌داده: ${(_goldScan['port'] ?? const []).length} • ALPN: ${(_goldScan['tls'] ?? const []).length}'),
              // SCANSHOW: نتایج همین‌جا روی صفحه با دکمه‌ی کپی
              for (final k in const ['sni_candidates', 'ip_candidates', 'sni', 'port', 'tls'])
                if ((_goldScan[k] ?? const <String>[]).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text({
                    'sni_candidates': 'دامنه‌های SNI کشف‌شده (تأییدنشده):',
                    'ip_candidates': 'IPهای کشف‌شده (تأییدنشده):',
                    'sni': 'SNIهای دارای پاسخ HTTPS روی سرورهای تنظیم‌شده:',
                    'port': 'پورت‌های دارای پاسخ TCP روی IPهای تنظیم‌شده:',
                    'tls': 'پروتکل‌های TLS مشاهده‌شده:',
                  }[k]!),
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
                    goodServers: goodServers,
                    pendingServers: pendingServers,
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
