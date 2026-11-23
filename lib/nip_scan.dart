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
List<String> nipExpandCidr(String cidr, {int maxPerBlock = 65536}) {
  final parts = cidr.trim().split('/');
  if (parts.length != 2) return const [];
  final octets = parts[0].split('.');
  final prefix = int.tryParse(parts[1].trim());
  if (octets.length != 4 || prefix == null || prefix < 8 || prefix > 32) {
    return const [];
  }
  int base = 0;
  for (final o in octets) {
    final v = int.tryParse(o.trim());
    if (v == null || v < 0 || v > 255) return const [];
    base = (base << 8) | v;
  }
  if (maxPerBlock <= 0) return const [];
  final size = 1 << (32 - prefix);
  final start = base & ~(size - 1) & 0xFFFFFFFF;
  // Ceiling division ensures the sampled output never exceeds the caller's cap.
  final step = size > maxPerBlock
      ? (size + maxPerBlock - 1) ~/ maxPerBlock
      : 1;
  final out = <String>[];
  for (var i = 0; i < size; i += step) {
    final v = start + i;
    out.add('${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}');
  }
  return out;
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
  int want = 1 << 31,
  Duration budget = const Duration(minutes: 2),
  Duration timeout = const Duration(milliseconds: 1500),
  bool Function()? cancelled,
}) async {
  if (port < 1 || port > 65535 || want <= 0 ||
      budget <= Duration.zero || timeout <= Duration.zero) {
    return const <NipHit>[];
  }
  final boundedIps = natBoundScanTargets(ips);
  if (boundedIps.isEmpty) return const <NipHit>[];
  final hits = <NipHit>[];
  // Stopwatch is monotonic: wall-clock adjustments cannot extend a scan.
  final elapsed = Stopwatch()..start();
  var next = 0;

  Future<void> worker() async {
    while (true) {
      if (hits.length >= want) return;
      if (cancelled != null && cancelled()) return;
      if (elapsed.elapsed >= budget) return;
      if (next >= boundedIps.length) return;
      final ip = boundedIps[next++];
      // Never let an in-flight probe extend the scan beyond its remaining
      // monotonic budget. Socket.connect enforces this per-attempt deadline.
      final remaining = budget - elapsed.elapsed;
      if (remaining <= Duration.zero) return;
      final probeTimeout = timeout < remaining ? timeout : remaining;
      final ms = await nipTcpProbe(ip, port, probeTimeout);
      if (ms != null) hits.add(NipHit(ip, ms));
    }
  }

  final n = min(concurrency.clamp(1, 16), max(boundedIps.length, 1));
  await Future.wait(List.generate(n, (_) => worker()));
  natStableSort(hits, (a, b) => a.ms.compareTo(b.ms));
  return hits;
}

/// Full official IPv4 country-resource inventory from RIPE, cached for offline reuse.
/// The returned prefixes are consumed by the resumable range cursor in small batches;
/// this function discovers ranges and does not itself send probes.
Future<List<String>> nipIranCidrs() async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getStringList('plus_ir_cidr') ?? const <String>[];
  final cachedAt = prefs.getInt('plus_ir_cidr_at') ?? 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (cached.isNotEmpty && now - cachedAt < const Duration(hours: 6).inMilliseconds) {
    return cached;
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client
        .getUrl(Uri.parse(
            'https://stat.ripe.net/data/country-resource-list/data.json?resource=IR'))
        .timeout(const Duration(seconds: 15));
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return cached;
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    final raw = ((decoded['data']?['resources']?['ipv4']) as List?) ?? const [];
    final ranges = raw
        .map((entry) => '$entry'.trim())
        .where((entry) => entry.contains('/') && !entry.contains(':'))
        .toSet()
        .toList(growable: false);
    if (ranges.isNotEmpty) {
      await prefs.setStringList('plus_ir_cidr', ranges);
      await prefs.setInt('plus_ir_cidr_at', now);
      return ranges;
    }
    return cached;
  } catch (e, st) {
    logError(e, st);
    return cached;
  } finally {
    client.close(force: true);
  }
}

