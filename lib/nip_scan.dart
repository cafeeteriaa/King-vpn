part of 'main.dart';

// NIP SCAN ===================================================================
// پیدا کردن IP های باز در ایران با TCP (بدون دانلود، حجم تقریباً صفر)،
// و امتحان کانفیگ‌های خود کاربر روی آن IP ها (روش IP تمیز).

class NipHit {
  final String ip;
  final int ms;
  const NipHit(this.ip, this.ms);
}

/// بلوک CIDR مثل «5.160.0.0/16» را به فهرست IP تبدیل می‌کند.
/// برای بلوک‌های بزرگ فقط [maxPerBlock] آدرس پراکنده برمی‌گرداند.
List<String> nipExpandCidr(String cidr, {int maxPerBlock = 4096}) {
  if (maxPerBlock <= 0) return const <String>[];
  final parts = cidr.trim().split('/');
  if (parts.length == 2) {
    final address = InternetAddress.tryParse(parts[0].trim());
    if (address?.type == InternetAddressType.IPv4) {
      return natExpandCidr(cidr, maxPerBlock: maxPerBlock);
    }
    if (address?.type == InternetAddressType.IPv6) {
      return natExpandIpv6Cidr(cidr, maxPerBlock: maxPerBlock);
    }
  }
  return natExpandIpRangeCursor(
    cidr,
    '0',
    maxPerBlock: maxPerBlock,
  ).addresses;
}

/// اتصال TCP به ip:port. اگر جواب داد زمان پاسخ (ms) را برمی‌گرداند، وگرنه null.
Future<int?> nipTcpProbe(String ip, int port, Duration timeout) async {
  final sw = Stopwatch()..start();
  try {
    final s = await Socket.connect(ip, port, timeout: timeout);
    sw.stop();
    s.destroy();
    return sw.elapsedMilliseconds;
  } catch (_) {
    return null;
  }
}

/// اسکن هم‌زمان. با رسیدن به [want] نتیجه، یا پایان [budget]، یا [cancelled] = true متوقف می‌شود.
Future<List<NipHit>> nipScan(
  List<String> ips, {
  int port = 443,
  int concurrency = 16,
  int? want,
  Duration budget = const Duration(minutes: 2),
  Duration timeout = const Duration(milliseconds: 1500),
  bool Function()? cancelled,
  void Function(int done, int total)? onProgress,
}) async {
  final hits = <NipHit>[];
  final clock = Stopwatch()..start();
  var next = 0;
  var done = 0;

  Future<void> worker() async {
    while (true) {
      if (want != null && hits.length >= want) return;
      if (cancelled != null && cancelled()) return;
      if (clock.elapsed >= budget) return;
      if (next >= ips.length) return;
      final ip = ips[next++];
      final ms = await nipTcpProbe(ip, port, timeout);
      if (cancelled != null && cancelled()) return;
      if (ms != null && (want == null || hits.length < want)) hits.add(NipHit(ip, ms));
      done++;
      onProgress?.call(done, ips.length);
    }
  }

  final n = min(concurrency.clamp(1, 16), max(ips.length, 1)).toInt();
  await Future.wait(List.generate(n, (_) => worker()));
  onProgress?.call(done, ips.length);
  natStableSort(hits, (a, b) => a.ms.compareTo(b.ms));
  return hits;
}

const String _nipHuntCursorKey = 'nip_hunt_range_cursors_v1';

Future<Map<String, dynamic>> _nipLoadHuntCursors() async {
  final prefs = await SharedPreferences.getInstance();
  final cursors = <String, dynamic>{};
  final raw = prefs.getString(_nipHuntCursorKey);
  if (raw != null && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.value is String || entry.value is num) {
            cursors['${entry.key}'] = entry.value;
          }
        }
      }
    } catch (e, stk) {
      logError(e, stk);
    }
  }
  return cursors;
}

