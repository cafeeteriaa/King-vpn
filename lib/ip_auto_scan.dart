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
const int _ipAutoBatch = 6000; // per-run work batch; per-block cursors cover the full inventory
const String _ipAutoAtKey = 'ipauto_at_v1'; // legacy National Net timestamp
const int _ipAutoConc = 48; // TCP fan-out ceiling

bool ipAutoBusy = false;
bool ipAutoStopFlag = false;
String ipAutoStatus = '';
final List<String> ipAutoHits = []; // به شکل «ip|port»
final Map<String, int> ipAutoCursors = {};

String _ipAutoKeyNow() => nationalMode ? _ipAutoKeyNat : _ipAutoKeyGlob;
String _ipAutoCursorKeyNow() => '${_ipAutoCursorKey}_${nationalMode ? 'nat' : 'glob'}';
String _ipAutoAtKeyForMode(bool national) =>
    '${_ipAutoAtKey}_${national ? 'nat' : 'glob'}';
// حالتی که فهرست IP در حافظه متعلق به آن است (null = هنوز بارگذاری نشده)
bool? _ipAutoLoadedNat;
String _ipAutoModeName() => nationalMode ? 'نت ملی' : 'جهانی';

Future<void> ipAutoLoad() async {
  // Capture the mode and its storage keys before the first await.
  final loadNationalMode = nationalMode;
  final hitsKey = loadNationalMode ? _ipAutoKeyNat : _ipAutoKeyGlob;
  final cursorKey = '${_ipAutoCursorKey}_${loadNationalMode ? 'nat' : 'glob'}';
  try {
    final p = await SharedPreferences.getInstance();
    if (nationalMode != loadNationalMode) return;
    final savedHits = p.getString(hitsKey) ?? '';
    final loadedCursors = <String, int>{};
    final encoded = p.getString(cursorKey);
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.value is num) {
              loadedCursors['${entry.key}'] = (entry.value as num).toInt();
            }
          }
        }
      } catch (error, stackTrace) {
        logError(error, stackTrace);
      }
    }
    if (nationalMode != loadNationalMode) return;
    ipAutoHits
      ..clear()
      ..addAll(savedHits.split('\n').where((value) => value.contains('|')));
    ipAutoCursors
      ..clear()
      ..addAll(loadedCursors);
    _ipAutoLoadedNat = loadNationalMode;
  } catch (error, stackTrace) {
    logError(error, stackTrace);
  }
}

Future<void> _ipAutoSave() async {
  final saveNationalMode = nationalMode;
  if (_ipAutoLoadedNat != null && _ipAutoLoadedNat != saveNationalMode) return;
  final hits = List<String>.of(ipAutoHits);
  final cursors = Map<String, int>.of(ipAutoCursors);
  final hitsKey = saveNationalMode ? _ipAutoKeyNat : _ipAutoKeyGlob;
  final cursorKey = '${_ipAutoCursorKey}_${saveNationalMode ? 'nat' : 'glob'}';
  try {
    final p = await SharedPreferences.getInstance();
    if (nationalMode != saveNationalMode ||
        (_ipAutoLoadedNat != null && _ipAutoLoadedNat != saveNationalMode)) {
      return;
    }
    await p.setString(hitsKey, hits.join('\n'));
    await p.setString(cursorKey, jsonEncode(cursors));
  } catch (error, stackTrace) {
    logError(error, stackTrace);
  }
}

/// Build an exact endpoint inventory from saved candidates and the freshly
/// fetched independent source templates. Hostnames resolve only to their
/// returned A/AAAA addresses; no neighboring subnet is synthesized.
Future<List<String>> _ipAutoBlocks(
  Iterable<Server> sourceServers, {
  required bool modeSnapshot,
  bool Function()? shouldAbort,
}) async {
  final ips = <String>{};
  if (modeSnapshot) {
    ips
      ..addAll(natNationalIpMemHosts())
      ..addAll(natScanHits)
      ..addAll(natRelayHosts);
  } else {
    ips
      ..addAll(natIpMemHosts())
      ..addAll(_goldIps.keys);
  }

  for (final server in sourceServers) {
    if (shouldAbort?.call() ?? false) break;
    final host = server.host.trim();
    if (host.isEmpty) continue;
    final literal = InternetAddress.tryParse(host);
    if (literal != null) {
      ips.add(literal.address);
      continue;
    }
    try {
      ips.addAll(await nipResolveAll(host));
    } catch (error, stackTrace) {
      logError(error, stackTrace);
    }
  }
  return natSeedBlocks(ips.toList(growable: false));
}

