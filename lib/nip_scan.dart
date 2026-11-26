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

/// Scan every supplied endpoint unless an explicit hit/time limit or cancellation is requested.
Future<List<NipHit>> nipScan(
  List<String> ips, {
  int port = 443,
  int concurrency = 16,
  int? want,
  Duration? budget,
  Duration timeout = const Duration(milliseconds: 1500),
  bool Function()? cancelled,
}) async {
  if (ips.isEmpty || (want != null && want <= 0) ||
      (budget != null && budget <= Duration.zero) ||
      timeout <= Duration.zero || port < 1 || port > 65535) {
    return <NipHit>[];
  }
  final hits = <NipHit>[];
  final elapsed = Stopwatch()..start();
  var next = 0;

  Future<void> worker() async {
    while (true) {
      if (want != null && hits.length >= want) return;
      if (cancelled != null && cancelled()) return;
      if (budget != null && elapsed.elapsed >= budget) return;
      if (next >= ips.length) return;
      final ip = ips[next++];
      final ms = await nipTcpProbe(ip, port, timeout);
      if ((cancelled != null && cancelled()) ||
          (budget != null && elapsed.elapsed >= budget)) {
        return;
      }
      if (ms != null && (want == null || hits.length < want)) {
        hits.add(NipHit(ip, ms));
      }
    }
  }

  final n = min(natAdaptiveConcurrency(concurrency), max(ips.length, 1));
  await Future.wait(List.generate(n, (_) => worker()));
  natStableSort(hits, (a, b) => a.ms.compareTo(b.ms));
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

String _nipHostnameOrEmpty(String value) {
  final host = value.trim();
  if (host.isEmpty || InternetAddress.tryParse(host) != null) return '';
  return host;
}

/// Replace only the endpoint address/port. Preserve valid TLS SNI and HTTP Host;
/// never invent an IP literal as a hostname or graft generic IPs onto REALITY.
String? nipSwapLink(Server t, String ip, {int? port}) {
  final l = t.link;
  final lower = l.toLowerCase();
  if (lower.startsWith('ss://') || t.reality) return null;
  try {
    if (lower.startsWith('vmess://')) {
      final b = natB64Normalize(l.substring(8));
      final decoded = jsonDecode(utf8.decode(base64.decode(b)));
      if (decoded is! Map) return null;
      final j = Map<String, dynamic>.from(decoded);
      final originalSni = _nipHostnameOrEmpty((j['sni'] ?? '').toString());
      final originalHost = _nipHostnameOrEmpty((j['host'] ?? '').toString());
      final fallbackHost = originalSni.isNotEmpty
          ? originalSni
          : _nipHostnameOrEmpty(t.host);
      j['add'] = ip;
      if (port != null) j['port'] = port.toString();
      if (originalSni.isNotEmpty) {
        j['sni'] = originalSni;
      } else {
        final fallbackSni = _nipHostnameOrEmpty(t.host);
        if (fallbackSni.isEmpty) {
          j.remove('sni');
        } else {
          j['sni'] = fallbackSni;
        }
      }
      if (j['net'] == 'ws' && originalHost.isEmpty) {
        if (fallbackHost.isEmpty) {
          j.remove('host');
        } else {
          j['host'] = fallbackHost;
        }
      }
      return 'vmess://${base64.encode(utf8.encode(jsonEncode(j)))}';
    }
    final u = Uri.parse(l);
    final q = Map<String, String>.from(u.queryParameters);
    final originalSni = _nipHostnameOrEmpty(q['sni'] ?? '');
    final fallbackSni = _nipHostnameOrEmpty(t.host);
    if (originalSni.isEmpty && fallbackSni.isEmpty) {
      q.remove('sni');
    } else if (originalSni.isEmpty) {
      q['sni'] = fallbackSni;
    }
    if (q['type'] == 'ws' && _nipHostnameOrEmpty(q['host'] ?? '').isEmpty) {
      final host = originalSni.isNotEmpty ? originalSni : fallbackSni;
      if (host.isEmpty) {
        q.remove('host');
      } else {
        q['host'] = host;
      }
    }
    return u.replace(host: ip, port: port ?? (u.hasPort ? u.port : null),
        queryParameters: q).toString();
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

/// Resolve every address family/record for an exact configured hostname.
Future<List<String>> nipResolveAll(String host) async {
  final literal = InternetAddress.tryParse(host.trim());
  if (literal != null) return <String>[literal.address];
  final out = <String>{};
  if (!NatNetworkDiagnosis.preferDomestic) {
    final doh = await dohResolve(host);
    if (doh != null) out.add(doh);
  }
  try {
    final addresses = await InternetAddress.lookup(host)
        .timeout(const Duration(seconds: 5));
    out.addAll(addresses.map((address) => address.address));
  } catch (_) {
    // Keep any independently verified DoH result; otherwise report no result.
  }
  return out.toList(growable: false);
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

/// آخرین شکست RIPE برای هر IP (حافظه‌ی موقت، جدا از کش دائمی).
final Map<String, DateTime> _asnFailAt = <String, DateTime>{};

/// بلوک‌های IPv4 اعلام‌شده‌ی شرکت هاست همان IP (از RIPE Stat).
Future<List<String>> nipAsnPrefixes(String ip) async {
  final prefs = await SharedPreferences.getInstance();
  final cacheKey = 'nip_asn_v1_$ip';
  final cached = prefs.getStringList(cacheKey);
  if (cached != null && cached.isNotEmpty) return cached;
  // NATOPT: RIPE خارج از کشور است. وقتی جهانی قطع است فقط کش معتبر است؛ شبکه نمی‌زنیم.
  if (NatNetworkDiagnosis.preferDomestic) return const [];
  // NATOPT: شکست اخیر را ۱۵ دقیقه به خاطر می‌سپاریم تا هر دور جستجو ۳ بار ۱۲ ثانیه تایم‌اوت نخورد.
  final failAt = _asnFailAt[ip];
  if (failAt != null && DateTime.now().difference(failAt) < const Duration(minutes: 15)) {
    return const [];
  }
  try {
    final r = await http
        .get(Uri.parse('https://stat.ripe.net/data/network-info/data.json?resource=$ip'))
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) {
      _asnFailAt[ip] = DateTime.now();
      return const [];
    }
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
    if (out.isNotEmpty) {
      await prefs.setStringList(cacheKey, out);
    } else {
      _asnFailAt[ip] = DateTime.now();
    }
    return out;
  } catch (_) {
    _asnFailAt[ip] = DateTime.now();
    return const [];
  }
}

// Full hostname inventory: retain the original CDN-oriented names and add the
// app's complete SNI domain inventory. IP literals are never valid TLS SNI.
final List<String> natFrontSnis = <String>{
  'cdnjs.cloudflare.com',
  'www.cloudflare.com',
  'speed.cloudflare.com',
  'one.one.one.one',
  'cloudflare-dns.com',
  'api.cloudflare.com',
  'developers.cloudflare.com',
  'support.cloudflare.com',
  'blog.cloudflare.com',
  'community.cloudflare.com',
  'www.cloudflarestatus.com',
  'radar.cloudflare.com',
  'dash.cloudflare.com',
  ...kAutoSniDomains,
}.where((value) =>
    value.trim().isNotEmpty && InternetAddress.tryParse(value.trim()) == null)
 .toList(growable: false);

/// روی IP:port یک TLS با SNI داده‌شده کامل شود؟ برمی‌گرداند همان SNI یا null.
Future<String?> nipFrontProbe(String ip, int port, String sni) async {
  if (sni.trim().isEmpty || InternetAddress.tryParse(sni.trim()) != null) {
    return null;
  }
  Socket? raw;
  SecureSocket? sec;
  try {
    raw = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 2000));
    sec = await SecureSocket.secure(raw, host: sni)
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

/// Replace SNI only for TLS hostname profiles; keep the original HTTP Host.
String? nipSwapSni(Server t, String ip, String sni, {int? port}) {
  final l = t.link;
  final lower = l.toLowerCase();
  if (lower.startsWith('ss://') || !t.tls || t.reality ||
      echFromLink(l).isNotEmpty ||
      _nipHostnameOrEmpty(sni).isEmpty) {
    return null;
  }
  try {
    if (lower.startsWith('vmess://')) {
      final b = natB64Normalize(l.substring(8));
      final decoded = jsonDecode(utf8.decode(base64.decode(b)));
      if (decoded is! Map) return null;
      final j = Map<String, dynamic>.from(decoded);
      final oldSni = _nipHostnameOrEmpty((j['sni'] ?? '').toString());
      final oldHost = _nipHostnameOrEmpty((j['host'] ?? '').toString());
      final fallbackHost = oldHost.isNotEmpty
          ? oldHost
          : (oldSni.isNotEmpty ? oldSni : _nipHostnameOrEmpty(t.host));
      j['add'] = ip;
      if (port != null) j['port'] = port.toString();
      j['sni'] = sni;
      if (j['net'] == 'ws' && fallbackHost.isNotEmpty) {
        j['host'] = fallbackHost;
      }
      return 'vmess://${base64.encode(utf8.encode(jsonEncode(j)))}';
    }
    final u = Uri.parse(l);
    final q = Map<String, String>.from(u.queryParameters);
    if (_nipHostnameOrEmpty(q['host'] ?? '').isEmpty) {
      final fallbackHost = _nipHostnameOrEmpty(q['sni'] ?? '') ;
      final host = fallbackHost.isNotEmpty ? fallbackHost : _nipHostnameOrEmpty(t.host);
      if (host.isNotEmpty) q['host'] = host;
    }
    q['sni'] = sni;
    return u.replace(host: ip, port: port ?? (u.hasPort ? u.port : null),
        queryParameters: q).toString();
  } catch (_) {
    return null;
  }
}

extension NipHunt on _HomePageState {
  static bool _natHuntBusy = false;

  /// Re-test every exact IP saved by the user or present in their server
  /// profiles. A public ASN/CIDR is metadata, not permission to scan its range.
  Future<bool> _natIpHunt() async {
    if (!nationalMode || connected || abort || _natHuntBusy) return false;
    _natHuntBusy = true;
    try {
      final templates = <Server>[];
      final seen = <String>{};
      final pool = <Server>[
        ...good,
        ...pending,
        for (final entry in _resMap.values) entry.s,
      ];
      for (final server in pool) {
        if (server.link.toLowerCase().startsWith('ss://') || server.reality) {
          continue;
        }
        if (seen.add(server.key)) templates.add(server);
      }
      if (templates.isEmpty) {
        _set('برای جایگزینی IP، کانفیگ TLS/WS قابل‌استفاده در منابع فعلی وجود ندارد');
        return false;
      }

      final savedIps = <String>{
        for (final entry in _goldIps.values) entry.ip,
        ...natRelayHosts,
      };
      await goldLoad();
      savedIps.addAll(<String>{for (final entry in _goldIps.values) entry.ip});
      for (final server in templates) {
        if (abort) return false;
        if (server.isIp) {
          savedIps.add(server.host);
        } else {
          savedIps.addAll(await nipResolveAll(server.host));
        }
      }
      if (savedIps.isEmpty) {
        _set('IP مشخصی در پوشه یا endpointهای کانفیگ پیدا نشد');
        return false;
      }
      final ips = savedIps.toList(growable: false);
      _set('نت ملی: بررسی کامل ${ips.length} IP ذخیره‌شده و endpointهای خود کانفیگ');

      // Process every compatible profile and every port explicitly carried by
      // that profile. The scan is resumable by user cancellation, not truncated
      // to a fixed number of templates, hits, or SNI names.
      for (final server in templates) {
        if (abort) return false;
        if (server.port < 1 || server.port > 65535) continue;
        final front = server.cdn && server.tls;
        if (await _natTryScan(
          <Server>[server],
          ips,
          port: server.port,
          label: 'endpoint ${server.name}',
          front: front,
        )) {
          return true;
        }
      }
      _set('نت ملی: همه IPهای مشخص‌شده برای کانفیگ‌های موجود بررسی شدند؛ اتصال واقعی تأیید نشد');
      return false;
    } finally {
      _natHuntBusy = false;
    }
  }

  /// TCP-open is only a discovery signal. Each resulting profile is passed to
  /// the real Core/TUN connection path before it can be stored as successful.
  Future<bool> _natTryScan(List<Server> tpls, List<String> ips,
      {required int port, required String label, bool front = false}) async {
    if (ips.isEmpty || tpls.isEmpty) return false;
    _set('نت ملی: جستجوی $label روی ${ips.length} آدرس، پورت $port…');
    const batchSize = 256;
    var totalHits = 0;
    var checkedHits = 0;
    for (var offset = 0; offset < ips.length; offset += batchSize) {
      if (abort) return false;
      final batch = ips.skip(offset).take(batchSize).toList(growable: false);
      final hits = await nipScan(
        batch,
        port: port,
        concurrency: natAdaptiveConcurrency(0),
        timeout: const Duration(milliseconds: 1500),
        cancelled: () => abort,
      );
      if (abort) return false;
      totalHits += hits.length;
      for (final hit in hits) {
        if (abort) return false;
        checkedHits++;
        final template = tpls[(offset + checkedHits) % tpls.length];
        final links = <String?>[
          nipSwapLink(template, hit.ip, port: port),
        ];
        if (front) {
          final sni = await nipFindFrontSni(hit.ip, port);
          if (abort) return false;
          if (sni != null) {
            links.add(nipSwapSni(template, hit.ip, sni, port: port));
          }
        }
        for (final link in links) {
          if (abort) return false;
          if (link == null) continue;
          final parsed = Server.parse(link);
          if (parsed == null) continue;
          _set('نت ملی: آزمون Core/TUN برای endpoint $checkedHits • ${hit.ip}:$port');
          if (await _connectLoop(<Server>[parsed], trust: false)) {
            final winner = current;
            if (winner != null) _natAdd(winner);
            return true;
          }
        }
      }
    }
    _set('نت ملی: تمام $checkedHits پاسخ TCP بررسی شد؛ هیچ اتصال واقعی تأیید نشد');
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