Future<void> _nipSaveHuntCursors(Map<String, dynamic> cursors) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_nipHuntCursorKey, jsonEncode(cursors));
}

/// Fair, resumable dual-stack range iterator. Batch size controls this run's
/// memory/time only; every prefix and every 128-bit address offset is retained.
({List<String> addresses, Map<String, dynamic> cursors}) _nipRangeBatch(
  List<String> ranges,
  Map<String, dynamic> saved, {
  required String namespace,
  int batchSize = 1000,
}) {
  final cursors = Map<String, dynamic>.of(saved);
  if (ranges.isEmpty || batchSize <= 0) {
    return (addresses: const <String>[], cursors: cursors);
  }
  final start = natCursorIndex(cursors['__nip_${namespace}_range_cursor'], ranges.length);
  final out = <String>{};
  var visited = 0;
  for (; visited < ranges.length && out.length < batchSize; visited++) {
    final index = (start + visited) % ranges.length;
    final range = ranges[index];
    final remaining = batchSize - out.length;
    final rangesLeft = ranges.length - visited;
    final quota = max(1, (remaining + rangesLeft - 1) ~/ rangesLeft);
    final batch = natExpandIpRangeCursor(
      range,
      cursors['$namespace:$range']?.toString() ?? '0',
      maxPerBlock: quota,
    );
    if (batch.addresses.isEmpty) continue;
    out.addAll(batch.addresses);
    cursors['$namespace:$range'] = batch.nextCursor;
  }
  if (visited > 0) {
    cursors['__nip_${namespace}_range_cursor'] = (start + visited) % ranges.length;
  }
  return (addresses: out.toList(growable: false), cursors: cursors);
}

/// IPv4 and IPv6 prefixes announced for Iran by RIPE, cached together.
Future<List<String>> nipIranCidrs() async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getStringList('plus_ir_cidr_v2');
  if (cached != null && cached.isNotEmpty) return cached;
  final legacyV4 = prefs.getStringList('plus_ir_cidr') ?? const <String>[];
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client
        .getUrl(Uri.parse(
            'https://stat.ripe.net/data/country-resource-list/data.json?resource=IR'))
        .timeout(const Duration(seconds: 15));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map) return legacyV4;
    final data = decoded['data'];
    final resources = data is Map ? data['resources'] : null;
    if (resources is! Map) return legacyV4;
    final ipv4 = resources['ipv4'];
    final ipv6 = resources['ipv6'];
    final ranges = <String>{
      ...legacyV4,
      if (ipv4 is List) ...ipv4.map((value) => '$value').where((value) => value.contains('/')),
      if (ipv6 is List) ...ipv6.map((value) => '$value').where((value) => value.contains('/')),
    }.toList(growable: false);
    if (ranges.isNotEmpty) await prefs.setStringList('plus_ir_cidr_v2', ranges);
    return ranges;
  } catch (_) {
    return legacyV4;
  } finally {
    client.close(force: true);
  }
}

/// همان کانفیگ سرور [t] را روی IP دیگری می‌سازد؛ SNI و Host اصلی حفظ می‌شوند.
String? nipSwapLink(Server t, String ip) {
  final l = t.link;
  final lower = l.toLowerCase();
  if (lower.startsWith('ss://')) return null;
  try {
    if (lower.startsWith('vmess://')) {
      var b = natB64Normalize(l.substring(8));
      final j = jsonDecode(utf8.decode(base64.decode(b)));
      j['add'] = ip;
      if ((j['sni'] ?? '').toString().isEmpty) j['sni'] = t.host;
      if ((j['host'] ?? '').toString().isEmpty && j['net'] == 'ws') {
        j['host'] = t.host;
      }
      return 'vmess://${base64.encode(utf8.encode(jsonEncode(j)))}';
    }
    final u = Uri.parse(l);
    final q = Map<String, String>.from(u.queryParameters);
    if ((q['sni'] ?? '').isEmpty) q['sni'] = t.host;
    if (q['type'] == 'ws' && (q['host'] ?? '').isEmpty) q['host'] = t.host;
    return u.replace(host: ip, queryParameters: q).toString();
  } catch (_) {
    return null;
  }
}