Future<List<String>> _ipAutoNextAddrs(
  Iterable<Server> sourceServers, {
  bool Function()? shouldAbort,
}) async {
  // Cursors belong to each exact /32 or /128 block. Generate exactly the
  // returned work batch; never advance cursors past discarded addresses.
  final modeSnapshot = nationalMode;
  final cursorSnapshot = Map<String, int>.of(ipAutoCursors);
  final blocks = await _ipAutoBlocks(
    sourceServers,
    modeSnapshot: modeSnapshot,
    shouldAbort: shouldAbort,
  );
  if (nationalMode != modeSnapshot || (shouldAbort?.call() ?? false)) {
    return const <String>[];
  }
  final generated = await compute(_genAddrsIso, <String, dynamic>{
    'cfIpsBatch': 0,
    'addressBatchSize': _ipAutoBatch,
    'blocks': blocks,
    'nationalMode': modeSnapshot,
    'liveRanges': <String>[],
    'cursors': cursorSnapshot,
  });
  if (nationalMode != modeSnapshot || (shouldAbort?.call() ?? false)) {
    return const <String>[];
  }
  final addresses = (generated['addrs'] as List).cast<String>();
  final nextCursors = <String, int>{
    for (final entry in (generated['cursors'] as Map).entries)
      entry.key.toString(): int.tryParse(entry.value.toString()) ?? 0,
  };
  if (addresses.isNotEmpty) {
    ipAutoCursors
      ..clear()
      ..addAll(nextCursors);
  }
  return List<String>.unmodifiable(addresses);
}

extension IpAutoExt on _HomePageState {
  /// آیا اسکن باید همین الان متوقف شود (VPN وصل شد، یا برنامه مشغول اتصال است، یا کاربر توقف زد)
  bool _ipAutoHalt({bool? modeSnapshot}) =>
      ipAutoStopFlag || connected || busy ||
      (modeSnapshot != null && nationalMode != modeSnapshot);

