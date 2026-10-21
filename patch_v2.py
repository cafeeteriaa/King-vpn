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
    final pool = <Server>[];
    pool.addAll(good);
    pool.addAll(pending);
    pool.addAll(_resMap.values.whereType<Server>());
    for (final s in pool) {
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
# Patches to the ORIGINAL files from the zip (must match exactly once)
# ---------------------------------------------------------------------------

# 1) main.dart: include the new part file
patch('main.dart',
      "part 'extras_plus.dart';",
      "part 'extras_plus.dart';\npart 'nip_scan.dart';")

# 2) main.dart: national IP hunt after the normal list fails
patch('main.dart',
      "      if (await _connectLoop(list, trust: false)) return true;\n",
      "      if (await _connectLoop(list, trust: false)) return true;\n"
      "      if (nationalMode && await _natIpHunt()) return true; // NIPHUNT\n")

# 3) main.dart: national IP hunt also on an empty round
patch('main.dart',
      "          emptyRounds++;\n",
      "          if (nationalMode && await _natIpHunt()) return true; // NIPHUNT\n"
      "          emptyRounds++;\n")

# 4) auto_test.dart: CORE-DEAD verdict (core never opens its local port)
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

# 4b) main.dart: national button turns on Ultra (matrix) for that connect only
patch('main.dart',
      "      natLevel = natForce ? 2 : 0;",
      "      ultraMode = natForce; // NATULTRA: Ultra/matrix only for the national button\n"
      "      natLevel = natForce ? 2 : 0;")

# 4c) main.dart: IP تمیز (clean IP) ON by default, once, for normal and national connect
patch('main.dart',
      "      // FOLDERONLY: healthy servers are kept only in the folder",
      "      // CIPDEFAULT: IP تمیز روشن پیش‌فرض (یک بار برای همه)\n"
      "      if (p.getBool('cip_v2') != true) {\n"
      "        cleanIpMode = true;\n"
      "        await p.setBool('cip_v2', true);\n"
      "        await _saveSettings();\n"
      "      }\n"
      "      // FOLDERONLY: healthy servers are kept only in the folder")

# 4e) main.dart: DISCONNECTFIX — a connect still in flight must not reconnect after Disconnect
patch('main.dart',
      "    wantVpn = false;\n    pendingFailover = false;",
      "    wantVpn = false;\n    _connGen++; // DISCONNECTFIX: cancel any connect still in flight\n    pendingFailover = false;")

# 4f) main.dart: IDMDEFAULT — حالت شکست‌ناپذیر همیشه روشن (یک بار، کاربر می‌تواند خاموشش کند)
patch('main.dart',
      "      // FOLDERONLY: healthy servers are kept only in the folder",
      "      // IDMDEFAULT: حالت شکست‌ناپذیر همیشه روشن (یک بار)\n"
      "      if (p.getBool('idm_v2') != true) {\n"
      "        indestructibleMode = true;\n"
      "        await p.setBool('idm_v2', true);\n"
      "        await _saveSettings();\n"
      "      }\n"
      "      // FOLDERONLY: healthy servers are kept only in the folder")

# 4g) main.dart: NATDEFAULTS — Fragment و اتصال با IP (DoH) روشن (یک بار)
# Fragment is forced off outside national mode by the existing code, so it only acts in national mode.
patch('main.dart',
      "      // FOLDERONLY: healthy servers are kept only in the folder",
      "      // NATDEFAULTS: فرگمنت و اتصال با IP (DoH) روشن (یک بار)\n"
      "      if (p.getBool('nat_v2') != true) {\n"
      "        fragEnabled = true;\n"
      "        ipMode = true;\n"
      "        await p.setBool('nat_v2', true);\n"
      "        await _saveSettings();\n"
      "      }\n"
      "      // FOLDERONLY: healthy servers are kept only in the folder")

# 4i) DOHAUTO: خلبان IP (DoH) را خودش روشن/خاموش می‌کند بر اساس نتیجه‌ی اتصال
patch('iran_ai_extras.dart',
      "bool localPilotOn = false;",
      "int _localConnFail = 0; // DOHAUTO: connect failures in a row\nbool localPilotOn = false;")

patch('iran_ai_extras.dart',
      "      _localReschedule();\n    } catch (e) {",
      "      // DOHAUTO: IP (DoH) را خلبان خودش روشن/خاموش می‌کند بر اساس نتیجه‌ی اتصال\n"
      "      if (connected) {\n"
      "        _localConnFail = 0;\n"
      "        if (!ipMode) {\n"
      "          ipMode = true;\n"
      "          await _saveSettings();\n"
      "        }\n"
      "      } else if (wantVpn) {\n"
      "        _localConnFail++;\n"
      "        if (_localConnFail >= 2 && ipMode) {\n"
      "          ipMode = false;\n"
      "          _localConnFail = 0;\n"
      "          await _saveSettings();\n"
      "        }\n"
      "      }\n"
      "      _localReschedule();\n    } catch (e) {")

# 4j) TOGGLES: خلبان Fragment، ماتریس (Ultra)، IP تمیز و DoH را خودش تنظیم می‌کند
patch('iran_ai_extras.dart',
      "bool localPilotOn = false;",
      "int _localGoodTog = 0; // TOGGLES: connected ticks in a row\nbool localPilotOn = false;")

patch('iran_ai_extras.dart',
      "  Future<void> localPilotTick({bool force = false}) async {",
      "  // TOGGLES: خلبان بر اساس نتیجه‌ی اتصال، Fragment / ماتریس / IP تمیز را خودش روشن و خاموش می‌کند\n"
      "  void _localTuneToggles() {\n"
      "    var changed = false;\n"
      "    if (connected) {\n"
      "      _localGoodTog++;\n"
      "      // وصل و پایدار: ماتریس سنگین است، خاموشش کن تا دیتا کم شود\n"
      "      if (_localGoodTog >= 3 && ultraMode) {\n"
      "        ultraMode = false;\n"
      "        changed = true;\n"
      "      }\n"
      "    } else if (wantVpn) {\n"
      "      _localGoodTog = 0;\n"
      "      if (_localFailStreak >= 2) {\n"
      "        // جستجو شکست می‌خورد: IP تمیز و Fragment (نت ملی) را روشن کن\n"
      "        if (!cleanIpMode) {\n"
      "          cleanIpMode = true;\n"
      "          changed = true;\n"
      "        }\n"
      "        if (nationalMode && !fragEnabled) {\n"
      "          fragEnabled = true;\n"
      "          changed = true;\n"
      "        }\n"
      "      }\n"
      "      if (_localFailStreak >= 3 && nationalMode && !ultraMode) {\n"
      "        ultraMode = true;\n"
      "        changed = true;\n"
      "      }\n"
      "    }\n"
      "    if (changed) unawaited(_saveSettings().catchError((e) => logError(e)));\n"
      "  }\n\n"
      "  Future<void> localPilotTick({bool force = false}) async {")

patch('iran_ai_extras.dart',
      "      await _localApply(decision);",
      "      await _localApply(decision);\n"
      "      _localTuneToggles(); // TOGGLES")

# 4k) NATKICK: خلبان وقتی نت ملی است همان «جستجوی سرور با نت ملی» را اجرا کند
patch('iran_ai_extras.dart',
      "  Future<void> localPilotTick({bool force = false}) async {",
      "  // NATKICK: در حالت نت ملی، خلبان همان مسیر دکمه‌ی «جستجوی سرور با نت ملی» را اجرا می‌کند\n"
      "  Future<void> _localNatConnect() async {\n"
      "    if (nationalMode && !connected && !busy) natForce = true;\n"
      "    await connect();\n"
      "  }\n\n"
      "  Future<void> localPilotTick({bool force = false}) async {")

patch('iran_ai_extras.dart',
      "          _applyTurboLevers();\n          await connect();",
      "          _applyTurboLevers();\n          await _localNatConnect();")

patch('iran_ai_extras.dart',
      "        if (decision.action == 'none' || decision.action == 'connect') {\n          await connect();",
      "        if (decision.action == 'none' || decision.action == 'connect') {\n          await _localNatConnect();")

# 4l) FOLDERFIRST: پوشه‌ی سرورها فقط وقتی اول تست می‌شود که نت ملی باشد (نه با حالت شکست‌ناپذیر در نت جهانی)
patch('main.dart',
      "    final forceSaved = nationalMode || natForce || indestructibleMode;",
      "    final forceSaved = nationalMode || natForce; // FOLDERFIRST: folder only in national mode")

# 4m) TESTUPGRADE: هشدار‌های اشتباه کمتر، گزارش شبکه/خلبان، و سناریوی نت ملی
patch('auto_test.dart',
      "  static const _busyStuckLimit = Duration(seconds: 120);",
      "  static const _busyStuckLimit = Duration(seconds: 240); // TESTUPGRADE")

patch('auto_test.dart',
      "  static const _switchingStuckLimit = Duration(seconds: 40);",
      "  static const _switchingStuckLimit = Duration(seconds: 90); // TESTUPGRADE")

patch('auto_test.dart',
      "      if (now.difference(_switchingSince!) > _switchingStuckLimit) {",
      "      if (!busy && now.difference(_switchingSince!) > _switchingStuckLimit) { // TESTUPGRADE")

patch('auto_test.dart',
      "    buf.writeln('یافته‌ها: ${_findings.length}');",
      "    buf.writeln('یافته‌ها: ${_findings.length}');\n"
      "    buf.writeln('🌐 شبکه: ${nationalMode ? 'نت ملی' : 'نت جهانی'} • خلبان: ${localPilotOn ? 'روشن' : 'خاموش'}');\n"
      "    buf.writeln('⚙ تنظیمات: IP تمیز=${cleanIpMode ? 'روشن' : 'خاموش'} • DoH=${ipMode ? 'روشن' : 'خاموش'} • Fragment=${fragEnabled ? 'روشن' : 'خاموش'} • ماتریس=${ultraMode ? 'روشن' : 'خاموش'} • شکست‌ناپذیر=${indestructibleMode ? 'روشن' : 'خاموش'}');")

patch('auto_test.dart',
      "      await _atScenarioLongStable(); // 5",
      "      await _atScenarioLongStable(); // 5\n      await _atScenarioNational(); // 6 TESTUPGRADE")

patch('auto_test.dart',
      "extension AutoTestEngine on _HomePageState {",
      "extension AutoTestEngine on _HomePageState {\n"
      "  /// سناریو ۶: تشخیص شبکه (جهانی یا ملی) و ثبت آن در گزارش\n"
      "  Future<void> _atScenarioNational() async {\n"
      "    _scenario = 6;\n"
      "    autoTestText.value = 'سناریو ۶: تشخیص شبکه';\n"
      "    if (busy || switching || connected) return;\n"
      "    try {\n"
      "      await _natDetect();\n"
      "    } catch (e) {\n"
      "      _atAdd('NAT-DETECT', 'تشخیص شبکه خطا داد: $e');\n"
      "      return;\n"
      "    }\n"
      "    dbg('🧪 تشخیص شبکه: ${nationalMode ? 'نت ملی' : 'نت جهانی'}');\n"
      "  }\n")

# 4n) TESTDEEP: شمارش تعویض‌های خلبان (PILOT-FLAP)، و خلاصه‌ی سناریوی رسیده‌شده در گزارش
patch('auto_test.dart',
      "  static int _scenario = 0;",
      "  static int _scenario = 0;\n"
      "  // PILOT-FLAP: how many times the pilot switched the server during this run\n"
      "  static int _atPilotSwitches = 0;")

patch('auto_test.dart',
      "    _scenario = 0;\n    _busySince = null;",
      "    _scenario = 0;\n    _atPilotSwitches = 0;\n    _busySince = null;")

patch('auto_test.dart',
      "    _samples.add(s);",
      "    _samples.add(s);\n"
      "    // PILOT-FLAP: a server change caused by the pilot, counted once per change\n"
      "    if (_samples.length >= 2) {\n"
      "      final prevWhy = _samples[_samples.length - 2].lastWhy;\n"
      "      if (lastWhy != prevWhy && lastWhy.contains('خلبان')) {\n"
      "        _atPilotSwitches++;\n"
      "      }\n"
      "      if (_atPilotSwitches == 6) {\n"
      "        _atAdd('PILOT-FLAP', 'خلبان ۶ بار سرور را عوض کرد؛ شاید بیش از حد تعویض می‌کند');\n"
      "      }\n"
      "    }")

patch('auto_test.dart',
      "    buf.writeln('نمونه وضعیت: ${_samples.length}');",
      "    buf.writeln('نمونه وضعیت: ${_samples.length}');\n"
      "    buf.writeln('🧭 سناریوی رسیده‌شده: $_scenario از ۶ • تعویض‌های خلبان: $_atPilotSwitches');")

# 4o) TESTDEEP2: راه‌حل برای کدهای جدید، و تشخیص خطاهای بلعیده‌شده‌ی بخش native (مثل MissingPluginException)
patch('auto_test.dart',
      "  static int _scenario = 0;",
      "  static int _scenario = 0;\n"
      "  // PLUGIN-SWALLOW: where this run's log starts inside errorLog\n"
      "  static int _atLogStart = 0;")

patch('auto_test.dart',
      "    _scenario = 0;\n    _atPilotSwitches = 0;",
      "    _scenario = 0;\n    _atPilotSwitches = 0;\n    _atLogStart = errorLog.value.length;")

patch('auto_test.dart',
      "    final elapsed = _startedAt == null",
      "    // PLUGIN-SWALLOW: platform errors the app caught silently during this run\n"
      "    final logWin = errorLog.value.length >= _atLogStart\n"
      "        ? errorLog.value.substring(_atLogStart)\n"
      "        : errorLog.value;\n"
      "    final swallowed = RegExp('بلعیده|MissingPluginException').allMatches(logWin).length;\n"
      "    if (swallowed > 0) {\n"
      "      _atAdd('PLUGIN-SWALLOW', 'خطای بخش native اندروید $swallowed بار بلعیده شد (مثلاً کانال vpn/bg)');\n"
      "    }\n"
      "    final elapsed = _startedAt == null")

patch('auto_test.dart',
      "      case 'CRASH':",
      "      case 'PILOT-FLAP':\n"
      "        return [\n"
      "          'lib/iran_ai_extras.dart → localPilotTick / _localApply',\n"
      "          'خلبان بیش از حد سرور را عوض کرد',\n"
      "          'قانون مدت ماندن روی سرور در خلبان وجود ندارد؛ باید در تصمیم تعویض (localPilotTick / _localDecide) اضافه شود',\n"
      "        ];\n"
      "      case 'NAT-DETECT':\n"
      "        return [\n"
      "          'lib/main.dart → _natDetect',\n"
      "          'تشخیص شبکه (جهانی یا ملی) خطا داد',\n"
      "          'متن خطا را بفرست؛ معمولاً به دسترسی سایت‌های تست یا لغو زودهنگام مربوط است',\n"
      "        ];\n"
      "      case 'PLUGIN-SWALLOW':\n"
      "        return [\n"
      "          'lib/main.dart → _startWatch (کانال vpn/bg)',\n"
      "          'بخش native اندروید متد alive را ندارد؛ هر دقیقه خطا می‌دهد ولی اتصال قطع نمی‌شود',\n"
      "          'متد alive در کد اندروید پیاده‌سازی نشده (فقط در Dart تعریف شده). اپ کار می‌کند، ولی یا باید در MainActivity اضافه شود یا این فراخوانی حذف شود',\n"
      "        ];\n"
      "      case 'CRASH':")

# 4p) TESTFIX2: CONNECT-HANG فقط برای اتصال واقعی؛ SWITCH-FLAG-STUCK برای پرچم گیرکرده‌ی تعویض با راه‌حل
patch('auto_test.dart',
      "  static DateTime? _busySince;",
      "  static DateTime? _busySince;\n"
      "  // TESTFIX2: true only while _atConnectEngine is waiting for a connect\n"
      "  static bool _atConnecting = false;\n"
      "  static DateTime? _switchFlagSince;")

patch('auto_test.dart',
      "    dbg('🧪 اتصال موتور: $label ($id)');\n    await connect();",
      "    dbg('🧪 اتصال موتور: $label ($id)');\n    _atConnecting = true;\n    try {\n      await connect();\n    } finally {\n      _atConnecting = false;\n    }")

patch('auto_test.dart',
      "    if (busy && !connected) {",
      "    if (_atConnecting && busy && !connected) {")

patch('auto_test.dart',
      "    if (busy) {\n      _busySince ??= now;",
      "    // SWITCH-FLAG-STUCK: switching stays true while connected and idle (blocks later actions)\n"
      "    if (switching && connected && !busy) {\n"
      "      _switchFlagSince ??= now;\n"
      "      if (now.difference(_switchFlagSince!) > const Duration(seconds: 40)) {\n"
      "        _atAdd('SWITCH-FLAG-STUCK', 'switching=true با اتصال برقرار و بدون کار، بیش از 40s • موتور=$_currentEngine');\n"
      "        switching = false; // release it so later actions are not blocked\n"
      "        _switchFlagSince = null;\n"
      "      }\n"
      "    } else {\n"
      "      _switchFlagSince = null;\n"
      "    }\n"
      "    if (busy) {\n      _busySince ??= now;")

patch('auto_test.dart',
      "      case 'CRASH':",
      "      case 'SWITCH-FLAG-STUCK':\n"
      "        return [\n"
      "          'lib/main.dart → _swapTo / _failover / _doConnect (هر جایی که switching=true می‌شود)',\n"
      "          'پرچم switching بعد از وصل شدن آزاد نشده؛ اپ را در حالت «تعویض» نگه می‌دارد و کارهای بعدی را مسدود می‌کند',\n"
      "          'در finally همان تابع switching = false بگذار؛ تست همین الان آن را آزاد می‌کند و کد آن را نشان می‌دهد',\n"
      "        ];\n"
      "      case 'CRASH':")

# 4q) TESTNOAD: تست ۲۰ دقیقه‌ای هیچ تبلیغی نشان نمی‌دهد
patch('auto_test.dart',
      "part of 'main.dart';",
      "part of 'main.dart';\n"
      "// TESTNOAD: true only while the 20-minute test runs; the ad gate lets connects through\n"
      "bool autoTestAdFree = false;")

patch('auto_test.dart',
      "    _phase = _AtPhase.running;",
      "    _phase = _AtPhase.running;\n    autoTestAdFree = true; // TESTNOAD")

patch('auto_test.dart',
      "    _phase = _AtPhase.idle;",
      "    _phase = _AtPhase.idle;\n    autoTestAdFree = false; // TESTNOAD")

patch('main.dart',
      "    if (!requireRewardedAd || (_sessionValid && !_adEveryConnect)) return true;",
      "    if (autoTestAdFree) return true; // TESTNOAD: no ad during the 20-minute test\n"
      "    if (!requireRewardedAd || (_sessionValid && !_adEveryConnect)) return true;")

# 4r) SWITCHRELEASE: وقتی هسته CONNECTED می‌شود و برنامه بیکار است، پرچم گیرکرده‌ی switching آزاد شود
# (listener قبلاً در switching=true همه‌ی رویدادها را نادیده می‌گرفت، پس اتصال واقعی دیده نمی‌شد)
patch('main.dart',
      "      if (!mounted || busy || switching) return;\n      final on = st.state == 'CONNECTED';",
      "      if (st.state == 'CONNECTED' && wantVpn && mounted && !busy && switching) {\n"
      "        _unlockLater(); // SWITCHRELEASE: core is up and the app is idle, the flag is stale\n"
      "      }\n"
      "      if (!mounted || busy || switching) return;\n      final on = st.state == 'CONNECTED';")

# 4s) ALIVEONCE: کانال vpn/bg در اندروید متد alive ندارد؛ یک بار خطا می‌گیریم و دیگر صدا نمی‌زنیم
patch('main.dart',
      "const bgChannel = MethodChannel('vpn/bg');",
      "const bgChannel = MethodChannel('vpn/bg');\n"
      "bool _bgAliveUnsupported = false; // ALIVEONCE: native side has no 'alive' handler")

patch('main.dart',
      "        final alive = await bgChannel.invokeMethod<bool>('alive');",
      "        final alive = _bgAliveUnsupported\n"
      "            ? null\n"
      "            : await bgChannel.invokeMethod<bool>('alive').catchError((e) {\n"
      "                _bgAliveUnsupported = true; // ALIVEONCE\n"
      "                return null;\n"
      "              });")

# 4s) TESTDEEP3: busy در حال اتصال بودن از busy گیرکرده جدا شود؛ نبود فایل خطای هسته گزارش شود؛ راه‌حل برای هر دو
patch('auto_test.dart',
      "        _atAdd('BUSY-STUCK',",
      "        _atAdd(connected ? 'BG-BUSY' : 'BUSY-STUCK',")

patch('auto_test.dart',
      "    final elapsed = _startedAt == null",
      "    // XRAY-NOLOG: the core starts without its error file, so its own errors are invisible\n"
      "    final noLog = RegExp('فایل خطای هسته ساخته نشد').allMatches(logWin).length;\n"
      "    if (noLog > 0) {\n"
      "      _atAdd('XRAY-NOLOG', 'هسته $noLog بار بدون فایل خطا شروع شد؛ این فقط یک نشانه است؛ اگر اتصال برقرار شده بی‌اهمیت است');\n"
      "    }\n"
      "    final elapsed = _startedAt == null")

patch('auto_test.dart',
      "      case 'CRASH':",
      "      case 'BG-BUSY':\n"
      "        return [\n"
      "          'lib/main.dart → _runBusy (جستجوی پس‌زمینه / ردیف همه)',\n"
      "          'اتصال برقرار است ولی جستجوی پس‌زمینه پرچم busy را نگه داشته؛ کارهای دیگر (تعویض، قطع، تست) مسدود می‌شوند',\n"
      "          'وقتی connected=true است جستجوی پس‌زمینه را محدود کن (worker کمتر یا توقف) و قبل از هر کار دستی آن را متوقف کن',\n"
      "        ];\n"
      "      case 'XRAY-NOLOG':\n"
      "        return [\n"
      "          'lib/main.dart → _start (نوشتن کانفیگ هسته، کلید log.error)',\n"
      "          'هسته قبل از ساختن فایل خطا بسته شد؛ دلیل واقعی فقط در logcat اندروید است و این در تقریباً همه‌ی شکست‌ها تکرار شد',\n"
      "          'logcat را هنگام اتصال بگیر (فیلتر: xray یا V2RAY) و خطای اولین خط هسته را بفرست',\n"
      "        ];\n"
      "      case 'CRASH':")

# 4t) ABORTPOOL: وقتی کار متوقف شد، دسته‌ی تست موازی دیگر آیتم جدید برنمی‌دارد (گیر ABORT-STUCK)
patch('main.dart',
      "bool _bgAliveUnsupported = false;",
      "bool _bgAliveUnsupported = false;\n"
      "bool poolStop = false; // ABORTPOOL: stop taking new items in parallel tests")

patch('main.dart',
      "      if (i >= items.length) break;",
      "      if (i >= items.length || poolStop) break; // ABORTPOOL")

patch('main.dart',
      "    } on TimeoutException {\n      abort = true;",
      "    } on TimeoutException {\n      abort = true;\n      poolStop = true; // ABORTPOOL")

patch('main.dart',
      "      if (mounted) setState(() => busy = false);",
      "      poolStop = false; // ABORTPOOL\n      if (mounted) setState(() => busy = false);")

# 4u) DATASAVE: وقتی وصل هستیم، بررسی پس‌زمینه‌ی سرورها حداکثر هر ۱۰ دقیقه (قبلاً هر ~۴ ثانیه و دیتای زیاد)
patch('main.dart',
      "    if (!wantVpn || abort || upBusy || appGone) return;",
      "    if (!wantVpn || abort || upBusy || appGone) return;\n"
      "    // DATASAVE: while connected, background re-checks run at most every 10 minutes\n"
      "    if (connected && DateTime.now().difference(lastStandby) < const Duration(minutes: 10)) return;")

# 4v) ABORTPOOL2: هر اجرای جدید از پرچم توقف قبلی پاک شود (وگرنه بعد از قطع، تست موازی بلافاصله خالی می‌ماند)
patch('main.dart',
      "  Future<void> _runBusy(Future<void> Function() f) async {\n    if (busy) return;",
      "  Future<void> _runBusy(Future<void> Function() f) async {\n    if (busy) return;\n    poolStop = false; // ABORTPOOL2: a new run starts clean")

# 4w) TIMEOUTFIX: مهلت تست بعد از توقف با رفتار واقعی اپ هماهنگ شد (اپ تا ۹۰ ثانیه صبر می‌کند)
patch('auto_test.dart',
      "        timeout: const Duration(seconds: 30), label: 'آزاد شدن بعد از abort');",
      "        timeout: const Duration(seconds: 100), label: 'آزاد شدن بعد از abort'); // TIMEOUTFIX: app waits up to 90s")

# 4x) LOGFIX: تست‌های PLUGIN-SWALLOW و XRAY-NOLOG باید از dbgLines بخوانند (قبلاً از errorLog می‌خواندند و هرگز فعال نمی‌شدند)
patch('auto_test.dart',
      "extension AutoTestEngine on _HomePageState {",
      "extension AutoTestEngine on _HomePageState {\n"
      "  /// LOGFIX: lines of the debug log written since this test started (HH:MM:SS sorted)\n"
      "  List<String> _atLogSince() {\n"
      "    final start = _startedAt == null ? '00:00:00' : _dbgHms(_startedAt!);\n"
      "    return dbgLines.where((l) => l.compareTo(start) >= 0).toList();\n"
      "  }\n")

patch('auto_test.dart',
      "    final logWin = errorLog.value.length >= _atLogStart\n        ? errorLog.value.substring(_atLogStart)\n        : errorLog.value;",
      "    final logWin = _atLogSince().join('\\n'); // LOGFIX")

# 4y) ABORTFAST: پیش‌آزمون سایت‌ها بعد از توقف سریع برگردد (قبلاً بعد از شروع هسته تا ~۳۰ ثانیه ادامه می‌داد)
patch('main.dart',
      "      if (!await _start(s, proxyOnly: true)) return null;",
      "      if (abort) return null; // ABORTFAST\n"
      "      if (!await _start(s, proxyOnly: true)) return null;\n"
      "      if (abort) {\n"
      "        await _stopCore(); // ABORTFAST\n"
      "        return null;\n"
      "      }")

# 4z) NEWRULES: پیام‌هایی که قبلاً E-GENERIC یا شکست کانفیگ اشتباه بودند، کد و راه‌حل درست بگیرند
patch('main.dart',
      "  if (has('کانفیگ ناموفق') || has('CONFIG-FAIL')) {",
      "  // NEWRULES: lines that used to be generic or wrongly counted as a config failure\n"
      "  if (has('اتصال توسط کاربر خواسته نشده بود')) {\n"
      "    return h('E-ABORT-SIDE',\n"
      "        'app_main/main.dart → _connectLoop / _start (توقف یا قطع اتصال)',\n"
      "        'اتصال وسط راه لغو شد. این شکست سرور یا کانفیگ نیست.',\n"
      "        'نادیده بگیر. اگر بدون تست و بدون قطع دستی هم دیده شد، یک کار دیگر (تست، خلبان یا دکمه) اتصال را لغو کرده است.');\n"
      "  }\n"
      "  if (m.startsWith('CFG') && m.length > 3 && '0123456789'.contains(m[3])) {\n"
      "    return h('E-CFG-DUMP', 'لاگ عیب‌یابی هسته',\n"
      "        'یک خط از متن کانفیگ هسته است؛ خودش خطا نیست.',\n"
      "        'نادیده بگیر؛ علت واقعی را در خط XRAY-ERR یا E-CONFIG-FAIL ببین.');\n"
      "  }\n"
      "  if (has('فایل خطای هسته ساخته نشد')) {\n"
      "    return h('E-XRAY-NOLOG', 'لاگ هسته (XRAY-ERR)',\n"
      "        'هسته قبل از ساختن فایل خطا بسته شد، پس دلیل شکست در فایل خطا نیست و فقط در logcat اندروید دیده می‌شود. این خطا در تقریباً همه‌ی شکست‌ها تکرار شد، پس علت اصلی است.',\n"
      "        'logcat را هنگام اتصال بگیر (فیلتر: xray یا V2RAY) و خطای اولین خط هسته را بفرست. کانفیگ را هم قبل از اجرا با jsonDecode بررسی کن تا خطای دقیق ثبت شود.');\n"
      "  }\n"
      "  if (has('V2RAY-STATE') || has('هسته: CONNECTED') || has('هسته: DISCONNECTED')) {\n"
      "    return h('E-CORE-EVENT', 'app_main/main.dart → listener onStatusChanged',\n"
      "        'رویداد عادی هسته (وصل/قطع). فقط تعداد زیاد آن در مدت کوتاه مشکل است.',\n"
      "        'اگر بیش از ۱۰ بار در ۲۰ دقیقه پرش داشتی، E-CORE-DROP را در همین گزارش ببین.');\n"
      "  }\n"
      "  if (has('جستجوی') && has('busy')) {\n"
      "    return h('E-BG-BUSY', 'app_main/main.dart → جستجوی پس‌زمینه (پرچم busy)',\n"
      "        'جستجوی پس‌زمینه پرچم busy را نگه داشته؛ کارهای دیگر را مسدود و دیتا مصرف می‌کند.',\n"
      "        'وقتی وصل هستی جستجوی پس‌زمینه را خاموش یا محدود کن (نسخه‌ی جدید هر ۱۰ دقیقه یک بار).');\n"
      "  }\n"
      "  if (has('کانفیگ ناموفق') || has('CONFIG-FAIL')) {")

# 5a) TOPACTIONS: در بالای گزارش، سه کار مهم‌تر با اولویت مشخص نشان داده شود
patch('auto_test.dart',
      "    buf.writeln('نمونه وضعیت: ${_samples.length}');",
      "    buf.writeln('نمونه وضعیت: ${_samples.length}');\n"
      "    // TOPACTIONS: the three most important findings first, each with its first action\n"
      "    const atPriority = ['ABORT-STUCK', 'TIMEOUT', 'SWITCH-FLAG-STUCK', 'SWITCH-STUCK', 'BG-BUSY',\n"
      "        'BUSY-STUCK', 'CONNECT-HANG', 'STABLE-NODATA', 'PLUGIN-SWALLOW', 'XRAY-NOLOG', 'PILOT-FLAP'];\n"
      "    int atRank(String c) {\n"
      "      final i = atPriority.indexOf(c);\n"
      "      return i < 0 ? 99 : i;\n"
      "    }\n"
      "    final ranked = [..._findings]..sort((a, b) => atRank(a.code).compareTo(atRank(b.code)));\n"
      "    if (ranked.isNotEmpty) {\n"
      "      buf.writeln('🎯 اول این‌ها را حل کن:');\n"
      "      for (final f in ranked.take(3)) {\n"
      "        buf.writeln('  • [${f.code}] ${_atHelpOf(f.code)[2]}');\n"
      "      }\n"
      "    }")

# 5b) ABORTCTX: لحظه‌ی توقف را ثبت کن تا معلوم شود کدام مرحله‌ی اپ جواب توقف را نداد
patch('auto_test.dart',
      "    abort = true;\n    try {\n      await disconnect();",
      "    // ABORTCTX: snapshot what the app was doing at the moment of the stop\n"
      "    _atAdd('ABORT-CONTEXT', 'لحظه‌ی توقف: status=\"$status\" • آخرین رویداد: $lastState • lastWhy=\"$lastWhy\"');\n"
      "    abort = true;\n    try {\n      await disconnect();")

patch('auto_test.dart',
      "      case 'CRASH':",
      "      case 'ABORT-CONTEXT':\n"
      "        return [\n"
      "          'lib/main.dart → همان مرحله‌ای که در «status» نوشته شده (مثلاً _start یا _preSocialCheck)',\n"
      "          'این مرحله وقتی توقف رسید هنوز در حال انتظار بود',\n"
      "          'در همان تابع بعد از هر await یک if (abort) return بگذار؛ اسم تابع را از status بگیر و برای من بفرست',\n"
      "        ];\n"
      "      case 'CRASH':")

# 5c) ABORTWAIT: انتظارهای داخل _start (پورت، تأیید هسته) با توقف زودتر تمام شوند
patch('main.dart',
      "    await Future.delayed(const Duration(milliseconds: 1500));\n    try {\n      final nv = natVarFor(s);",
      "    await Future.delayed(const Duration(milliseconds: 1500));\n    if (abort) return false; // ABORTWAIT\n    try {\n      final nv = natVarFor(s);")

patch('main.dart',
      "        if (!await waitProxyPort(max: const Duration(seconds: 8))) {",
      "        if (abort || !await waitProxyPort(max: const Duration(seconds: 8))) { // ABORTWAIT")

patch('main.dart',
      "        ready = await waitSig.future.timeout(connWait, onTimeout: () {",
      "        // ABORTWAIT: a stop request completes the wait at once instead of after connWait\n"
      "        final abortPoll = Timer.periodic(const Duration(milliseconds: 300), (tm) {\n"
      "          if ((abort || myGen != _connGen) && !waitSig.isCompleted) {\n"
      "            waitSig.complete(false);\n"
      "            tm.cancel();\n"
      "          }\n"
      "        });\n"
      "        ready = await waitSig.future.timeout(connWait, onTimeout: () {")

patch('main.dart',
      "        if (myGen != _connGen) ready = false; // superseded",
      "        abortPoll.cancel(); // ABORTWAIT\n        if (myGen != _connGen) ready = false; // superseded")

# 5) write the new part file
with open(os.path.join(LIB, 'nip_scan.dart'), 'w', encoding='utf-8') as f:
    f.write(NIP_FILE)
print('OK: nip_scan.dart written')
print('ALL PATCHES APPLIED')