// CHAINHUNT: کمک‌های جستجوی IP (پشت هم، هرکدام جواب داد همان استفاده می‌شود)
// آدرس واسط (relay) که خودت اضافه می‌کنی: IP سرور داخلی/واسط با همان پورت سرور.
// مثال: const natRelayHosts = <String>['1.2.3.4'];
List<String> natRelayHosts = <String>[];

// RELAYHOSTS: واسط‌های IP که کاربر اضافه می‌کند
Future<void> natRelayHostsLoad() async {
  try {
    final p = await SharedPreferences.getInstance();
    natRelayHosts = p.getStringList('nat_relay_hosts') ?? <String>[];
  } catch (e, st) {
    logError(e, st);
  }
}

Future<void> natRelayHostsSave(String text) async {
  natRelayHosts = text
      .split(RegExp(r'[\r\n\s]+'))
      .where((x) => InternetAddress.tryParse(x) != null)
      .toList();
  try {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('nat_relay_hosts', natRelayHosts);
  } catch (e, st) {
    logError(e, st);
  }
}

Future<List<String>> nipResolveAll(String host) async {
  final literal = InternetAddress.tryParse(host.trim());
  if (literal != null) return [literal.address];
  // Preserve the existing global-mode DoH preference, then collect all system
  // A/AAAA answers so both address families can feed ASN discovery.
  final doh = NatNetworkDiagnosis.preferDomestic
      ? const <String>[]
      : await dohResolveAll(host);
  final out = <String>{...doh};
  try {
    final addresses = await InternetAddress.lookup(host)
        .timeout(const Duration(seconds: 5));
    for (final address in addresses) {
      if (address.type == InternetAddressType.IPv4 ||
          address.type == InternetAddressType.IPv6) {
        out.add(address.address);
      }
    }
  } catch (_) {}
  return out.toList(growable: false);
}

Future<String?> nipResolve(String host) async {
  final addresses = await nipResolveAll(host);
  return addresses.isEmpty ? null : addresses.first;
}

/// بلوک‌های هاست یک IP را برای نت ملی ذخیره می‌کند (کلید: IP).
Future<void> natPrefetchAsn(List<Server> list) async {
  final hosts = list.where((server) => !server.cdn).toList(growable: false);
  final ips = <String>{};
  for (var offset = 0; offset < hosts.length; offset += 8) {
    final batch = hosts.skip(offset).take(8);
    final resolved = await Future.wait(batch.map((server) async {
      if (server.isIp) return <String>[server.host];
      return nipResolveAll(server.host);
    }));
    for (final addresses in resolved) {
      ips.addAll(addresses);
    }
  }
  final allIps = ips.toList(growable: false);
  for (var offset = 0; offset < allIps.length; offset += 4) {
    final batch = allIps.skip(offset).take(4);
    await Future.wait(batch.map((ip) async {
      await nipAsnPrefixes(ip); // each A/AAAA endpoint has its own RIPE cache
    }));
  }
}

/// آخرین شکست RIPE برای هر IP (حافظه‌ی موقت، جدا از کش دائمی).
final Map<String, DateTime> _asnFailAt = <String, DateTime>{};

