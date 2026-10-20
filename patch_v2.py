#!/usr/bin/env python3
# patch_v2.py
# Applies exact, verified patches to the copied app sources (build_app/lib).
# Every patch must match EXACTLY ONCE. If not, the build stops with a clear message.

import os
import sys

LIB = sys.argv[1] if len(sys.argv) > 1 else 'build_app/lib'


def patch(fname, old, new):
    path = os.path.join(LIB, fname)
    with open(path, encoding='utf-8') as f:
        src = f.read()
    n = src.count(old)
    if n != 1:
        print(f'ERROR: {fname}: expected 1 match, found {n} for: {old[:70]!r}')
        sys.exit(1)
    src = src.replace(old, new, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src)
    print(f'OK: {fname} <- {old[:50]!r}')


# ---------------------------------------------------------------------------
# New part file: IP scan + national-network IP hunt (part of main.dart, no imports)
# ---------------------------------------------------------------------------
NIP_FILE = r'''part of 'main.dart';

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
  int concurrency = 150,
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

  final n = min(concurrency, max(ips.length, 1));
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
    for (final s in [...good, ...pending, ..._resMap.values]) {
      if (s.isIp || s.link.toLowerCase().startsWith('ss://')) continue;
      if (!seen.add(s.host)) continue;
      templates.add(s);
      if (templates.length >= 5) break;
    }
    if (templates.isEmpty) {
      _set('برای جستجوی IP سرور دامنه‌دار نمونه نداریم؛ یک بار با سرورهای پوشه وصل شو');
      return false;
    }

    final blocks = await nipIranCidrs();
    if (blocks.isEmpty) {
      _set('فهرست IP ایران گرفته نشد؛ اینترنت را چک کن');
      return false;
    }
    final per = max(16, 30000 ~/ blocks.length);
    final ips = <String>[];
    for (final b in blocks) {
      ips.addAll(nipExpandCidr(b, maxPerBlock: per));
    }
    ips.shuffle(Random());

    final port = templates.first.port;
    _set('نت ملی: جستجوی IP سالم ایران (${ips.length} آدرس)…');
    final hits = await nipScan(ips,
        port: port,
        want: 12,
        budget: const Duration(minutes: 2),
        cancelled: () => abort);
    if (abort) return false;
    if (hits.isEmpty) {
      _set('نت ملی: هیچ IP بازی پیدا نشد');
      return false;
    }

    final cands = <Server>[];
    for (var i = 0; i < hits.length && cands.length < 8; i++) {
      final t = templates[i % templates.length];
      final link = nipSwapLink(t, hits[i].ip);
      if (link == null) continue;
      final c = Server.parse(link);
      if (c != null) cands.add(c);
    }
    if (cands.isEmpty) return false;

    _set('نت ملی: امتحان ${cands.length} IP پیداشده…');
    final ok = await _connectLoop(cands, trust: false);
    if (ok) {
      final w = current;
      if (w != null) _natAdd(w);
    }
    return ok;
  }
}
'''

# ---------------------------------------------------------------------------
# Patches to existing files
# ---------------------------------------------------------------------------

# 1) main.dart: include the new part file
patch('main.dart',
      "part 'extras_plus.dart';",
      "part 'extras_plus.dart';\npart 'nip_scan.dart';")

# 2) main.dart: hunt after the normal list fails (national mode only)
patch('main.dart',
      "      if (await _connectLoop(list, trust: false)) return true;\n",
      "      if (await _connectLoop(list, trust: false)) return true;\n"
      "      if (nationalMode && await _natIpHunt()) return true; // NIPHUNT\n")

# 3) main.dart: hunt also when there is nothing to try (empty round)
patch('main.dart',
      "          emptyRounds++;\n",
      "          if (nationalMode && await _natIpHunt()) return true; // NIPHUNT\n"
      "          emptyRounds++;\n")

# 4) auto_test.dart: core-dead streak counter
patch('auto_test.dart',
      "  static bool _abortRequested = false;",
      "  static bool _abortRequested = false;\n"
      "  // CORE-DEAD: how many times in a row the core did not open its local port\n"
      "  static int _atCoreDeadStreak = 0;")

patch('auto_test.dart',
      "    _atStopEarly = false;\n    _atVerdict = '';",
      "    _atStopEarly = false;\n    _atVerdict = '';\n    _atCoreDeadStreak = 0;")

patch('auto_test.dart',
      "    _atFailStreak = 0;\n\n    await _atWait(const Duration(seconds: 12), note:",
      "    _atFailStreak = 0;\n    _atCoreDeadStreak = 0;\n\n    await _atWait(const Duration(seconds: 12), note:")

patch('auto_test.dart',
      "      _atAdd('ENG-FAIL',",
      """      // CORE-DEAD: the core does not even open its local port, several times in a row.
      // That means the app/core layer is broken, not the configs.
      if (!coreUp && !lastFail.contains('uuid')) {
        _atCoreDeadStreak++;
        if (_atCoreDeadStreak >= 3) {
          _atVerdict = 'هسته‌ی V2Ray ابدیت شده: $_atCoreDeadStreak بار پشت‌سرهم روی پورت محلی بالا نیامد. '
              'کانفیگ‌ها مقصر نیستند؛ اجرای هسته در اپ شکسته است (پروسه‌ی قبلی بسته نشده یا پلاگین). '
              'راه حل: اپ را کامل ببند و دوباره باز کن. اگر تکرار شد، logcat را همان لحظه بفرست.';
        }
      } else {
        _atCoreDeadStreak = 0;
      }
      _atAdd('ENG-FAIL',""")

# 5) write the new part file
with open(os.path.join(LIB, 'nip_scan.dart'), 'w', encoding='utf-8') as f:
    f.write(NIP_FILE)
print('OK: nip_scan.dart written')
print('ALL PATCHES APPLIED')
