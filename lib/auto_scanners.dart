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
const String _autoScanCheckpointKey = 'auto_scan_checkpoint_v2';

typedef AutoScanCheckpoint = ({
  Map<String, dynamic> cdn,
  String? domain,
  int? port,
});

/// Decode the unified scan checkpoint, migrating the legacy per-cursor keys
/// when no valid v2 checkpoint exists. The returned map is detached from the
/// decoded JSON object so later staging cannot mutate persisted state.
AutoScanCheckpoint kingDecodeAutoScanCheckpoint({
  required String? encoded,
  String? legacyCdnJson,
  String? legacyDomain,
  int? legacyPort,
}) {
  Map<String, dynamic> decodeCdn(Object? value) {
    final result = <String, dynamic>{};
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.value is num || entry.value is String) {
          result['${entry.key}'] = entry.value;
        }
      }
    }
    return result;
  }

  Map<String, dynamic> legacyCdn = <String, dynamic>{};
  if (legacyCdnJson != null && legacyCdnJson.isNotEmpty) {
    try {
      legacyCdn = decodeCdn(jsonDecode(legacyCdnJson));
    } catch (_) {
      // A corrupt legacy CDN cursor must not prevent domain/port recovery.
    }
  }

  if (encoded != null && encoded.isNotEmpty) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map && decoded['version'] == 2) {
        final cdn = decodeCdn(decoded['cdn']);
        final hasCdn = decoded['cdn'] is Map;
        final domainValue = decoded['domain'];
        final portValue = decoded['port'];
        final domain = decoded.containsKey('domain')
            ? (domainValue is String ? domainValue : null)
            : legacyDomain;
        final port = decoded.containsKey('port')
            ? (portValue is num &&
                    portValue.toInt() >= 1 &&
                    portValue.toInt() <= 65535
                ? portValue.toInt()
                : null)
            : legacyPort;
        return (
          cdn: hasCdn ? cdn : legacyCdn,
          domain: domain,
          port: port,
        );
      }
    } catch (_) {
      // Fall back to legacy keys; never replace them with an empty checkpoint.
    }
  }
  return (cdn: legacyCdn, domain: legacyDomain, port: legacyPort);
}

/// Encode all auto-scan cursors in one preference value. One write makes the
/// three independent inventories advance together or not at all.
String kingEncodeAutoScanCheckpoint({
  required Map<String, dynamic> cdn,
  required String? domain,
  required int? port,
}) =>
    jsonEncode({
      'version': 2,
      'cdn': cdn,
      'domain': domain,
      'port': port,
    });