/// All announced IPv4 and IPv6 prefixes for every ASN owning this address.
Future<List<String>> nipAsnPrefixes(String ip) async {
  final prefs = await SharedPreferences.getInstance();
  final cacheKey = 'nip_asn_v1_$ip';
  final cached = prefs.getStringList(cacheKey);
  if (cached != null && cached.isNotEmpty) return cached;
  // RIPE is external; while international access is unavailable, use valid cache only.
  if (NatNetworkDiagnosis.preferDomestic) return const [];
  final failAt = _asnFailAt[ip];
  if (failAt != null &&
      DateTime.now().difference(failAt) < const Duration(minutes: 15)) {
    return const [];
  }
  try {
    final response = await http
        .get(Uri.parse('https://stat.ripe.net/data/network-info/data.json?resource=$ip'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      _asnFailAt[ip] = DateTime.now();
      return const [];
    }
    final rawAsns =
        ((jsonDecode(response.body)['data']?['asns']) as List?) ?? const [];
    final asns = rawAsns.map((value) => value.toString()).toList(growable: false);
    final out = <String>{};
    for (var offset = 0; offset < asns.length; offset += 4) {
      final batch = asns.skip(offset).take(4);
      await Future.wait(batch.map((asn) async {
        try {
          final result = await http
              .get(Uri.parse(
                  'https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS$asn'))
              .timeout(const Duration(seconds: 12));
          if (result.statusCode != 200) return;
          final decoded = jsonDecode(result.body);
          final data = decoded is Map ? decoded['data'] : null;
          final prefixes = data is Map ? data['prefixes'] : null;
          if (prefixes is! List) return;
          for (final entry in prefixes) {
            if (entry is! Map) continue;
            final prefix = '${entry['prefix']}';
            if (prefix.contains('/')) out.add(prefix);
          }
        } catch (e, stk) {
          logError(e, stk);
        }
      }));
    }
    final ranges = out.toList(growable: false);
    if (ranges.isNotEmpty) {
      await prefs.setStringList(cacheKey, ranges);
    } else {
      _asnFailAt[ip] = DateTime.now();
    }
    return ranges;
  } catch (e, stk) {
    logError(e, stk);
    _asnFailAt[ip] = DateTime.now();
    return const [];
  }
}

// FRONTSNI: کانفیگ‌های CDN: اگر SNI اصلی فیلتر شده باشد، SNI را به یک دامنه‌ی دیگر
// روی همان Cloudflare تغییر می‌دهیم و Host را همان سرور نگه می‌داریم.
// لیست کاندید؛ هر کدام که TLS روی IP باز کامل شد نگه داشته می‌شود.
// خودت می‌توانی دامنه‌های بیشتری به این لیست اضافه کنی.
// Seed domains are only starting points; the full project domain inventory
// is rotated through by nipFindFrontSni on subsequent calls.
// Front-SNI candidates include the expanded seed catalog. The scanner
// separately adds only SNI names that returned a real HTTPS response.
const natFrontSnis = <String>[
  // Preserve the original seven indices: saved variants refer to these slots.
  'cdnjs.cloudflare.com',
  'www.cloudflare.com',
  'speed.cloudflare.com',
  'one.one.one.one',
  'www.aparat.com',
  'www.digikala.com',
  'divar.ir',
  ...kAutoSniDomains,
];
const String _nipFrontSniCursorKey = 'nip_front_sni_cursor_v1';
int _nipFrontSniCursor = 0;
Future<void>? _nipFrontSniCursorLoadFuture;
Future<void> _nipFrontSniScanQueue = Future<void>.value();
Future<void> _nipEnsureFrontSniCursorLoaded() {
  return _nipFrontSniCursorLoadFuture ??= () async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _nipFrontSniCursor =
          (prefs.getInt(_nipFrontSniCursorKey) ?? 0).clamp(0, 1 << 31).toInt();
    } catch (e, stk) {
      logError(e, stk);
    }
  }();
}
Future<void> _nipFrontSniCursorSaveQueue = Future<void>.value();
Future<void> _nipPersistFrontSniCursor(int value) {
  return _nipFrontSniCursorSaveQueue = _nipFrontSniCursorSaveQueue.then((_) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_nipFrontSniCursorKey, value);
    } catch (e, stk) {
      logError(e, stk);
    }
  });
}