/// همان کانفیگ سرور [t] را روی IP دیگری می‌سازد؛ SNI و Host اصلی حفظ می‌شوند.
String? nipSwapLink(Server t, String ip) {
  final l = t.link;
  final lower = l.toLowerCase();
  if (lower.startsWith('ss://') || t.reality) return null;
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

Future<void> natRelayHostsLoad() async {
  try {
    final p = await SharedPreferences.getInstance();
    natRelayHosts = natBoundScanTargets(
      p.getStringList('nat_relay_hosts') ?? <String>[],
    );
  } catch (e, st) {
    logError(e, st);
  }
}

Future<void> natRelayHostsSave(String text) async {
  natRelayHosts = natBoundScanTargets(
    text.split(RegExp(r'[\s,;]+')),
  );
  try {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('nat_relay_hosts', natRelayHosts);
  } catch (e, st) {
    logError(e, st);
  }
}

Future<String?> nipResolve(String host) async {
  // NATOPT: وقتی جهانی قطع است، DoH (سرویس خارجی) بی‌فایده و کند است؛ مستقیم DNS سیستم.
  if (!NatNetworkDiagnosis.preferDomestic) {
    // DNSDOH: اول DoH (در نت ملی DNS معمولی جواب بسته می‌دهد)
    final d = await dohResolve(host);
    if (d != null) return d;
  }
  try {
    final l = await InternetAddress.lookup(host).timeout(const Duration(seconds: 5));
    return l.isEmpty ? null : l.first.address;
  } catch (_) {
    return null;
  }
}

// FRONTSNI: alternate SNI candidates for standard TLS only.
// A candidate is retained only after a TLS handshake and platform certificate/hostname validation.
// This does not prove HTTP Host routing, CDN co-location, or domain-fronting acceptance;
// the real VPN tunnel and HTTP traffic check remain the final acceptance gate.
// The original Host header is preserved when a candidate is applied.
// FRONTSNI: full historical hostname candidate inventory (IP literals excluded).
// Every candidate is evaluated independently; the original Host header is preserved.
const natFrontSnis = <String>[
  'cdnjs.cloudflare.com',
  'www.cloudflare.com',
  'cloudflare.com',
  'speed.cloudflare.com',
  'www.aparat.com',
  'www.digikala.com',
  'divar.ir',
  'www.snapp.ir',
  'www.bale.ai',
  'eitaa.com',
  'www.zarinpal.com',
  'www.iranserver.com',
  'www.shatel.ir',
  'www.mci.ir',
  'workers.dev',
  'dash.cloudflare.com',
  'one.one.one.one',
  'cloudflare-dns.com',
];

const String _nipFrontEndpointsKey = 'nip_front_endpoints_v1';
final List<String> _nipFrontEndpoints = [];
bool _nipFrontEndpointsLoaded = false;

Future<void> _nipFrontEndpointsLoad() async {
  if (_nipFrontEndpointsLoaded) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    _nipFrontEndpoints
      ..clear()
      ..addAll(prefs.getStringList(_nipFrontEndpointsKey) ?? const <String>[]);
  } catch (e, st) {
    logError(e, st);
  } finally {
    _nipFrontEndpointsLoaded = true;
  }
}

Future<void> _nipFrontEndpointsAdd(List<NipHit> hits, int port) async {
  await _nipFrontEndpointsLoad();
  final known = _nipFrontEndpoints.toSet();
  for (final hit in hits) {
    final key = '${hit.ip}|$port';
    if (known.add(key)) _nipFrontEndpoints.add(key);
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_nipFrontEndpointsKey, _nipFrontEndpoints);
  } catch (e, st) {
    logError(e, st);
  }
}

Future<void> _nipFrontEndpointsRemove(List<String> endpoints, int port) async {
  await _nipFrontEndpointsLoad();
  final remove = endpoints.map((ip) => '$ip|$port').toSet();
  _nipFrontEndpoints.removeWhere(remove.contains);
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_nipFrontEndpointsKey, _nipFrontEndpoints);
  } catch (e, st) {
    logError(e, st);
  }
}

Future<void> _nipFrontEndpointsPrune(
  List<NipHit> hits,
  int port,
  List<String> candidates,
) async {
  if (hits.isEmpty || candidates.isEmpty) return;
  final fingerprint = _nipSniFingerprint(candidates);
  final prefs = await SharedPreferences.getInstance();
  final done = <String>{};
  for (final hit in hits) {
    final key = 'nip_sni_cursor_${hit.ip.replaceAll(':', '_')}_$port';
    final fp = prefs.getString('${key}_fp');
    if (fp == fingerprint && prefs.getInt(key) == -1) {
      done.add('${hit.ip}|$port');
    }
  }
  if (done.isEmpty) return;
  _nipFrontEndpoints.removeWhere(done.contains);
  await prefs.setStringList(_nipFrontEndpointsKey, _nipFrontEndpoints);
}

