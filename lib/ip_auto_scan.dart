part of 'main.dart';

// IPAUTO: اسکن خودکار IP با هسته‌ی VPN، کاملاً جدا از نت ملی.
// - فقط وقتی VPN قطع است و جستجوی نت ملی یا اسکن DNS در حال اجرا نیست، شروع می‌شود.
// - هیچ صف، حافظه یا بازه‌ی نت ملی را تغییر نمی‌دهد (natRanges، natIpMem، pending، good).
//   فقط برای خواندن، سرور نمونه و پورت‌های پرتکرار را از آن‌ها می‌گیرد.
// - هر IP اول با TCP سنجیده می‌شود؛ فقط پورت‌های باز با هسته‌ی VPN دو بار تست می‌شوند.
// - نتیجه بر اساس حالت فعلی (ملی یا جهانی) در فهرست جدا ذخیره می‌شود و کپی‌پذیر است.
// - هر اجرا بخش بعدیِ آدرس‌ها را برمی‌دارد (کرسر خودش)، پس با اجراهای متوالی بلوک‌ها پوشش داده می‌شوند.

const String _ipAutoKeyNat = 'ipauto_nat_v1';
const String _ipAutoKeyGlob = 'ipauto_glob_v1';
const String _ipAutoCursorKey = 'ipauto_cursor_v1';
const String _ipAutoPosKey = 'ipauto_pos_v1'; // جای فعلی در فهرست آدرس‌ها
const int _ipAutoBatch = 6000; // آدرس در هر اجرا
const int _ipAutoMaxHits = 1000; // سقف نتایج ذخیره‌شده
const int _ipAutoPorts = 5; // بیشترین پورت برای TCP
const String _ipAutoAtKey = 'ipauto_at_v1'; // زمان آخرین اسکن خودکار نت ملی
const int _ipAutoConc = 48; // اتصال TCP همزمان
const int _ipAutoCoreMax = 200; // سقف تست هسته در هر اجرا

bool ipAutoBusy = false;
bool ipAutoStopFlag = false;
String ipAutoStatus = '';
final List<String> ipAutoHits = []; // به شکل «ip|port»
final Map<String, int> ipAutoCursors = {};
int ipAutoPos = 0;

String _ipAutoKeyNow() => nationalMode ? _ipAutoKeyNat : _ipAutoKeyGlob;
// IPAUTO-MODE: کرسر و جای فعلی هم برای هر حالت جدا هستند (فهرست بلوک‌ها در دو حالت فرق دارد)
String _ipAutoPosKeyNow() => '${_ipAutoPosKey}_${nationalMode ? 'nat' : 'glob'}';
String _ipAutoCursorKeyNow() => '${_ipAutoCursorKey}_${nationalMode ? 'nat' : 'glob'}';
// حالتی که فهرست IP در حافظه متعلق به آن است (null = هنوز بارگذاری نشده)
bool? _ipAutoLoadedNat;
String _ipAutoModeName() => nationalMode ? 'نت ملی' : 'جهانی';

Future<void> ipAutoLoad() async {
  try {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_ipAutoKeyNow()) ?? '';
    ipAutoHits
      ..clear()
      ..addAll(s.split('\n').where((x) => x.contains('|')));
    _ipAutoLoadedNat = nationalMode;
    ipAutoPos = int.tryParse(p.getString(_ipAutoPosKeyNow()) ?? '') ?? 0;
    final c = p.getString(_ipAutoCursorKeyNow());
    if (c != null && c.isNotEmpty) {
      final m = jsonDecode(c) as Map;
      ipAutoCursors
        ..clear()
        ..addAll({for (final e in m.entries) '${e.key}': (e.value as num).toInt()});
    }
  } catch (e, stk) {
    logError(e, stk);
  }
}

Future<void> _ipAutoSave() async {
  try {
    // IPAUTO-MODE: اگر حالت وسط کار عوض شده، فهرست حافظه مال حالت دیگری است؛ ذخیره نمی‌کنیم
    // تا نتایج یک حالت در کلید حالت دیگر نریزد.
    if (_ipAutoLoadedNat != null && _ipAutoLoadedNat != nationalMode) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(_ipAutoKeyNow(), ipAutoHits.join('\n'));
    await p.setString(_ipAutoCursorKeyNow(), jsonEncode(ipAutoCursors));
    await p.setString(_ipAutoPosKeyNow(), ipAutoPos.toString());
  } catch (e, stk) {
    logError(e, stk);
  }
}