/// Accept an SNI only when an HTTPS request receives a real successful response.
Future<String?> nipFrontProbe(String ip, int port, String sni) async {
  Socket? raw;
  SecureSocket? sec;
  try {
    raw = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 2500));
    sec = await SecureSocket.secure(
      raw,
      host: sni,
      supportedProtocols: const ['http/1.1'],
    ).timeout(const Duration(seconds: 4));
    sec.write(
      'GET / HTTP/1.1\r\n'
      'Host: $sni\r\n'
      'User-Agent: KING-VPN-Front-SNI-Probe/1.0\r\n'
      'Accept: */*\r\n'
      'Connection: close\r\n\r\n',
    );
    await sec.flush().timeout(const Duration(seconds: 3));
    final statusLine = await utf8.decoder
        .bind(sec)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 4));
    final match = RegExp(r'^HTTP/1\.[01]\s+(\d{3})').firstMatch(statusLine);
    final status = int.tryParse(match?.group(1) ?? '');
    if (status == null || status < 100 || status > 599) return null;
    return sni;
  } catch (_) {
    return null;
  } finally {
    try { sec?.destroy(); } catch (e, st) { logError(e, st); }
    try { raw?.destroy(); } catch (e, st) { logError(e, st); }
  }
}

Future<String?> nipFindFrontSni(String ip, int port, {bool Function()? cancelled}) async {
  await _nipEnsureFrontSniCursorLoaded();

  // Serialize cursor ownership. A cancelled probe must never reserve and skip
  // domains that were not actually tested by this invocation.
  final previous = _nipFrontSniScanQueue;
  final release = Completer<void>();
  _nipFrontSniScanQueue = release.future;
  await previous;
  try {
    final inventory = <String>{
      ...natFrontSnis,
      ...dnsxFullDomains(),
      ...(_goldScan['sni'] ?? const <String>[]),
    }.toList()..sort();
    if (inventory.isEmpty) return null;

    final start = _nipFrontSniCursor % inventory.length;
    final count = inventory.length;
    var completed = 0;
    for (var offset = 0; offset < count; offset++) {
      if (cancelled?.call() ?? false) break;
      final sni = inventory[(start + offset) % inventory.length];
      final ok = await nipFrontProbe(ip, port, sni);
      completed++;
      if (ok != null) {
        _nipFrontSniCursor = (start + completed) % inventory.length;
        await _nipPersistFrontSniCursor(_nipFrontSniCursor);
        return ok;
      }
    }
    // Commit only probes that actually completed. Unvisited names remain
    // queued after cancellation or interruption.
    if (completed > 0) {
      _nipFrontSniCursor = (start + completed) % inventory.length;
      await _nipPersistFrontSniCursor(_nipFrontSniCursor);
    }
    return null;
  } finally {
    release.complete();
  }
}

/// همان کانفیگ را با IP و SNI جدید می‌سازد؛ Host اصلی سرور حفظ می‌شود.
String? nipSwapSni(Server t, String ip, String sni) {
  final l = t.link;
  final lower = l.toLowerCase();
  if (lower.startsWith('ss://')) return null;
  if (echFromLink(l).isNotEmpty) return null; // ECH: SNI جایگزین ممنوع
  try {
    if (lower.startsWith('vmess://')) {
      var b = natB64Normalize(l.substring(8));
      final j = jsonDecode(utf8.decode(base64.decode(b)));
      final oldSni = (j['sni'] ?? '').toString().isNotEmpty ? j['sni'].toString() : t.host;
      if ((j['host'] ?? '').toString().isEmpty) j['host'] = oldSni;
      j['add'] = ip;
      j['sni'] = sni;
      return 'vmess://${base64.encode(utf8.encode(jsonEncode(j)))}';
    }
    final u = Uri.parse(l);
    final q = Map<String, String>.from(u.queryParameters);
    final oldSni = (q['sni'] ?? '').isNotEmpty ? q['sni']! : t.host;
    if ((q['host'] ?? '').isEmpty) q['host'] = oldSni;
    q['sni'] = sni;
    return u.replace(host: ip, queryParameters: q).toString();
  } catch (_) {
    return null;
  }
}