/// Return the next fair, wrapping slice from a complete inventory.
///
/// [batchSize] limits work in one execution only; it never truncates the
/// supplied inventory. An unknown/stale cursor safely restarts at the first
/// item, and an empty inventory never performs modulo arithmetic.
List<T> kingNextInventoryBatch<T>(
  Iterable<T> inventory, {
  required int batchSize,
  T? lastValue,
}) {
  if (batchSize <= 0) return const <T>[];
  final items = inventory.toList(growable: false);
  if (items.isEmpty) return const <T>[];
  final previousIndex = lastValue == null ? -1 : items.indexOf(lastValue);
  final start = previousIndex < 0 ? 0 : (previousIndex + 1) % items.length;
  final count = min(batchSize, items.length);
  return List<T>.unmodifiable([
    for (var offset = 0; offset < count; offset++)
      items[(start + offset) % items.length],
  ]);
}

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
      // Keep platform certificate validation enabled. A probe must not treat
      // an invalid or self-signed certificate as trusted reachability evidence.
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
    secure = await SecureSocket.secure(
      raw,
      host: sni,
      supportedProtocols: [alpn],
      // Use the platform trust store. ALPN discovery is not allowed to
      // classify an invalid or self-signed certificate as trusted TLS evidence.
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
    final savedCheckpoint = kingDecodeAutoScanCheckpoint(
      encoded: prefs.getString(_autoScanCheckpointKey),
      legacyCdnJson: prefs.getString(_autoScanCdnCursorKey),
      legacyDomain: prefs.getString(_autoScanDomainCursorKey),
      legacyPort: prefs.getInt(_autoScanPortCursorKey),
    );
    final stagedCdnCursors =
        Map<String, dynamic>.of(savedCheckpoint.cdn);
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
    if (scanNationalMode) {
      for (final server in nationalEndpointServers) {
        if (!server.isIp) domainSources.add(server.host);
      }
    } else {
      for (final entry in _goldSrv.values) {
        final server = Server.parse(entry.link);
        if (server != null && !server.isIp) domainSources.add(server.host);
      }
    }
    // Both modes share exactly the same hostname validation and IP-literal
    // exclusion. National mode changes ordering only; it never narrows the
    // global inventory or bypasses normalization.
    final domainInventory = scanNationalMode
        ? dnsxNationalFirstDomains(extra: domainSources)
        : (kingNormalizeDomainHosts(domainSources)..sort());
    final savedDomainCursor = savedCheckpoint.domain;
    final domainBatch = kingNextInventoryBatch(
      domainInventory,
      batchSize: _autoScanDomainBatchSize,
      lastValue: savedDomainCursor,
    );
    final stagedDomainCursor = domainBatch.isEmpty ? savedDomainCursor : domainBatch.last;
    // Keep the full TCP port-number inventory (1..65535), independently
    // of the smaller set of ports already present in saved configs. Active
    // TCP checks use only exact IPs of saved VPN server endpoints.
    final portTargetIps = await _autoConfiguredServerIps(
      servers: scanNationalMode ? nationalEndpointServers : null,
      cancelled: cancelled,
    );
    final portInventory = natBuildFullPortInventory(kAutoPorts);
    final savedPortCursor = savedCheckpoint.port ?? 0;
    final portBatch = kingNextInventoryBatch(
      portInventory,
      batchSize: _autoScanPortBatchSize,
      lastValue: savedPortCursor,
    );
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

    // Probe each domain only at its own DNS-resolved A/AAAA addresses.
    // This no longer depends on saved VPN configurations; DNS observations
    // are used for ordinary HTTPS/SNI reachability on TCP/443, not port sweeps.
    final sniHits = <String>[];
    final sniTargets = <String, List<String>>{};
    var n = 0;
    sniLoop:
    for (final d in domainBatch) {
      n++;
      if (scanNationalMode) {
        await natManualYield(shouldAbort: () => cancelled());
        if (cancelled()) break sniLoop;
      }
      final resolved = await _autoResolveDualStackTargets(
        domains: [d],
        cancelled: cancelled,
      );
      sniTargets[d] = resolved;
      var ok = false;
      for (var offset = 0; offset < resolved.length; offset += 4) {
        if (cancelled()) break sniLoop;
        final batch = resolved.skip(offset).take(4);
        final checks = await Future.wait(
          batch.map((ip) => _autoSniOk(ip, 443, d)),
        );
        if (checks.any((latency) => latency != null)) {
          ok = true;
          break;
        }
      }
      if (ok) sniHits.add(d);
      say('SNI $n/${domainBatch.length} • پاسخ HTTPS (کاندیدا): ${sniHits.length}');
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

    // ALPN is checked against the DNS-resolved addresses for the same SNI.
    // No saved server record is required for this independent TLS inventory.
    final tlsHits = <String>[];
    for (final alpn in const ['h2', 'http/1.1']) {
      if (cancelled()) break;
      var ok = false;
      for (final d in domainBatch) {
        final targetIps = sniTargets[d] ?? const <String>[];
        for (var offset = 0; offset < targetIps.length; offset += 4) {
          if (cancelled()) break;
          final batch = targetIps.skip(offset).take(4);
          final selected = await Future.wait(
            batch.map((ip) => _autoAlpnOk(ip, 443, d, alpn)),
          );
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
      if (ok) say('TLS/ALPN مشاهده شد: $alpn (کاندیدا)');
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
    // One preference write commits CDN, domain and port progress together.
    // If it fails, the previous checkpoint remains authoritative and the
    // already-saved observations can safely be rediscovered on the next run.
    final checkpointSaved = await prefs.setString(
      _autoScanCheckpointKey,
      kingEncodeAutoScanCheckpoint(
        cdn: stagedCdnCursors,
        domain: stagedDomainCursor,
        port: stagedPortCursor,
      ),
    );
    if (!checkpointSaved) {
      say('ذخیرهٔ نقطهٔ ادامهٔ اسکن انجام نشد؛ Cursor قبلی حفظ شد و اجرای بعدی دوباره بررسی می‌کند.');
      return;
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