/// خودکار فقط IPهای دقیقِ کانفیگ‌های موجود و سرورهای قبلاً موفق را بررسی می‌کند.
/// پیمایش گسترده‌ی CIDRهای ISP/CDN برای اجرای خودکار مجاز نیست؛ اسکن دستی جداست.
List<String> _ipAutoBlocks(Iterable<Server> knownServers) {
  // Hard isolation: national candidates come only from the national scanner's
  // verified memory/hits. Global candidates come only from the active global pool.
  final ips = <String>{};
  if (nationalMode) {
    ips
      ..addAll(natIpMemHosts())
      ..addAll(natScanHits);
  } else {
    for (final server in knownServers) {
      if (server.isIp) ips.add(server.host);
    }
  }
  return ips.map((ip) => '$ip/32').toList(growable: false);
}

Future<List<String>> _ipAutoNextAddrs(Iterable<Server> knownServers) async {
  final args = <String, dynamic>{
    'cfIpsBatch': 0, // exact known endpoints only; no broad public CIDR scan
    'blocks': _ipAutoBlocks(knownServers),
    'nationalMode': nationalMode,
    'liveRanges': <String>[],
    'cursors': Map<String, int>.of(ipAutoCursors),
  };
  final gen = await compute(_genAddrsIso, args);
  final all = (gen['addrs'] as List).cast<String>();
  ipAutoCursors
    ..clear()
    ..addAll(Map<String, int>.from(gen['cursors'] as Map));
  if (all.isEmpty) return const <String>[];
  // فقط یک تکه‌ی _ipAutoBatch تایی در هر اجرا؛ جای فعلی ذخیره می‌شود تا اجرای بعدی ادامه دهد
  final start = ipAutoPos % all.length;
  final slice = all.skip(start).take(_ipAutoBatch).toList();
  ipAutoPos = start + slice.length;
  return slice;
}

extension IpAutoExt on _HomePageState {
  /// آیا اسکن باید همین الان متوقف شود (VPN وصل شد، یا برنامه مشغول اتصال است، یا کاربر توقف زد)
  bool _ipAutoHalt() => ipAutoStopFlag || connected || busy;

  /// نت ملی: اسکن IP خودکار بدون دکمه (هر ۲۴ ساعت، یا ۶ ساعت اگر نتیجه نداشت)، فقط وقتی VPN قطع است.
  /// نتایج در فهرست نت ملی ذخیره می‌شوند و هیچ صف یا بازه‌ی دیگری را تغییر نمی‌دهد.
  Future<void> ipAutoBackground() async {
    try {
      if (!kNatIpScanOn) return; // shared master switch applies to every IP scanner
      if (!nationalMode) return;
      if (ipAutoBusy || dnsxManualBusy || _natRangeScanBusy || _dnsxAutoBusy) return;
      if (connected || busy) return;
      await ipAutoLoad();
      final p = await SharedPreferences.getInstance();
      final last = int.tryParse(p.getString(_ipAutoAtKey) ?? '') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      // اگر هنوز IP سالمی پیدا نشده، زودتر دوباره امتحان می‌شود (۶ ساعت)؛ وگرنه هر ۲۴ ساعت
      final gapMs = ipAutoHits.isEmpty ? 6 * 3600 * 1000 : 24 * 3600 * 1000;
      if (now - last < gapMs) return;
      ipAutoBusy = true;
      dnsxManualBusy = true;
      ipAutoStopFlag = false;
      try {
        await _ipAutoRunOnce((s) => ipAutoStatus = s);
        // فقط اسکن کامل ذخیره می‌شود؛ اگر وسط کار متوقف شد، دفعه‌ی بعد دوباره امتحان می‌شود
        if (!_ipAutoHalt()) {
          await p.setString(_ipAutoAtKey, now.toString());
        }
      } catch (e, stk) {
        logError(e, stk);
      } finally {
        ipAutoBusy = false;
        dnsxManualBusy = false;
        await _ipAutoSave();
      }
    } catch (e, stk) {
      logError(e, stk);
    }
  }

  /// دلیل رد شدن شروع اسکن؛ null یعنی می‌شود شروع کرد
  String? _ipAutoRefusal() {
    // نت ملی کاملاً خودکار است؛ دکمه‌ی دستی فقط برای حالت عادی است
    if (!kNatIpScanOn) return 'اسکن IP از تنظیم اصلی خاموش است.';
    if (ipAutoBusy) return 'اسکن در حال اجراست.';
    if (connected || busy) return 'اول VPN را قطع کنید، بعد اسکن خودکار IP را اجرا کنید.';
    if (nationalMode && _natRangeScanBusy) {
      return 'جستجوی نت ملی در حال اجراست؛ کمی صبر کنید.';
    }
    if (nationalMode && _dnsxAutoBusy) {
      return 'اسکن DNS پس‌زمینه در حال اجراست؛ کمی صبر کنید.';
    }
    return null;
  }

