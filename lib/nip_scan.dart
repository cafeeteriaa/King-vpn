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
    if (response.statusCode != 200) return const <String>[];
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
    text.split(RegExp(r'[\\r\\n\\s]+')),
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

Future<List<String>> nipFindFrontSnis(
  String ip,
  int port, {
  bool Function()? cancelled,
  Duration budget = const Duration(seconds: 90),
}) async {
  if (budget <= Duration.zero) return const <String>[];
  final elapsed = Stopwatch()..start();
  final matches = <String>[];
  for (final sni in natFrontSnis) {
    if (cancelled?.call() == true) return matches;
    final remaining = budget - elapsed.elapsed;
    if (remaining <= Duration.zero) return matches;
    const perProbeCap = Duration(seconds: 5);
    final probeBudget = remaining < perProbeCap ? remaining : perProbeCap;
    final ok = await nipFrontProbe(ip, port, sni, timeout: probeBudget);
    if (cancelled?.call() == true) return matches;
    if (ok != null) matches.add(ok);
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
      if (!seen.add(s.link)) continue;
      templates.add(s);
    }
    if (templates.isEmpty) {
      _set('برای جستجوی IP سرور نمونه نداریم؛ یک بار با سرورهای پوشه وصل شو');
      return false;
    }
    final cdnT = templates.where((s) => s.cdn).toList();
    final direct = templates.where((s) => !s.cdn).toList();

    // مرحله ۱: کانفیگ‌های CDN (SNI/Host) ← لبه‌های باز چند CDN
    // CDNDIV: Cloudflare + Fastly + AWS CloudFront + Google، نه فقط Cloudflare
    if (cdnT.isNotEmpty) {
      // Cursor-based sampling traverses the entire published CDN range inventory
      // over repeated passes. The batch is a work quantum, not a candidate ceiling.
      // Non-Cloudflare CDN ranges are emitted first; Cloudflare is deliberately last.
      final ips = _getCfIps(
        batchSize: 1024,
        liveRanges: _liveCdnRanges,
        cursors: _cfRangeCursors,
      );
      if (await _natTryScan(cdnT, ips,
          port: cdnT.first.port, label: 'لبه‌ی CDN', front: true)) {
        return true;
      }
      if (abort) return false;
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

    // مرحله ۳: اسکن همسایه‌های ASN عمداً اجرا نمی‌شود.
    // داشتن یک hostname/IP از یک شرکت، مجوز اسکن بقیه‌ی prefixهای همان ASN نیست.
    // محدوده‌های دستیِ مالک و فهرست relayهای صریح همچنان از مسیرهای جداگانه قابل آزمون‌اند.
    // مرحله ۴ (IP های باز ایران) حذف شد: یک IP باز ایران فوروارد نمی‌کند،
    // پس برای REALITY/TCP وقت تلف می‌کرد و هیچ‌وقت وصل نمی‌شد.
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
      _set('نت ملی: هیچ $label بازی پیدا نشد');
      return false;
    }
    final top = hits; // Every responsive endpoint remains eligible.
    final snis = <List<String>>[];
    if (front) {
      // Every SNI candidate is tested; concurrency is chunked, not truncated.
      for (var i = 0; i < top.length; i += 4) {
        final batch = top.skip(i).take(4).toList();
        snis.addAll(await Future.wait(batch.map((h) => nipFindFrontSnis(
          h.ip, port, cancelled: () => abort,
        ))));
        if (abort) return false;
      }
    }
    final matchingTemplates = tpls.where((t) => t.port == port).toList();
    if (matchingTemplates.isEmpty) return false;
    final candidateBatch = <Server>[];
    final candidateLinks = <String>{};
    Future<bool> flushCandidates() async {
      if (candidateBatch.isEmpty) return false;
      final batch = List<Server>.of(candidateBatch);
      candidateBatch.clear();
      candidateLinks.clear();
      if (await _connectLoop(batch, trust: false)) {
        final winner = current;
        if (winner != null) _natAdd(winner);
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
