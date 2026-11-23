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
  int want = 12,
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
      if (hits.length >= want) return;
      if (cancelled != null && cancelled()) return;
      if (clock.elapsed >= budget) return;
      if (next >= ips.length) return;
      final ip = ips[next++];
      final ms = await nipTcpProbe(ip, port, timeout);
      if (cancelled != null && cancelled()) return;
      if (ms != null && hits.length < want) hits.add(NipHit(ip, ms));
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
  final start =
      (int.tryParse(cursors['__nip_${namespace}_range_cursor']?.toString() ?? '') ?? 0) %
          ranges.length;
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
  final doh = NatNetworkDiagnosis.preferDomestic ? null : await dohResolve(host);
  final out = <String>{if (doh != null) doh};
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
  var n = 0;
  for (final server in list) {
    if (n >= 20) break;
    if (server.cdn) continue;
    final addresses = server.isIp ? [server.host] : await nipResolveAll(server.host);
    for (final ip in addresses) {
      if (n >= 20) break;
      n++;
      await nipAsnPrefixes(ip); // each A/AAAA endpoint has its own RIPE cache
    }
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
    await pool<String>(asns, 4, (asn) async {
      try {
        final result = await http
            .get(Uri.parse(
                'https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS$asn'))
            .timeout(const Duration(seconds: 12));
        if (result.statusCode != 200) return;
        final prefixes =
            ((jsonDecode(result.body)['data']?['prefixes']) as List?) ?? const [];
        for (final entry in prefixes) {
          if (entry is! Map) continue;
          final prefix = '${entry['prefix']}';
          if (prefix.contains('/')) out.add(prefix);
        }
      } catch (e, stk) {
        logError(e, stk);
      }
    });
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
// FRONTSNI: کاهش از ۱۹ به ۸ دامنه برای سرعت بیشتر nipFindFrontSni
const natFrontSnis = <String>[
  'cdnjs.cloudflare.com',    // 0
  'www.cloudflare.com',      // 1
  'speed.cloudflare.com',    // 2  ← قبلاً 3 بود، حالا 2
  'one.one.one.one',         // 3  ← قبلاً 16 بود
  '1.1.1.1',                 // 4  ← قبلاً 17 بود
  'www.aparat.com',          // 5
  'www.digikala.com',        // 6
  'divar.ir',                // 7
];

/// روی IP:port یک TLS با SNI داده‌شده کامل شود؟ برمی‌گرداند همان SNI یا null.
Future<String?> nipFrontProbe(String ip, int port, String sni) async {
  Socket? raw;
  SecureSocket? sec;
  try {
    raw = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 2000));
    sec = await SecureSocket.secure(raw, host: sni, onBadCertificate: (_) => true)
        .timeout(const Duration(seconds: 3));
    return sni;
  } catch (_) {
    return null;
  } finally {
    try { sec?.destroy(); } catch (e, st) { logError(e, st); }
    try { raw?.destroy(); } catch (e, st) { logError(e, st); }
  }
}