  /// یک تست کامل هسته برای یک سرور (با IP جایگزین)؛ همان مسیر تست‌های موجود، با همان گیت
  Future<bool> _ipAutoCoreOk(Server s, String url) async {
    try {
      final rr = await _delayGate.run<dynamic>(() async {
        return await v2ray
            .getServerDelay(config: _testCfg(natCfg(s, 0)), url: url)
            .timeout(const Duration(seconds: 8), onTimeout: () => -1);
      });
      final r = rr is int ? rr : (int.tryParse('$rr') ?? -1);
      return r > 0;
    } catch (e, stk) {
      logError(e, stk);
      return false;
    }
  }

  Future<void> _ipAutoRunOnce(void Function(String) say, {bool manual = false}) async {
    // A national scan uses the national hot-source/template pipeline; it must
    // not fetch or fall back to the global discovered-server pool.
    var pool = <Server>[];
    if (nationalMode) {
      say('دریافت الگوهای مستقل نت ملی...');
      try {
        final nationalSeeds = await natHotNext(50, fetch: false);
        if (nationalSeeds.isNotEmpty) {
          natTemplateSeeds = nationalSeeds.take(2).toList();
          pool = [...nationalSeeds, ...good, ...pending];
        } else {
          pool = <Server>[...natTemplateSeeds, ...good, ...pending];
        }
      } catch (e, stk) {
        logError(e, stk);
        pool = <Server>[...natTemplateSeeds, ...good, ...pending];
      }
    } else {
      say('دریافت سرور نمونه از منابع جهانی...');
      try {
        pool = await fetchServers(stop: () => _ipAutoHalt(), quickCap: 200);
      } catch (e, stk) {
        logError(e, stk);
        pool = <Server>[];
      }
      if (pool.isEmpty) pool = <Server>[...good, ...pending, ...fetchedAll];
    }
    if (pool.isEmpty) {
      say('دریافت لیست سرورها ناموفق بود. اینترنت را بررسی کنید و دوباره اجرا کنید.');
      return;
    }
    final tpl = pool.take(2).toList();
    say('ساخت آدرس‌ها...');
    final addrs = await _ipAutoNextAddrs(
        nationalMode ? const <Server>[] : [...good, ...pending, ...fetchedAll]);
    if (addrs.isEmpty) {
      say('آدرسی برای اسکن پیدا نشد.');
      return;
    }
    final ports = natAutoPorts(pool).take(_ipAutoPorts).toList();
    if (ports.isEmpty) ports.add(443);

    // مرحله‌ی ۱: TCP روی همه‌ی آدرس‌ها
    final candidates = <String>[];
    for (final port in ports) {
      if (_ipAutoHalt()) break;
      say('بررسی TCP روی پورت $port (${addrs.length} آدرس)...');
      final hits = await natScanIps(
        addrs,
        port: port,
        concurrency: (manual && nationalMode) ? kNatManualConc : _ipAutoConc,
        want: 300,
        budget: const Duration(minutes: 5),
        timeout: const Duration(milliseconds: 1500),
        cancelled: () => _ipAutoHalt(),
      );
      for (final h in hits) {
        candidates.add('${h.ip}|$port');
      }
    }

    // مرحله‌ی ۲: تست واقعی با هسته‌ی VPN، دو بار پشت سر هم
    final url = nationalMode ? _natTestUrls.first : delayTestUrl;
    final seen = ipAutoHits.toSet();
    final tplSrv = tpl.first;
    var found = 0;
    var checked = 0;
    // سقف تست هسته در هر اجرا، تا زمان اجرا از حد نگذرد (بقیه در اجرای بعدی از آدرس‌های تازه می‌آیند)
    final toTest = candidates.take(_ipAutoCoreMax).toList();
    say('${candidates.length} پورت باز (تست ${toTest.length} تای اول)؛ تست با هسته‌ی VPN...');
    for (final c in toTest) {
      if (_ipAutoHalt()) break;
      checked++;
      if (seen.contains(c)) continue;
      final parts = c.split('|');
      final ip = parts[0];
      final port = int.tryParse(parts[1]) ?? 443;
      final ipLink = _natSetPort(_natSetHost(tplSrv.link, ip, tplSrv.host), port);
      final s = Server(ipLink, tplSrv.name, ip, port);
      if (!await _ipAutoCoreOk(s, url)) {
        say('تست $checked/${toTest.length} • جواب‌داده: $found');
        continue;
      }
      if (!await _ipAutoCoreOk(s, url)) {
        say('تست $checked/${toTest.length} • جواب‌داده: $found');
        continue;
      }
      ipAutoHits.insert(0, c);
      // Core outbound delay is not proof of a clean IP or Android TUN health.
      // Keep it as a candidate only; promotion requires a real user tunnel test.
      seen.add(c);
      found++;
      if (ipAutoHits.length > _ipAutoMaxHits) {
        ipAutoHits.removeRange(_ipAutoMaxHits, ipAutoHits.length);
      }
      say('تست $checked/${toTest.length} • جواب‌داده: $found');
    }
    say(ipAutoStopFlag
        ? 'متوقف شد. $found IP جدید در حالت ${_ipAutoModeName()}.'
        : 'تمام شد: $found IP جدید در حالت ${_ipAutoModeName()}.');
  }