extension NipHunt on _HomePageState {
  /// نت ملی: وقتی سرورهای شناخته‌شده جواب ندادند، IP های باز ایران را پیدا
  /// می‌کند و کانفیگ‌های خود کاربر را روی آن‌ها امتحان می‌کند.
  /// موفق‌ها ذخیره می‌شوند تا دفعه‌ی بعد اول امتحان شوند.
  Future<bool> _natIpHunt() async {
    if (!nationalMode || connected || abort) return false;
    final sourceServers = <Server>[...good, ...pending];
    final seenLinks = sourceServers.map((server) => server.link).toSet();
    for (final entry in _resMap.values) {
      if (seenLinks.add(entry.link)) sourceServers.add(entry.s);
    }
    final uniqueTemplates = <String, Server>{};
    for (final server in sourceServers) {
      if (server.link.toLowerCase().startsWith('ss://')) continue;
      uniqueTemplates.putIfAbsent(server.host, () => server);
    }
    final templateInventory = uniqueTemplates.values.toList()
      ..sort((a, b) {
        final hostOrder = a.host.compareTo(b.host);
        return hostOrder != 0 ? hostOrder : a.link.compareTo(b.link);
      });
    if (templateInventory.isEmpty) {
      _set('برای جستجوی IP سرور نمونه نداریم؛ یک بار با سرورهای پوشه وصل شو');
      return false;
    }
    final templatePrefs = await SharedPreferences.getInstance();
    const templateCursorKey = 'nip_hunt_template_cursor_v1';
    final savedTemplateCursor = templatePrefs.getString(templateCursorKey);
    final previousTemplateIndex = savedTemplateCursor == null
        ? -1
        : templateInventory.indexWhere((server) => server.link == savedTemplateCursor);
    final templateStart = previousTemplateIndex < 0
        ? 0
        : (previousTemplateIndex + 1) % templateInventory.length;
    final templateBatchSize = templateInventory.length;
    final templates = <Server>[
      for (var i = 0; i < min(templateBatchSize, templateInventory.length); i++)
        templateInventory[(templateStart + i) % templateInventory.length],
    ];
    // Only the exact host:port endpoints present in saved server configurations
    // are actively probed. CDN/ASN prefix catalogs and relay-name catalogs remain
    // discovery metadata; they do not grant permission to probe unrelated hosts.
    Future<void> saveTemplateCursor(Server completed) async {
      if (!abort) {
        await templatePrefs.setString(templateCursorKey, completed.link);
      }
    }

    for (final template in templates) {
      if (abort) return false;
      final port = template.port;
      if (port < 1 || port > 65535) {
        await saveTemplateCursor(template);
        continue;
      }
      final resolved = template.isIp
          ? <String>[template.host]
          : await nipResolveAll(template.host);
      if (abort) return false;
      final ips = resolved
          .map(InternetAddress.tryParse)
          .whereType<InternetAddress>()
          .where((address) =>
              address.type == InternetAddressType.IPv4 ||
              address.type == InternetAddressType.IPv6)
          .map((address) => address.address)
          .toSet()
          .toList()
        ..sort();
      if (ips.isNotEmpty &&
          await _natTryScan(
            [template],
            ips,
            port: port,
            label: 'endpoint دقیقِ کانفیگ ذخیره‌شده',
          )) {
        await saveTemplateCursor(template);
        return true;
      }
      if (abort) return false;
      // Each template is a complete, bounded unit. Re-resolution on the next
      // run retries transient DNS/TCP failures without discarding the host.
      await saveTemplateCursor(template);
    }

    _set('نت ملی: endpoint قابل‌استفاده‌ای از کانفیگ‌های ذخیره‌شده پیدا نشد');
    return false;
  }