Future<String?> nipFindFrontSni(String ip, int port) async {
  for (final sni in natFrontSnis) {
    final ok = await nipFrontProbe(ip, port, sni);
    if (ok != null) return ok;
  }
  return null;
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
  static DateTime? _nipLastHunt;

  /// نت ملی: وقتی سرورهای شناخته‌شده جواب ندادند، IP های باز ایران را پیدا
  /// می‌کند و کانفیگ‌های خود کاربر را روی آن‌ها امتحان می‌کند.
  /// موفق‌ها ذخیره می‌شوند تا دفعه‌ی بعد اول امتحان شوند.
  Future<bool> _natIpHunt() async {
    if (!nationalMode || connected || abort) return false;
    final last = _nipLastHunt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 4)) {
      return false;
    }
    _nipLastHunt = DateTime.now();

    final templates = <Server>[];
    final seen = <String>{};
    final pool = <Server>[];
    pool.addAll(good);
    pool.addAll(pending);
    for (final e in _resMap.values) {
      if (!pool.any((x) => x.link == e.link)) pool.add(e.s);
    }
    for (final s in pool) {
      if (s.link.toLowerCase().startsWith('ss://')) continue;
      if (!seen.add(s.host)) continue;
      templates.add(s);
      if (templates.length >= 40) break;
    }
    if (templates.isEmpty) {
      _set('برای جستجوی IP سرور نمونه نداریم؛ یک بار با سرورهای پوشه وصل شو');
      return false;
    }
    final cdnT = templates.where((s) => s.cdn).toList();
    final direct = templates.where((s) => !s.cdn).toList();
    final huntCursors = await _nipLoadHuntCursors();
    if (abort) return false;

    // مرحله ۱: همه‌ی prefixهای زنده‌ی CDN، هر دو خانواده، با Cursor مستقل.
    // هر اجرا فقط یک دسته‌ی قابل‌اتمام را می‌سنجد و بعد از تکمیل آن ادامه می‌دهد.
    if (cdnT.isNotEmpty) {
      final cdnRanges = <String>{
        ..._liveCdnRanges,
        ..._cfRanges,
        ..._cfRangesV6,
      }.toList()..sort();
      final cdnBatch = _nipRangeBatch(
        cdnRanges,
        huntCursors,
        namespace: 'cdn',
        batchSize: 1000,
      );
      if (cdnBatch.addresses.isNotEmpty) {
        if (await _natTryScan(
          cdnT,
          cdnBatch.addresses,
          port: cdnT.first.port,
          label: 'لبه‌ی CDN',
          front: true,
          onComplete: () => _nipSaveHuntCursors(cdnBatch.cursors),
        )) {
          return true;
        }
        if (abort) return false;
      }
    }
    if (direct.isEmpty) return false;

    // مرحله ۲: واسط‌های تعریف‌شده (natRelayHosts) — مستقیم امتحان می‌شوند
    if (natRelayHosts.isNotEmpty) {
      final cands = <Server>[];
      for (final ip in natRelayHosts) {
        final link = nipSwapLink(direct[cands.length % direct.length], ip);
        if (link == null) continue;
        final c = Server.parse(link);
        if (c != null) cands.add(c);
        if (cands.length >= 8) break;
      }
      if (cands.isNotEmpty) {
        _set('نت ملی: امتحان ${cands.length} واسط…');
        if (await _connectLoop(cands, trust: false)) {
          final w = current;
          if (w != null) _natAdd(w);
          return true;
        }
        if (abort) return false;
      }
    }

    // مرحله ۳: A/AAAA همه‌ی templateهای مستقیم و prefixهای ASN هرکدام.
    final hostResults = await Future.wait(direct.map((server) async {
      if (server.isIp) return <String>[server.host];
      return nipResolveAll(server.host);
    }));
    if (abort) return false;
    final hostIps = <String>{
      for (final result in hostResults) ...result,
    };
    if (hostIps.isNotEmpty) {
      final prefixes = <String>{};
      await pool<String>(hostIps.toList(growable: false), 4, (hostIp) async {
        if (abort) return;
        prefixes.addAll(await nipAsnPrefixes(hostIp));
      });
      if (abort) return false;
      if (prefixes.isNotEmpty) {
        final asnRanges = prefixes.toList()..sort();
        final asnBatch = _nipRangeBatch(
          asnRanges,
          huntCursors,
          namespace: 'asn',
          batchSize: 1000,
        );
        if (asnBatch.addresses.isNotEmpty &&
            await _natTryScan(
              direct,
              asnBatch.addresses,
              port: direct.first.port,
              label: 'IP هم‌شرکت سرور',
              onComplete: () => _nipSaveHuntCursors(asnBatch.cursors),
            )) {
          return true;
        }
        if (abort) return false;
      }
    }

    // مرحله ۴ (IP های باز ایران) حذف شد: یک IP باز ایران فوروارد نمی‌کند،
    // پس برای REALITY/TCP وقت تلف می‌کرد و هیچ‌وقت وصل نمی‌شد.
    _set('نت ملی: واسط یا IP هم‌شرکت سالم پیدا نشد');
    return false;
  }

  /// اسکن IP ها و امتحان نتیجه‌ها با همان کانفیگ‌ها (فقط IP عوض می‌شود).
  /// front = true (CDN): برای IP های باز، SNI دامنه‌ی باز هم امتحان می‌شود.
  Future<bool> _natTryScan(List<Server> tpls, List<String> ips,
      {required int port,
      required String label,
      bool front = false,
      Future<void> Function()? onComplete}) async {
    if (ips.isEmpty) return false;
    _set('نت ملی: جستجوی $label (${ips.length} آدرس)…');
    var completed = 0;
    final hits = await nipScan(
      ips,
      port: port,
      want: ips.length,
      budget: const Duration(minutes: 2),
      cancelled: () => abort,
      onProgress: (done, total) => completed = done,
    );
    if (abort) return false;
    // Do not advance the range cursor until the full scan AND all resulting
    // connection trials finish. A timeout/cancel retries this slice safely.
    if (hits.isEmpty) {
      if (completed >= ips.length) await onComplete?.call();
      _set('نت ملی: هیچ $label بازی پیدا نشد');
      return false;
    }

    // Try every open address in small groups; the former top-8 truncation
    // could permanently ignore working endpoints later in the same batch.
    for (var offset = 0; offset < hits.length; offset += 8) {
      if (abort) return false;
      final top = hits.skip(offset).take(8).toList();
      final snis = <String?>[];
      if (front) {
        for (var i = 0; i < top.length; i += 4) {
          if (abort) return false;
          final batch = top.skip(i).take(4).toList();
          snis.addAll(await Future.wait(
            batch.map((hit) => nipFindFrontSni(hit.ip, port)),
          ));
        }
      }
      if (abort) return false;
      final candidates = <Server>[];
      for (var i = 0; i < top.length; i++) {
        final template = tpls[(offset + i) % tpls.length];
        final link = nipSwapLink(template, top[i].ip);
        if (link != null) {
          final candidate = Server.parse(link);
          if (candidate != null) candidates.add(candidate);
        }
        final sni = i < snis.length ? snis[i] : null;
        if (sni != null) {
          final frontLink = nipSwapSni(template, top[i].ip, sni);
          if (frontLink != null) {
            final candidate = Server.parse(frontLink);
            if (candidate != null) candidates.add(candidate);
          }
        }
      }
      if (candidates.isEmpty) continue;
      _set('نت ملی: امتحان ${candidates.length} آدرس ($label)…');
      if (await _connectLoop(candidates, trust: false)) {
        final winner = current;
        if (winner != null) _natAdd(winner);
        if (completed >= ips.length) await onComplete?.call();
        return true;
      }
    }
    if (completed >= ips.length) await onComplete?.call();
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