  Future<void> ipAutoSheet(BuildContext ctx0) async {
    await ipAutoLoad();
    ipAutoStopFlag = false;
    if (!ctx0.mounted) return;
    showModalBottomSheet(
      context: ctx0,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          void upd(VoidCallback f) {
            try {
              setS(f);
            } catch (e) {
              errJournalAdd(e, kind: 'SILENT-SHEET');
            }
          }

          Future<void> start() async {
            final why = _ipAutoRefusal();
            if (why != null) {
              ScaffoldMessenger.maybeOf(ctx0)?.showSnackBar(SnackBar(content: Text(why)));
              return;
            }
            ipAutoBusy = true;
            // تا این اسکن تمام نشده، اسکن DNS پس‌زمینه هم شروع نمی‌شود (جدا و بدون تداخل)
            dnsxManualBusy = true;
            ipAutoStopFlag = false;
            upd(() => ipAutoStatus = 'شروع...');
            try {
              await _ipAutoRunOnce((s) => upd(() => ipAutoStatus = s), manual: true);
            } catch (e, stk) {
              logError(e, stk);
              upd(() => ipAutoStatus = 'خطا: $e');
            } finally {
              ipAutoBusy = false;
              dnsxManualBusy = false;
              await _ipAutoSave();
              upd(() {});
            }
          }

          final running = ipAutoBusy;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('اسکن خودکار IP',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text('حالت فعلی: ${_ipAutoModeName()}  •  نتایج این حالت جدا ذخیره می‌شوند.'),
                  const SizedBox(height: 4),
                  const Text(
                      'اسکن خودکار است: لازم نیست بازه‌ای وارد کنید. فقط وقتی VPN قطع باشد اجرا می‌شود. '
                      'هر IP که با هسته‌ی VPN جواب بدهد در فهرست می‌آید.'),
                  const SizedBox(height: 8),
                  Text(ipAutoStatus.isEmpty ? 'آماده' : ipAutoStatus),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: running ? null : () => start(),
                        child: const Text('شروع اسکن خودکار'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: running
                            ? () => upd(() {
                                  ipAutoStopFlag = true;
                                })
                            : null,
                        child: const Text('توقف'),
                      ),
                    ),
                  ]),
                  const Divider(height: 20),
                  if (ipAutoHits.isNotEmpty)
                    OutlinedButton(
                      onPressed: () async {
                        final txt = ipAutoHits.map((x) => x.replaceAll('|', ':')).join('\n');
                        await Clipboard.setData(ClipboardData(text: txt));
                        ScaffoldMessenger.maybeOf(ctx0)?.showSnackBar(SnackBar(
                            content: Text('${ipAutoHits.length} IP کپی شد')));
                      },
                      child: Text('کپی همه‌ی ${ipAutoHits.length} IP (${_ipAutoModeName()})'),
                    ),
                  if (ipAutoHits.isEmpty)
                    Text('هنوز endpoint پاسخ‌گوی هسته برای حالت ${_ipAutoModeName()} پیدا نشده است.'),
                  for (final h in ipAutoHits)
                    ListTile(
                      dense: true,
                      title: Text(h.replaceAll('|', ':')),
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: h.replaceAll('|', ':')));
                        ScaffoldMessenger.maybeOf(ctx0)?.showSnackBar(SnackBar(
                            content: Text('${h.replaceAll('|', ':')} کپی شد')));
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      // بستن شیت فقط اسکن دستی (حالت عادی) را متوقف می‌کند؛ اسکن خودکار نت ملی دست‌نخورده می‌ماند
      if (!nationalMode) ipAutoStopFlag = true;
    });
  }
}
