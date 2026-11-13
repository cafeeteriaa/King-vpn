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
  final size = 1 << (32 - prefix);
  final start = base & ~(size - 1) & 0xFFFFFFFF;
  final step = size > maxPerBlock ? size ~/ maxPerBlock : 1;
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
  int want = 12,
  Duration budget = const Duration(minutes: 2),
  Duration timeout = const Duration(milliseconds: 1500),
  bool Function()? cancelled,
}) async {
  final hits = <NipHit>[];
  final deadline = DateTime.now().add(budget);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      if (hits.length >= want) return;
      if (cancelled != null && cancelled()) return;
      if (DateTime.now().isAfter(deadline)) return;
      if (next >= ips.length) return;
      final ip = ips[next++];
      final ms = await nipTcpProbe(ip, port, timeout);
      if (ms != null) hits.add(NipHit(ip, ms));
    }
  }

  final n = min(concurrency.clamp(1, 16), max(ips.length, 1));
  await Future.wait(List.generate(n, (_) => worker()));
  hits.sort((a, b) => a.ms.compareTo(b.ms));
  return hits;
}

/// فهرست بلوک‌های IPv4 ایران از RIPE (یک بار دانلود و بعد کش).
Future<List<String>> nipIranCidrs() async {
  final p = await SharedPreferences.getInstance();
  final cached = p.getStringList('plus_ir_cidr');
  if (cached != null && cached.isNotEmpty) return cached;
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await c
        .getUrl(Uri.parse(
            'https://stat.ripe.net/data/country-resource-list/data.json?resource=IR'))
        .timeout(const Duration(seconds: 15));
    final res = await req.close().timeout(const Duration(seconds: 20));
    final body = await res.transform(utf8.decoder).join();
    final j = jsonDecode(body);
    final raw = (j['data']['resources']['ipv4'] as List?) ?? const [];
    final list = raw.map((e) => '$e').where((e) => e.contains('/')).toList();
    if (list.isNotEmpty) await p.setStringList('plus_ir_cidr', list);
    return list;
  } catch (_) {
    return const [];
  } finally {
    c.close(force: true);
  }
}