  /// نت ملی: اسکن IP خودکار بدون دکمه (هر ۲۴ ساعت، یا ۶ ساعت اگر نتیجه نداشت)، فقط وقتی VPN قطع است.
  /// نتایج در فهرست نت ملی ذخیره می‌شوند و هیچ صف یا بازه‌ی دیگری را تغییر نمی‌دهد.
  Future<void> ipAutoBackground({bool Function()? stop}) async {
    final runNationalMode = nationalMode;
    if (!kNatIpScanOn) return;
    bool externallyStopped() => !mounted || (stop?.call() ?? false);
    if (externallyStopped()) return;
    if (ipAutoBusy || dnsxManualBusy || _natRangeScanBusy || _dnsxAutoBusy) return;
    if (connected || busy) return;

    // Acquire both shared scan locks before the first await. Otherwise a manual
    // DNS/IP scan can start while preferences are loading and overlap this run.
    ipAutoBusy = true;
    dnsxManualBusy = true;
    ipAutoStopFlag = false;
    try {
      await ipAutoLoad();
      if (_ipAutoHalt(modeSnapshot: runNationalMode)) return;

      final p = await SharedPreferences.getInstance();
      if (_ipAutoHalt(modeSnapshot: runNationalMode)) return;

      final atKey = _ipAutoAtKeyForMode(runNationalMode);
      var last = int.tryParse(p.getString(atKey) ?? '') ?? 0;
      // Migrate the old shared timestamp to National Net only. Global scanning
      // receives an independent cadence and cannot inherit that old delay.
      if (runNationalMode && last == 0) {
        last = int.tryParse(p.getString(_ipAutoAtKey) ?? '') ?? 0;
        if (last > 0) await p.setString(atKey, last.toString());
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      // اگر هنوز IP سالمی پیدا نشده، زودتر دوباره امتحان می‌شود (۶ ساعت)؛ وگرنه هر ۲۴ ساعت
      final gapMs = ipAutoHits.isEmpty ? 6 * 3600 * 1000 : 24 * 3600 * 1000;
      if (now - last < gapMs) return;

      final completed = await _ipAutoRunOnce(
        (s) => ipAutoStatus = s,
        shouldAbort: externallyStopped,
      );
      // Failed, cancelled, or mode-switched scans must not consume the retry interval.
      if (completed &&
          !_ipAutoHalt(modeSnapshot: runNationalMode) &&
          !externallyStopped()) {
        await p.setString(atKey, now.toString());
      }
    } catch (e, stk) {
      logError(e, stk);
    } finally {
      // Persist while the locks are still held so another scan cannot mutate
      // the shared result lists before their snapshot is taken.
      await _ipAutoSave();
      ipAutoBusy = false;
      dnsxManualBusy = false;
    }
  }

  /// دلیل رد شدن شروع اسکن؛ null یعنی می‌شود شروع کرد
  String? _ipAutoRefusal() {
    // نت ملی کاملاً خودکار است؛ دکمه‌ی دستی فقط برای حالت عادی است
    if (!kNatIpScanOn) return 'اسکن IP از تنظیم اصلی خاموش است.';
    if (ipAutoBusy || dnsxManualBusy) return 'اسکن دیگری در حال اجراست.';
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

  Future<bool> _ipAutoRunOnce(
    void Function(String) say, {
    bool manual = false,
    bool Function()? shouldAbort,
  }) async {
    final runNationalMode = nationalMode;
    bool halted() =>
        _ipAutoHalt(modeSnapshot: runNationalMode) ||
        (shouldAbort?.call() ?? false);
    if (halted()) return false;
    if (runNationalMode) {
      await natNationalIpMemLoad();
      await natRelayHostsLoad();
    } else {
      await natIpMemLoad();
      await goldLoad();
    }
    if (halted()) return false;

    // A national scan uses the national hot-source/template pipeline; it must
    // not fetch or fall back to the global discovered-server pool.
    var pool = <Server>[];
    if (runNationalMode) {
      say('دریافت الگوهای مستقل نت ملی...');
      try {
        final nationalSeeds = await natHotAll(fetch: false);
        if (halted()) return false;
        if (nationalSeeds.isNotEmpty) {
          natNationalTemplateSeeds = [
            ...natNationalTemplateSeeds,
            ...nationalSeeds,
          ];
          pool = [...natNationalTemplateSeeds];
        } else {
          pool = <Server>[...natNationalTemplateSeeds];
        }
      } catch (e, stk) {
        logError(e, stk);
        if (halted()) return false;
        pool = <Server>[...natNationalTemplateSeeds];
      }
    } else {
      say('دریافت سرور نمونه از منابع جهانی...');
      try {
        pool = await fetchServers(stop: () => halted());
      } catch (e, stk) {
        logError(e, stk);
        if (halted()) return false;
        pool = <Server>[];
      }
      if (halted()) return false;
      if (pool.isEmpty) pool = <Server>[...good, ...pending, ...fetchedAll];
    }
    if (halted()) return false;
    if (pool.isEmpty) {
      say('دریافت لیست سرورها ناموفق بود. اینترنت را بررسی کنید و دوباره اجرا کنید.');
      return false;
    }
    final tpl = <Server>[];
    final templateKeys = <String>{};
    for (final server in pool) {
      // Same host:port with different credentials/protocols is not a duplicate
      // template; every distinct config must get a chance to validate the IP.
      if (templateKeys.add(server.link.trim())) tpl.add(server);
    }
    say('ساخت آدرس‌ها...');
    final addrs = await _ipAutoNextAddrs(
      tpl,
      shouldAbort: halted,
    );
    if (halted()) return false;
    if (addrs.isEmpty) {
      say('آدرسی برای اسکن پیدا نشد.');
      return false;
    }
    final ports = natAutoPorts(pool).toSet().toList()..sort();
    if (ports.isEmpty) ports.add(443);

    // مرحله‌ی ۱: TCP روی همه‌ی آدرس‌ها
    final reachableEndpoints = <String>[];
    for (final port in ports) {
      if (halted()) break;
      say('بررسی TCP روی پورت $port (${addrs.length} آدرس)...');
      final hits = await natScanIps(
        addrs,
        port: port,
        concurrency: (manual && runNationalMode) ? kNatManualConc : _ipAutoConc,
        timeout: const Duration(milliseconds: 1500),
        cancelled: halted,
      );
      if (halted()) return false;
      for (final h in hits) {
        reachableEndpoints.add('${h.ip}|$port');
      }
    }

    // مرحله‌ی ۲: همه‌ی endpointهای پاسخ‌گو با همه‌ی قالب‌های موجود تست می‌شوند.
    // هر endpoint تا یافتن یک قالب سالم بررسی می‌شود؛ هیچ سقف hit یا تعداد تست وجود ندارد.
    final url = runNationalMode ? _natTestUrls.first : delayTestUrl;
    final seen = ipAutoHits.toSet();
    var found = 0;
    var checked = 0;
    say('${reachableEndpoints.length} پورت پاسخ‌گو؛ تست کامل با هسته‌ی VPN و همه‌ی قالب‌ها...');
    for (final endpoint in reachableEndpoints) {
      if (halted()) break;
      checked++;
      if (seen.contains(endpoint)) continue;
      final parts = endpoint.split('|');
      final ip = parts[0];
      final port = int.tryParse(parts[1]) ?? 443;
      var verified = false;
      for (final template in tpl) {
        if (halted()) return false;
        final ipLink = _natSetPort(
          _natSetHost(template.link, ip, template.host),
          port,
        );
        final server = Server(ipLink, template.name, ip, port);
        final firstOk = await _ipAutoCoreOk(server, url);
        if (halted()) return false;
        if (!firstOk) continue;
        final secondOk = await _ipAutoCoreOk(server, url);
        if (halted()) return false;
        if (secondOk) {
          verified = true;
          break;
        }
      }
      if (verified) {
        ipAutoHits.insert(0, endpoint);
        seen.add(endpoint);
        found++;
      }
      say('تست $checked/${reachableEndpoints.length} • جواب‌داده: $found');
    }
    if (halted()) {
      say('متوقف شد؛ نتایج این اجرا کامل نیستند.');
      return false;
    }
    say('تمام شد: $found IP جدید در حالت ${runNationalMode ? 'نت ملی' : 'جهانی'}.');
    return true;
  }

  Future<void> ipAutoSheet(BuildContext ctx0) async {
    var sheetScanRunning = false;
    await ipAutoLoad();
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
            final runNationalMode = nationalMode;
            ipAutoBusy = true;
            sheetScanRunning = true;
            // تا این اسکن تمام نشده، اسکن DNS پس‌زمینه هم شروع نمی‌شود (جدا و بدون تداخل)
            dnsxManualBusy = true;
            ipAutoStopFlag = false;
            upd(() => ipAutoStatus = 'شروع...');
            try {
              // The sheet may have stayed open while the user changed network mode.
              await ipAutoLoad();
              if (_ipAutoHalt(modeSnapshot: runNationalMode)) {
                upd(() => ipAutoStatus = 'حالت شبکه تغییر کرد یا اسکن متوقف شد؛ دوباره شروع کن.');
                return;
              }
              await _ipAutoRunOnce((s) => upd(() => ipAutoStatus = s), manual: true);
            } catch (e, stk) {
              logError(e, stk);
              upd(() => ipAutoStatus = 'خطا: $e');
            } finally {
              sheetScanRunning = false;
              // Keep the lock until the snapshot is persisted.
              await _ipAutoSave();
              ipAutoBusy = false;
              dnsxManualBusy = false;
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
                        if (!ctx0.mounted) return;
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
                        if (!ctx0.mounted) return;
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
      // Stop only the manual scan launched by this sheet; never cancel a background run.
      if (sheetScanRunning) ipAutoStopFlag = true;
    });
  }
}