int _nipSniFingerprint(List<String> values) {
  var hash = 0x811c9dc5;
  for (final unit in values.join('\n').codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// روی IP:port یک TLS با SNI داده‌شده کامل شود؟ برمی‌گرداند همان SNI یا null.
Future<String?> nipFrontProbe(
    String ip, int port, String sni, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
  if (timeout <= Duration.zero) return null;
  final elapsed = Stopwatch()..start();
  Duration remaining() => timeout - elapsed.elapsed;
  Socket? raw;
  SecureSocket? sec;
  try {
    final connectBudget = remaining();
    if (connectBudget <= Duration.zero) return null;
    const connectCap = Duration(seconds: 2);
    raw = await Socket.connect(
      ip,
      port,
      timeout: connectBudget < connectCap ? connectBudget : connectCap,
    );
    // TCP connect and TLS handshake share one deadline. Keep normal certificate
    // and hostname validation; a successful handshake is only a prefilter.
    final handshakeBudget = remaining();
    if (handshakeBudget <= Duration.zero) return null;
    sec = await SecureSocket.secure(raw, host: sni).timeout(handshakeBudget);
    return sni;
  } catch (_) {
    return null;
  } finally {
    try { sec?.destroy(); } catch (e, st) { logError(e, st); }
    try { raw?.destroy(); } catch (e, st) { logError(e, st); }
  }
}

List<String> nipFrontSniCandidates(Iterable<Server> templates) {
  final all = _dnsxHostsFrom([
    ...dnsxFullDomains(),
    ...natFrontSnis,
    ...templates.map((server) => server.host),
  ]).toSet();
  bool cloudflareLast(String host) =>
      host == 'one.one.one.one' ||
      host.endsWith('.cloudflare.com') ||
      host == 'cloudflare.com' ||
      host.endsWith('.workers.dev') ||
      host.endsWith('.pages.dev') ||
      host.endsWith('cloudflare-dns.com');
  final ordinary = all.where((host) => !cloudflareLast(host)).toList();
  final cloudflare = all.where(cloudflareLast).toList();
  return [...ordinary, ...cloudflare];
}

Future<List<String>> nipFindFrontSnis(
  String ip,
  int port, {
  Iterable<String>? candidates,
  bool Function()? cancelled,
  Duration budget = const Duration(seconds: 90),
}) async {
  if (budget <= Duration.zero) return const <String>[];
  final list = _dnsxHostsFrom(candidates ?? natFrontSnis).toSet().toList();
  if (list.isEmpty) return const <String>[];
  final prefs = await SharedPreferences.getInstance();
  final cursorKey = 'nip_sni_cursor_${ip.replaceAll(':', '_')}_$port';
  final fingerprint = _nipSniFingerprint(list);
  final fingerprintKey = '${cursorKey}_fp';
  final oldFingerprint = prefs.getInt(fingerprintKey);
  final sameInventory = oldFingerprint == fingerprint;
  if (!sameInventory) {
    await prefs.setInt(fingerprintKey, fingerprint);
    await prefs.setInt(cursorKey, 0);
  }
  final storedCursor = sameInventory ? (prefs.getInt(cursorKey) ?? 0) : 0;
  if (storedCursor < 0) return const <String>[];
  final start = storedCursor % list.length;
  final elapsed = Stopwatch()..start();
  final matches = <String>[];
  var processed = 0;
  for (var offset = 0; offset < list.length; offset++) {
    if (cancelled?.call() == true) break;
    final remaining = budget - elapsed.elapsed;
    if (remaining <= Duration.zero) break;
    final sni = list[(start + offset) % list.length];
    const perProbeCap = Duration(seconds: 5);
    final probeBudget = remaining < perProbeCap ? remaining : perProbeCap;
    final ok = await nipFrontProbe(ip, port, sni, timeout: probeBudget);
    processed++;
    if (cancelled?.call() == true) break;
    if (ok != null) matches.add(ok);
  }
  if (processed > 0) {
    await prefs.setInt(cursorKey,
        processed >= list.length ? -1 : (start + processed) % list.length);
  }
  return matches;
}
Future<String?> nipFindFrontSni(
  String ip,
  int port, {
  bool Function()? cancelled,
  Duration budget = const Duration(seconds: 90),
}) async {
  final matches = await nipFindFrontSnis(
    ip, port, cancelled: cancelled, budget: budget,
  );
  return matches.isEmpty ? null : matches.first;
}

/// همان کانفیگ را با IP و SNI جدید می‌سازد؛ Host اصلی سرور حفظ می‌شود.
String? nipSwapSni(Server t, String ip, String sni) {
  final l = t.link;
  final lower = l.toLowerCase();
  if (lower.startsWith('ss://')) return null;
  // Front-SNI candidates are for ordinary TLS only; never rewrite REALITY or plaintext links.
  if (!t.tls || t.reality) return null;
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
  static int _nipCdnPortCursor = 0;

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

    await _nipFrontEndpointsLoad();
    final templates = <Server>[];
    final seen = <String>{};
    final pool = <Server>[];
    pool.addAll(good);
    pool.addAll(pending);
    for (final e in _resMap.values) {
      if (!pool.any((x) => x.link == e.link)) pool.add(e.s);
    }
    for (final s in pool) {
      if (!seen.add(s.link)) continue;
      templates.add(s);
    }
    if (templates.isEmpty) {
      _set('برای جستجوی IP سرور نمونه نداریم؛ یک بار با سرورهای پوشه وصل شو');
      return false;
    }
    final cdnT = templates.where((s) => s.cdn).toList();
    final direct = templates.where((s) => !s.cdn).toList();

    // Resume unfinished SNI work before discovering a fresh address batch.
    if (_nipFrontEndpoints.isNotEmpty) {
      final byPort = <int, List<String>>{};
      for (final entry in _nipFrontEndpoints) {
        final parts = entry.split('|');
        if (parts.length != 2) continue;
        final port = int.tryParse(parts[1]);
        if (port == null || port < 1 || port > 65535) continue;
        byPort.putIfAbsent(port, () => <String>[]).add(parts[0]);
      }
      final pendingPorts = byPort.keys.toList(growable: false);
      if (pendingPorts.isNotEmpty) {
        final port = pendingPorts[_nipCdnPortCursor % pendingPorts.length];
        _nipCdnPortCursor = (_nipCdnPortCursor + 1) % pendingPorts.length;
        final portTemplates = templates.where((s) => s.port == port).toList();
        if (portTemplates.isNotEmpty) {
          await _natTryScan(portTemplates, byPort[port]!, port: port,
              label: 'ادامه‌ی آزمون SNI', front: true);
          if (abort) return false;
          return false;
        }
      }
    }

    // مرحله ۱: کانفیگ‌های CDN (SNI/Host) ← لبه‌های باز چند CDN
    // CDNDIV: Cloudflare + Fastly + AWS CloudFront + Google، نه فقط Cloudflare
    if (cdnT.isNotEmpty) {
      // Rotate through every configured CDN service port across hunt passes.
      // Address and SNI candidates are cursor-driven independently of this port cursor.
      final cdnPorts = cdnT.map((s) => s.port).where((p) => p > 0 && p < 65536)
          .toSet().toList(growable: false);
      if (cdnPorts.isNotEmpty) {
        final port = cdnPorts[_nipCdnPortCursor % cdnPorts.length];
        _nipCdnPortCursor = (_nipCdnPortCursor + 1) % cdnPorts.length;
        final portTemplates = cdnT.where((s) => s.port == port).toList();
        final ips = _getCfIps(
          batchSize: 1024,
          liveRanges: _liveCdnRanges,
          cursors: _cfRangeCursors,
        );
        if (await _natTryScan(portTemplates, ips,
            port: port, label: 'لبه‌ی CDN', front: true)) {
          return true;
        }
        if (abort) return false;
      }
    }
    if (direct.isEmpty) return false;

    // مرحله ۲: همه‌ی واسط‌ها با همه‌ی الگوهای قابل‌تبدیل ترکیب می‌شوند.
    if (natRelayHosts.isNotEmpty) {
      final relayBatch = <Server>[];
      final relayLinks = <String>{};
      Future<bool> flushRelays() async {
        if (relayBatch.isEmpty) return false;
        final batch = List<Server>.of(relayBatch);
        relayBatch.clear();
        relayLinks.clear();
        if (await _connectLoop(batch, trust: false)) {
          final winner = current;
          if (winner != null) _natAdd(winner);
          return true;
        }
        return false;
      }
      for (final ip in natRelayHosts) {
        for (final template in direct) {
          final link = nipSwapLink(template, ip);
          if (link == null || !relayLinks.add(link)) continue;
          final candidate = Server.parse(link);
          if (candidate != null) relayBatch.add(candidate);
          if (relayBatch.length >= 64) {
            _set('نت ملی: آزمون دسته‌ای واسط‌ها (${relayBatch.length})…');
            if (await flushRelays()) return true;
            if (abort) return false;
          }
        }
      }
      if (relayBatch.isNotEmpty && await flushRelays()) return true;
      if (abort) return false;
    }

    // Country-resource and published CDN ranges are traversed by the
    // resumable range engine; this hunt keeps testing the full template/relay inventory.
    _set('نت ملی: واسط یا IP هم‌شرکت سالم پیدا نشد');
    return false;
  }

  /// اسکن IP ها و امتحان نتیجه‌ها با همان کانفیگ‌ها (فقط IP عوض می‌شود).
  /// front = true (CDN): برای IP های باز، SNI دامنه‌ی باز هم امتحان می‌شود.
  Future<bool> _natTryScan(List<Server> tpls, List<String> ips,
      {required int port, required String label, bool front = false}) async {
    if (ips.isEmpty) return false;
    _set('نت ملی: جستجوی $label (${ips.length} آدرس)…');
    final hits = await nipScan(ips,
        port: port,
        want: ips.length,
        budget: const Duration(minutes: 2),
        cancelled: () => abort);
    if (abort) return false;
    if (hits.isEmpty) {
      if (front) await _nipFrontEndpointsRemove(ips, port);
      _set('نت ملی: هیچ $label بازی پیدا نشد');
      return false;
    }
    if (front) await _nipFrontEndpointsAdd(hits, port);
    final top = hits; // Every responsive endpoint remains eligible.
    final matchingTemplates = tpls.where((t) => t.port == port).toList();
    if (matchingTemplates.isEmpty) return false;
    final snis = <List<String>>[];
    final frontSniCandidates = front ? nipFrontSniCandidates(matchingTemplates) : const <String>[];
    if (front) {
      // Every SNI candidate is tested; concurrency is chunked, not truncated.
      for (var i = 0; i < top.length; i += 4) {
        final batch = top.skip(i).take(4).toList();
        snis.addAll(await Future.wait(batch.map((h) => nipFindFrontSnis(
          h.ip, port, candidates: frontSniCandidates, cancelled: () => abort,
        ))));
        if (abort) return false;
      }
    }
    final candidateBatch = <Server>[];
    final candidateLinks = <String>{};
    Future<bool> flushCandidates() async {
      if (candidateBatch.isEmpty) return false;
      final batch = List<Server>.of(candidateBatch);
      candidateBatch.clear();
      candidateLinks.clear();
      if (await _connectLoop(batch, trust: false)) {
        final winner = current;
        if (winner != null) {
          _natAdd(winner);
          if (front) await _nipFrontEndpointsRemove([winner.host], port);
        }
        return true;
      }
      return false;
    }
    void addCandidate(String? link) {
      if (link == null || !candidateLinks.add(link)) return;
      final candidate = Server.parse(link);
      if (candidate != null) candidateBatch.add(candidate);
    }
    // Exhaust the endpoint × template × validated-SNI product in bounded
    // connection batches. No template or successful SNI is silently dropped.
    for (var i = 0; i < top.length; i++) {
      final hit = top[i];
      final frontNames = i < snis.length ? snis[i] : const <String>[];
      for (final template in matchingTemplates) {
        addCandidate(nipSwapLink(template, hit.ip));
        for (final name in frontNames) {
          addCandidate(nipSwapSni(template, hit.ip, name));
          if (candidateBatch.length >= 64) {
            _set('نت ملی: آزمون دسته‌ای مسیرهای $label (${candidateBatch.length})…');
            if (await flushCandidates()) return true;
            if (abort) return false;
          }
        }
        if (candidateBatch.length >= 64) {
          _set('نت ملی: آزمون دسته‌ای مسیرهای $label (${candidateBatch.length})…');
          if (await flushCandidates()) return true;
          if (abort) return false;
        }
      }
    }
    if (candidateBatch.isNotEmpty && await flushCandidates()) return true;
    if (front) await _nipFrontEndpointsPrune(top, port, frontSniCandidates);
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