/// همان کانفیگ سرور [t] را روی IP دیگری می‌سازد؛ SNI و Host اصلی حفظ می‌شوند.
String? nipSwapLink(Server t, String ip) {
  final l = t.link;
  final lower = l.toLowerCase();
  if (lower.startsWith('ss://')) return null;
  try {
    if (lower.startsWith('vmess://')) {
      var b = l.substring(8);
      b = b.padRight(b.length + (4 - b.length % 4) % 4, '=');
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
const natRelayHosts = <String>[];

Future<String?> nipResolve(String host) async {
  // DNSDOH: اول DoH (در نت ملی DNS معمولی جواب بسته می‌دهد)
  final d = await dohResolve(host);
  if (d != null) return d;
  try {
    final l = await InternetAddress.lookup(host).timeout(const Duration(seconds: 5));
    return l.isEmpty ? null : l.first.address;
  } catch (_) {
    return null;
  }
}

/// بلوک‌های هاست یک IP را برای نت ملی ذخیره می‌کند (کلید: IP).
Future<void> natPrefetchAsn(List<Server> list) async {
  var n = 0;
  for (final s in list) {
    if (n >= 20) break;
    if (s.cdn) continue;
    final ip = s.isIp ? s.host : await nipResolve(s.host);
    if (ip == null) continue;
    n++;
    await nipAsnPrefixes(ip); // نتیجه خودکار در کش ذخیره می‌شود
  }
}

/// بلوک‌های IPv4 اعلام‌شده‌ی شرکت هاست همان IP (از RIPE Stat).
Future<List<String>> nipAsnPrefixes(String ip) async {
  final prefs = await SharedPreferences.getInstance();
  final cacheKey = 'nip_asn_v1_$ip';
  final cached = prefs.getStringList(cacheKey);
  if (cached != null && cached.isNotEmpty) return cached;
  try {
    final r = await http
        .get(Uri.parse('https://stat.ripe.net/data/network-info/data.json?resource=$ip'))
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return const [];
    final asns = ((jsonDecode(r.body)['data']?['asns']) as List?) ?? const [];
    final out = <String>[];
    for (final a in asns.take(2)) {
      final rr = await http
          .get(Uri.parse('https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS$a'))
          .timeout(const Duration(seconds: 12));
      if (rr.statusCode != 200) continue;
      final prefixes = ((jsonDecode(rr.body)['data']?['prefixes']) as List?) ?? const [];
      for (final pe in prefixes) {
        final pr = '${pe['prefix']}';
        if (pr.contains('/') && !pr.contains(':')) out.add(pr);
      }
    }
    if (out.isNotEmpty) await prefs.setStringList(cacheKey, out);
    return out;
  } catch (_) {
    return const [];
  }
}

// FRONTSNI: کانفیگ‌های CDN: اگر SNI اصلی فیلتر شده باشد، SNI را به یک دامنه‌ی دیگر
// روی همان Cloudflare تغییر می‌دهیم و Host را همان سرور نگه می‌داریم.
// لیست کاندید؛ هر کدام که TLS روی IP باز کامل شد نگه داشته می‌شود.
// خودت می‌توانی دامنه‌های بیشتری به این لیست اضافه کنی.
const natFrontSnis = <String>[
  // V15: Iranian domains first. DPI sees these and lets traffic through.
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
  // Cloudflare domains after.
  'cdnjs.cloudflare.com',
  'www.cloudflare.com',
  'cloudflare.com',
  'speed.cloudflare.com',
  'workers.dev',
  'dash.cloudflare.com',
  'one.one.one.one',
  '1.1.1.1',
  'cloudflare-dns.com',
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
    try { sec?.destroy(); } catch (_) {}
    try { raw?.destroy(); } catch (_) {}
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
      var b = l.substring(8);
      b = b.padRight(b.length + (4 - b.length % 4) % 4, '=');
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

    // مرحله ۱: کانفیگ‌های CDN (SNI/Host) ← لبه‌های باز چند CDN
    // CDNDIV: Cloudflare + Fastly + AWS CloudFront + Google، نه فقط Cloudflare
    if (cdnT.isNotEmpty) {
      final cfSet = _cfRanges.toSet();
      final cfIps = <String>[];
      final otherIps = <String>[];
      for (final c in _liveCdnRanges) {
        if (cfSet.contains(c)) cfIps.addAll(nipExpandCidr(c, maxPerBlock: 512));
      }
      // PERFFIX: بقیه‌ی CDNها را فقط تا سقف هم‌اندازه‌ی Cloudflare بساز. قبلاً
      // همه‌ی بلوک‌های زنده (صدها بلوک × ۵۱۲) روی UI ساخته و بعد کوتاه می‌شد
      // که باعث قفل شدن اپ می‌شد.
      final cap = cfIps.isEmpty ? 6000 : cfIps.length;
      final rnd = Random();
      final others = _liveCdnRanges.where((c) => !cfSet.contains(c)).toList()
        ..shuffle(rnd);
      for (final c in others) {
        if (otherIps.length >= cap) break;
        otherIps.addAll(nipExpandCidr(c, maxPerBlock: 32));
      }
      if (otherIps.length > cap) otherIps.removeRange(cap, otherIps.length);
      final ips = <String>[...cfIps, ...otherIps];
      ips.shuffle(rnd);
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

    // مرحله ۳: IP های همان شرکت هاست سرور (ASN) روی همان پورت
    final t0 = direct.first;
    final sIp = t0.isIp ? t0.host : await nipResolve(t0.host);
    if (sIp != null) {
      final prefixes = await nipAsnPrefixes(sIp);
      if (prefixes.isNotEmpty) {
        final ips = <String>[];
        for (final p in prefixes.take(80)) {
          ips.addAll(nipExpandCidr(p, maxPerBlock: 256));
        }
        ips.shuffle(Random());
        if (ips.isNotEmpty &&
            await _natTryScan(direct, ips,
                port: t0.port, label: 'IP هم‌شرکت سرور')) {
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
      {required int port, required String label, bool front = false}) async {
    if (ips.isEmpty) return false;
    _set('نت ملی: جستجوی $label (${ips.length} آدرس)…');
    final hits = await nipScan(ips,
        port: port,
        want: 12,
        budget: const Duration(minutes: 2),
        cancelled: () => abort);
    if (abort) return false;
    if (hits.isEmpty) {
      _set('نت ملی: هیچ $label بازی پیدا نشد');
      return false;
    }
    final top = hits.take(12).toList();
    final snis = front
        ? await Future.wait(top.map((h) => nipFindFrontSni(h.ip, port)))
        : <String?>[];
    final cands = <Server>[];
    for (var i = 0; i < top.length && cands.length < 8; i++) {
      final t = tpls[i % tpls.length];
      final link = nipSwapLink(t, top[i].ip);
      if (link != null) {
        final c = Server.parse(link);
        if (c != null) cands.add(c);
      }
      final sni = i < snis.length ? snis[i] : null;
      if (sni != null && cands.length < 8) {
        final fl = nipSwapSni(t, top[i].ip, sni);
        if (fl != null) {
          final c = Server.parse(fl);
          if (c != null) cands.add(c);
        }
      }
    }
    if (cands.isEmpty) {
      _set('نت ملی: IP باز پیدا شد ولی هیچ SNI باز نگرفت ($label)');
      return false;
    }
    _set('نت ملی: امتحان ${cands.length} آدرس ($label)…');
    final ok = await _connectLoop(cands, trust: false);
    if (ok) {
      final w = current;
      if (w != null) _natAdd(w);
    }
    return ok;
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