  /// TCP reachability is a prefilter for exact configured endpoints only.
  /// A candidate is promoted only by _connectLoop's real TUN/core HTTP gate.
  Future<bool> _natTryScan(
    List<Server> templates,
    List<String> ips, {
    required int port,
    required String label,
  }) async {
    if (ips.isEmpty || templates.isEmpty || port < 1 || port > 65535) {
      return false;
    }
    // A DNS hostname can resolve to more endpoints than one two-minute
    // probe window can cover. Process every resolved address in resumable-size
    // slices; do not advance the template cursor after only the first slice.
    const ipBatchSize = 256;
    final totalBatches = (ips.length + ipBatchSize - 1) ~/ ipBatchSize;
    for (var ipOffset = 0; ipOffset < ips.length; ipOffset += ipBatchSize) {
      if (abort) return false;
      final scanBatch = ips.skip(ipOffset).take(ipBatchSize).toList();
      final batchNumber = ipOffset ~/ ipBatchSize + 1;
      _set('نت ملی: بررسی $label • دسته $batchNumber/$totalBatches • ${ips.length} آدرس…');

      var completed = 0;
      var hits = <NipHit>[];
      // The slice is deliberately small enough to fit comfortably inside the
      // per-batch budget. If the OS still interrupts it, retry this exact slice
      // rather than committing the template cursor and skipping its tail.
      while (completed < scanBatch.length) {
        completed = 0;
        hits = await nipScan(
          scanBatch,
          port: port,
          want: scanBatch.length,
          budget: const Duration(minutes: 2),
          cancelled: () => abort,
          onProgress: (done, total) {
            completed = done;
          },
        );
        if (abort) return false;
      }

      for (var offset = 0; offset < hits.length; offset += 8) {
        if (abort) return false;
        final batch = hits.skip(offset).take(8).toList(growable: false);
        final candidates = <Server>[];
        for (var i = 0; i < batch.length; i++) {
          final hit = batch[i];
          final template = templates[(offset + i) % templates.length];
          final link = nipSwapLink(template, hit.ip);
          if (link == null) continue;
          final candidate = Server.parse(link);
          if (candidate != null) candidates.add(candidate);
        }
        if (candidates.isEmpty) continue;
        _set('نت ملی: اعتبارسنجی تونلی ' + candidates.length.toString() + ' کاندیدا…');
        if (await _connectLoop(candidates, trust: false)) {
          final winner = current;
          if (winner != null) _natAdd(winner);
          return true;
        }
        if (abort) return false;
      }
    }
    return false;
  }
}

// HOTFOLDER UI ==============================================================
// وضعیت پوشه‌ی منابع تازه و ساخت دستی آن (در هر حالتی، نه فقط نت ملی).
extension HotFolderUi on _HomePageState {
  String hotFolderInfo() {
    try {
      final f = File(_hotPath());
      if (!f.existsSync()) {
        return 'هنوز ساخته نشده؛ با زدن همین ردیف ساخته می‌شود';
      }
      final age = DateTime.now().difference(f.lastModifiedSync());
      final mb = (f.lengthSync() / 1048576).toStringAsFixed(1);
      return '$mb MB • ${age.inHours} ساعت پیش ساخته شده • با زدن این ردیف تازه می‌شود';
    } catch (_) {
      return 'خطا در خواندن وضعیت پوشه';
    }
  }

  Future<void> hotFolderRebuild() async {
    if (_hotBusy) {
      _set('پوشه‌ی منابع تازه هم‌اکنون در حال ساخت است؛ کمی صبر کن');
      return;
    }
    _set('پوشه‌ی منابع تازه: در حال دریافت از منبع‌ها...');
    _hotFailAt = null;
    await natHotEnsure(force: true);
    final ok = _hotFailAt == null && File(_hotPath()).existsSync();
    _set(ok
        ? 'پوشه‌ی منابع تازه آماده شد (${hotFolderInfo()})'
        : 'ساخته نشد: منبع‌ها دریافت نشدند؛ اینترنت یا دسترسی به GitHub و میرورها را چک کن');
  }
}
