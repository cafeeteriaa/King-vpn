part of 'main.dart';

// IPAUTO: اسکن خودکار IP با هسته‌ی VPN، کاملاً جدا از نت ملی.
// - فقط وقتی VPN قطع است و جستجوی نت ملی یا اسکن DNS در حال اجرا نیست، شروع می‌شود.
// - هیچ صف، حافظه یا بازه‌ی نت ملی را تغییر نمی‌دهد (natRanges، natIpMem، pending، good).
// - موجودی نامزدهای IP را مستقل از کانفیگ‌ها از DNS دوپشته، پوشه‌ی جهانی و رنج‌های CDN می‌سازد.
// - تست فعال TCP و هسته فقط روی جفت IP:port دقیقِ endpointهای VPN موجود انجام می‌شود.
// - نامزدهای کشف‌شده با endpoint پاسخ‌گو یا مسیر تونل تأییدشده اشتباه گرفته نمی‌شوند.
// - نتیجه بر اساس حالت فعلی (ملی یا جهانی) در فهرست جدا ذخیره می‌شود و کپی‌پذیر است.
// - هر اجرا بخش بعدیِ آدرس‌ها را برمی‌دارد (کرسر خودش)، پس با اجراهای متوالی بلوک‌ها پوشش داده می‌شوند.

const String _ipAutoKeyNat = 'ipauto_nat_v1';
const String _ipAutoKeyGlob = 'ipauto_glob_v1';
const String _ipAutoCursorKey = 'ipauto_cursor_v1';
const String _ipAutoPosKey = 'ipauto_pos_v1'; // جای فعلی در فهرست آدرس‌ها
const String _ipAutoPendingKey = 'ipauto_pending_core_v1';
int get _ipAutoBatch => max(1, Platform.numberOfProcessors * 4096); // resumable device-sized work slice
// TCP scanning uses every discovered/configured port; no fixed port-count cap.
const String _ipAutoAtKey = 'ipauto_at_v1'; // زمان آخرین اسکن خودکار نت ملی
int get _ipAutoConc => natAdaptiveConcurrency(0); // hardware-aware concurrent probes

bool ipAutoBusy = false;
bool ipAutoStopFlag = false;
String ipAutoStatus = '';
final List<String> ipAutoHits = []; // به شکل «ip|port»
final List<String> ipAutoPendingCore = []; // TCP hits awaiting two-pass VPN-core verification
final Map<String, dynamic> ipAutoCursors = {};
int ipAutoPos = 0;

String _ipAutoKeyNow() => nationalMode ? _ipAutoKeyNat : _ipAutoKeyGlob;
// IPAUTO-MODE: کرسر و جای فعلی هم برای هر حالت جدا هستند (فهرست بلوک‌ها در دو حالت فرق دارد)
String _ipAutoPosKeyNow() => '${_ipAutoPosKey}_${nationalMode ? 'nat' : 'glob'}';
String _ipAutoCursorKeyNow() => '${_ipAutoCursorKey}_${nationalMode ? 'nat' : 'glob'}';
// حالتی که فهرست IP در حافظه متعلق به آن است (null = هنوز بارگذاری نشده)
bool? _ipAutoLoadedNat;
String _ipAutoModeName() => nationalMode ? 'نت ملی' : 'جهانی';

typedef IpAutoSnapshot = ({
  List<String> hits,
  List<String> pending,
  Map<String, dynamic> cursors,
  int position,
});

/// Versioned, single-value snapshot for one IP Auto mode. A valid snapshot is
/// authoritative; legacy keys are read only for migration when v2 is absent
/// or corrupt. Results, retry backlog and cursors share one commit edge.
String ipAutoEncodeSnapshot({
  required Iterable<String> hits,
  required Iterable<String> pending,
  required Map<String, dynamic> cursors,
  required int position,
}) => jsonEncode({
  'version': 2,
  'hits': hits.toList(growable: false),
  'pending': pending.toList(growable: false),
  'cursors': cursors,
  'position': position < 0 ? 0 : position,
});

IpAutoSnapshot ipAutoDecodeSnapshot({
  required String? encoded,
  String legacyHits = '',
  String legacyPending = '',
  String? legacyCursors,
  String? legacyPosition,
}) {
  List<String> decodeLines(Object? value) => value is List
      ? value.whereType<String>().where((line) => line.contains('|')).toList()
      : <String>[];

  Map<String, dynamic> decodeCursors(Object? value) {
    final out = <String, dynamic>{};
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is String &&
            (entry.value is num || entry.value is String)) {
          out[entry.key as String] = entry.value;
        }
      }
    }
    return out;
  }

  final legacyCursorMap = <String, dynamic>{};
  if (legacyCursors != null && legacyCursors.isNotEmpty) {
    try {
      legacyCursorMap.addAll(decodeCursors(jsonDecode(legacyCursors)));
    } catch (_) {
      // A corrupt cursor key must not discard the other legacy state.
    }
  }
  final legacyPos = int.tryParse(legacyPosition ?? '');
  final legacy = (
    hits: legacyHits.split('\n').where((line) => line.contains('|')).toList(),
    pending: legacyPending.split('\n').where((line) => line.contains('|')).toList(),
    cursors: legacyCursorMap,
    position: legacyPos == null || legacyPos < 0 ? 0 : legacyPos,
  );

  if (encoded == null || encoded.isEmpty) return legacy;
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map || decoded['version'] != 2) return legacy;
    final position = decoded['position'];
    if (position is! int || position < 0 ||
        decoded['hits'] is! List ||
        decoded['pending'] is! List ||
        decoded['cursors'] is! Map) {
      return legacy;
    }
    return (
      hits: decodeLines(decoded['hits']),
      pending: decodeLines(decoded['pending']),
      cursors: decodeCursors(decoded['cursors']),
      position: position,
    );
  } catch (_) {
    return legacy;
  }
}

Future<void> ipAutoLoad() async {
  // Capture the mode and its keys before the first await: mode-local state
  // must never be mixed by a network-mode switch during preference I/O.
  final loadNationalMode = nationalMode;
  final suffix = loadNationalMode ? 'nat' : 'glob';
  final snapshotKey = 'ipauto_snapshot_v2_$suffix';
  final hitsKey = loadNationalMode ? _ipAutoKeyNat : _ipAutoKeyGlob;
  final posKey = '${_ipAutoPosKey}_$suffix';
  final cursorKey = '${_ipAutoCursorKey}_$suffix';
  final pendingKey = '${_ipAutoPendingKey}_$suffix';
  try {
    final p = await SharedPreferences.getInstance();
    if (nationalMode != loadNationalMode) return;
    final snapshot = ipAutoDecodeSnapshot(
      encoded: p.getString(snapshotKey),
      legacyHits: p.getString(hitsKey) ?? '',
      legacyPending: p.getString(pendingKey) ?? '',
      legacyCursors: p.getString(cursorKey),
      legacyPosition: p.getString(posKey),
    );
    if (nationalMode != loadNationalMode) return;
    ipAutoHits
      ..clear()
      ..addAll(snapshot.hits);
    ipAutoPendingCore
      ..clear()
      ..addAll(snapshot.pending);
    ipAutoCursors
      ..clear()
      ..addAll(snapshot.cursors);
    ipAutoPos = snapshot.position;
    _ipAutoLoadedNat = loadNationalMode;
  } catch (e, stk) {
    logError(e, stk);
  }
}

Future<bool> _ipAutoSave() async {
  // Persist all mode-local state with one preference write. Immutable snapshots
  // prevent result, retry-queue and cursor generations from being interleaved.
  final saveNationalMode = nationalMode;
  if (_ipAutoLoadedNat != null && _ipAutoLoadedNat != saveNationalMode) return false;
  final hits = List<String>.unmodifiable(ipAutoHits);
  final pending = List<String>.unmodifiable(ipAutoPendingCore);
  final cursors = Map<String, dynamic>.unmodifiable(ipAutoCursors);
  final position = ipAutoPos;
  final snapshotKey = 'ipauto_snapshot_v2_${saveNationalMode ? 'nat' : 'glob'}';
  try {
    final p = await SharedPreferences.getInstance();
    if (nationalMode != saveNationalMode ||
        (_ipAutoLoadedNat != null && _ipAutoLoadedNat != saveNationalMode)) {
      return false;
    }
    final saved = await p.setString(
      snapshotKey,
      ipAutoEncodeSnapshot(
        hits: hits,
        pending: pending,
        cursors: cursors,
        position: position,
      ),
    );
    if (!saved) {
      errJournalAdd(
        StateError('IP Auto snapshot preference write returned false'),
        kind: 'IP-AUTO-SNAPSHOT-WRITE',
      );
    }
    return saved;
  } catch (e, stk) {
    logError(e, stk);
    return false;
  }
}

/// Inventory پویا برای اسکن IP؛ رنج‌های تنظیم‌شده و بلوک‌های کشف‌شده
/// به‌صورت چرخشی پیمایش می‌شوند تا هیچ بخش ثابتِ ابتدای فهرست انحصاری نشود.
Future<List<String>> _ipAutoBlocks(Iterable<Server> knownServers) async {
  // Active probes are restricted to exact A/AAAA endpoints declared by
  // configured VPN server records. Do not enumerate unrelated ISP/CDN CIDRs.
  final ips = <String>{};
  final servers = knownServers.toList(growable: false);
  final resolveConcurrency = natAdaptiveConcurrency(0);
  for (var offset = 0; offset < servers.length; offset += resolveConcurrency) {
    final batch = servers.skip(offset).take(resolveConcurrency);
    final resolved = await Future.wait(batch.map((server) async {
      if (server.isIp) return <String>[server.host];
      return await nipResolveAll(server.host);
    }));
    for (final addresses in resolved) {
      for (final address in addresses) {
        final parsed = InternetAddress.tryParse(address);
        if (parsed == null ||
            (parsed.type != InternetAddressType.IPv4 &&
                parsed.type != InternetAddressType.IPv6)) continue;
        ips.add(parsed.address);
      }
    }
  }
  final blocks = ips.map((ip) {
    final parsed = InternetAddress.tryParse(ip);
    return parsed?.type == InternetAddressType.IPv6 ? '$ip/128' : '$ip/32';
  }).toList()..sort();
  return blocks;
}

Future<({List<String> addresses, Map<String, dynamic> cursors})> _ipAutoNextAddrs(Iterable<Server> knownServers, {bool Function()? shouldAbort, int batchSize = _ipAutoBatch}) async {
  // A mode switch while compute() is running must not apply stale cursors
  // or a stale batch position to the newly selected network mode.
  final modeSnapshot = nationalMode;
  final cursorSnapshot = Map<String, dynamic>.of(ipAutoCursors);
  final args = <String, dynamic>{
    // Only exact addresses resolved from configured VPN server endpoints
    // are actively probed. CDN/ISP CIDRs are not swept as third-party networks.
    'cfIpsBatch': 0,
    'maxAddrs': batchSize,
    'blocks': await _ipAutoBlocks(knownServers),
    'nationalMode': modeSnapshot,
    'liveRanges': <String>[],
    'cursors': cursorSnapshot,
  };
  final gen = await compute(_genAddrsIso, args);
  if (nationalMode != modeSnapshot || (shouldAbort?.call() ?? false)) {
    return (addresses: const <String>[], cursors: cursorSnapshot);
  }
  // Overlapping CIDRs and exact host seeds may describe the same endpoint.
  // Probe each distinct address once while preserving deterministic order.
  final all = (gen['addrs'] as List).cast<String>().toSet().toList(growable: false);
  final generatedCursors = Map<String, dynamic>.from(gen['cursors'] as Map);
  if (all.isEmpty) return (addresses: const <String>[], cursors: cursorSnapshot);
  // Return staged cursors. The caller commits them only after the complete TCP
  // batch has finished; cancellation never skips addresses in the inventory.
  final slice = all.toList(growable: false);
  return (addresses: slice, cursors: generatedCursors);
}

extension IpAutoExt on _HomePageState {
  /// آیا اسکن باید همین الان متوقف شود (VPN وصل شد، یا برنامه مشغول اتصال است، یا کاربر توقف زد)
  bool _ipAutoHalt({bool? modeSnapshot}) =>
      ipAutoStopFlag || connected || busy ||
      (modeSnapshot != null && nationalMode != modeSnapshot);

  /// نت ملی: اسکن IP خودکار بدون دکمه (هر ۲۴ ساعت، یا ۶ ساعت اگر نتیجه نداشت)، فقط وقتی VPN قطع است.
  /// نتایج در فهرست نت ملی ذخیره می‌شوند و هیچ صف یا بازه‌ی دیگری را تغییر نمی‌دهد.
  Future<void> ipAutoBackground() async {
    final runNationalMode = nationalMode;
    if (!kNatIpScanOn || !runNationalMode) return;
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

      final now = DateTime.now().millisecondsSinceEpoch;
      // Last-run time is diagnostic metadata only; no 6/24-hour scan cooldown.
      final completed = await _ipAutoRunOnce((s) => ipAutoStatus = s);
      // Failed, cancelled, or mode-switched scans must not consume the retry interval.
      if (completed && !_ipAutoHalt(modeSnapshot: runNationalMode)) {
        await p.setString(_ipAutoAtKey, now.toString());
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

  Future<bool> _ipAutoRunOnce(void Function(String) say, {bool manual = false}) async {
    final runNationalMode = nationalMode;
    bool halted() => _ipAutoHalt(modeSnapshot: runNationalMode);
    if (halted()) return false;

    // Passive candidate discovery is independent of saved VPN configurations.
    // It merges the complete project domain catalogs, dual-stack DNS answers,
    // global-folder IP observations and the rotating CDN range inventory.
    // These candidates are inventory only; active endpoint checks below remain
    // tied to exact VPN server host:port pairs.
    await goldLoad();
    if (halted()) return false;
    final discoveryPrefs = await SharedPreferences.getInstance();
    // Keep every previously discovered IP in both modes. National mode changes
    // scan order, never the set of retained global observations.
    final baseCandidates = <String>{
      for (final entry in _goldIps.values) entry.ip,
    };
    final discoveredGlobalDomains = runNationalMode
        ? const <String>[]
        : await kingDiscoverGlobalDnsDomains();
    if (halted()) return false;
    final domainSources = <String>{
      ...discoveredGlobalDomains,
      ...kAutoNationalSniDomains,
      ...kAutoSniDomains,
      ...dnsxFullDomains(),
      ...natFrontSnis,
      ...natRelayHosts,
    };
    if (runNationalMode) {
      for (final server in <Server>{
        ...natTemplateSeeds,
        ...good,
        ...pending,
      }) {
        if (!server.isIp) domainSources.add(server.host);
      }
    }
    final domainInventory = runNationalMode
        ? dnsxNationalFirstDomains(extra: domainSources)
        : (domainSources
            .map((domain) => domain.trim().toLowerCase())
            .where((domain) => domain.isNotEmpty && domain.contains('.'))
            .toList()
          ..sort());
    final savedDomainCursor =
        discoveryPrefs.getString(_autoScanDomainCursorKey);
    final previousDomainIndex = savedDomainCursor == null
        ? -1
        : domainInventory.indexOf(savedDomainCursor);
    final domainStart = previousDomainIndex < 0
        ? 0
        : (previousDomainIndex + 1) % domainInventory.length;
    final domainBatch = <String>[
      for (var i = 0; i < min(_autoScanDomainBatchSize, domainInventory.length); i++)
        domainInventory[(domainStart + i) % domainInventory.length],
    ];
    final stagedDomainCursor =
        domainBatch.isEmpty ? savedDomainCursor : domainBatch.last;

    final savedCdnCursorJson =
        discoveryPrefs.getString(_autoScanCdnCursorKey);
    final stagedCdnCursors = <String, dynamic>{};
    if (savedCdnCursorJson != null && savedCdnCursorJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedCdnCursorJson);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.value is num || entry.value is String) {
              stagedCdnCursors['${entry.key}'] = entry.value;
            }
          }
        }
      } catch (e, stk) {
        logError(e, stk);
      }
    }
    await refreshCdnRanges();
    if (halted()) return false;
    final dnsCandidates = await _autoResolveDualStackTargets(
      domains: domainBatch,
      cancelled: halted,
    );
    if (halted()) return false;
    // Keep CDN ranges in the inventory in both modes; domestic DNS candidates
    // are placed first below, while global ranges remain queued for later work.
    final cdnRanges = _liveCdnRanges.isNotEmpty
        ? _liveCdnRanges
        : [..._cfRanges, ..._cfRangesV6];
    // Preserve insertion order so domestic-first DNS observations are
    // consumed before saved global IPs and CDN ranges, without dropping them.
    final candidateRanges = <String>{
      ...dnsCandidates,
      ...baseCandidates,
      ...cdnRanges,
      if (baseCandidates.isEmpty &&
          dnsCandidates.isEmpty &&
          cdnRanges.isEmpty)
        ...kAutoFallbackIps,
    }.toList();
    final cdnCandidates = _getCfIps(
      batchSize: _autoScanCdnBatchSize,
      liveRanges: candidateRanges,
      cursors: stagedCdnCursors,
    );
    final independentIpCandidates = <String>{
      ...baseCandidates,
      ...dnsCandidates,
      ...cdnCandidates,
    }.toList()
      ..sort();
    final inventorySaved = await goldAddScans(
      {'ip_candidates': independentIpCandidates},
      shouldAbort: halted,
    );
    if (!inventorySaved || halted()) return false;
    await discoveryPrefs.setString(
      _autoScanCdnCursorKey,
      jsonEncode(stagedCdnCursors),
    );
    if (stagedDomainCursor != null) {
      await discoveryPrefs.setString(
        _autoScanDomainCursorKey,
        stagedDomainCursor,
      );
    }

    // A national scan uses the national hot-source/template pipeline; it must
    // not fetch or fall back to the global discovered-server pool.
    var pool = <Server>[];
    if (runNationalMode) {
      say('دریافت الگوهای مستقل نت ملی...');
      try {
        final nationalSeeds = await natHotNext(max(1, Platform.numberOfProcessors * 4096), fetch: false);
        if (halted()) return false;
        if (nationalSeeds.isNotEmpty) {
          natTemplateSeeds = List<Server>.of(nationalSeeds);
          pool = [...nationalSeeds, ...good, ...pending];
        } else {
          pool = <Server>[...natTemplateSeeds, ...good, ...pending];
        }
      } catch (e, stk) {
        logError(e, stk);
        if (halted()) return false;
        pool = <Server>[...natTemplateSeeds, ...good, ...pending];
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
      say('موجودی مستقل IP ذخیره شد؛ برای بررسی فعال، ابتدا یک endpoint دقیق VPN در منابع پروژه موجود باشد.');
    }
    say('ساخت آدرس‌ها...');
    final tcpConcurrency =
        (manual && runNationalMode) ? kNatManualConc : _ipAutoConc;
    final effectiveTcpConcurrency = natAdaptiveConcurrency(tcpConcurrency);
    final batchCapacity = _ipAutoBatch;
    final knownEndpointByLink = <String, Server>{
      for (final server in [...pool, ...good, ...pending, ...fetchedAll])
        server.link: server,
    };
    final knownEndpoints = knownEndpointByLink.values.toList(growable: false);
    if (knownEndpoints.isEmpty) {
      say('موجودی مستقل ذخیره شد: ${independentIpCandidates.length} IP کاندیدا؛ endpoint پیکربندی‌شده‌ای برای تست فعال وجود ندارد.');
      return true;
    }
    final generatedBatch = await _ipAutoNextAddrs(
      knownEndpoints,
      shouldAbort: halted,
      batchSize: batchCapacity,
    );
    final addrs = generatedBatch.addresses;
    if (halted()) return false;
    if (addrs.isEmpty) {
      say('موجودی مستقل IP ذخیره شد؛ endpointهای نمونه در این نوبت به آدرس قابل‌بررسی resolve نشدند.');
      return true;
    }
    // Keep every source configuration associated with its exact IP:port pair.
    // Port equality alone cannot identify transport, TLS, SNI or credentials.
    final endpointSources =
        <({Server endpoint, Iterable<String> addresses, int port})>[];
    final addressSet = addrs.toSet();
    for (final server in knownEndpoints) {
      if (halted()) return false;
      if (server.port < 1 || server.port > 65535) continue;
      final resolved = server.isIp
          ? <String>[server.host]
          : await nipResolveAll(server.host);
      if (halted()) return false;
      endpointSources.add((
        endpoint: server,
        addresses: resolved,
        port: server.port,
      ));
    }
    final endpointTemplates = natIndexEndpointTemplates<Server>(
      sources: endpointSources,
      keyOf: (server) => server.link,
      addressScope: addressSet,
    );
    final endpointTargets = <int, Set<String>>{};
    for (final pair in endpointTemplates.keys) {
      final separator = pair.lastIndexOf('|');
      if (separator <= 0) continue;
      final address = pair.substring(0, separator);
      final port = int.tryParse(pair.substring(separator + 1));
      if (port == null) continue;
      (endpointTargets[port] ??= <String>{}).add(address);
    }
    final ports = endpointTargets.keys.toList()..sort();
    final allowedEndpointPairs = endpointTemplates.keys.toSet();

    // مرحله‌ی ۱: TCP فقط روی host:portهای اعلام‌شده در کانفیگ‌ها
    final candidates = <String>[];
    for (final port in ports) {
      if (halted()) break;
      final endpointIps = (endpointTargets[port] ?? <String>{}).toList();
      say('بررسی endpointهای تنظیم‌شده روی پورت $port (${endpointIps.length} آدرس)...');
      var completed = 0;
      final hits = await natScanIps(
        endpointIps,
        port: port,
        concurrency: tcpConcurrency,
        want: endpointIps.length,
        timeout: const Duration(milliseconds: 1500),
        cancelled: halted,
        onProgress: (done, total, _) => completed = done,
      );
      if (halted()) return false;
      if (completed < endpointIps.length) {
        say('بسته endpointهای پورت $port کامل نشد؛ Cursor دست‌نخورده ماند و همین دسته در اجرای بعدی ادامه می‌یابد.');
        return false;
      }
      for (final h in hits) {
        candidates.add('${h.ip}|$port');
      }
    }

    if (halted()) return false;
    // Commit only after every configured port has completed its TCP slice.
    // Core-verification backlog is persisted separately and can resume later.
    ipAutoCursors
      ..clear()
      ..addAll(generatedBatch.cursors);

    // مرحله‌ی ۲: تست واقعی با هسته‌ی VPN، دو بار پشت سر هم
    final url = runNationalMode ? _natTestUrls.first : delayTestUrl;
    final seen = ipAutoHits.toSet();
    final queued = ipAutoPendingCore.toSet();
    for (final candidate in candidates) {
      if (!seen.contains(candidate) && queued.add(candidate)) {
        ipAutoPendingCore.add(candidate);
      }
    }
    // Persist the completed TCP cursor with its complete core-verification
    // backlog before lengthy native tests. Process death can then resume safely.
    if (!await _ipAutoSave()) {
      say('ذخیرهٔ نقطهٔ ادامهٔ IP Auto ناموفق بود؛ دسته دوباره بررسی خواهد شد.');
      return false;
    }
    if (endpointTemplates.isEmpty) {
      // Never borrow a different server just because its port happens to match.
      say('بسته TCP کامل شد؛ ${ipAutoPendingCore.length} نامزد برای بررسی هسته ذخیره شد و منتظر الگوی دقیق endpoint است.');
      return true;
    }
    final activeQueue = ipAutoPendingCore
        .where(allowedEndpointPairs.contains)
        .toList(growable: true);
    var found = 0;
    var checked = 0;
    // Only pending pairs still present in the current configured endpoint
    // inventory are actively tested; out-of-scope historical items stay queued.
    say('${candidates.length} endpointها • ${activeQueue.length} مورد مجاز برای تست هسته');
    while (activeQueue.isNotEmpty) {
      if (halted()) break;
      final c = activeQueue.removeAt(0);
      checked++;
      if (seen.contains(c)) {
        ipAutoPendingCore.remove(c);
        if (!await _ipAutoSave()) return false;
        continue;
      }
      final parts = c.split('|');
      final ip = parts[0];
      final port = int.tryParse(parts[1]) ?? 443;
      final matchingTemplates = endpointTemplates[c] ?? const <Server>[];
      var verifiedWithMatchingConfig = false;
      for (final template in matchingTemplates) {
        if (halted()) return false;
        final ipLink = _natSetPort(
          _natSetHost(template.link, ip, template.host),
          port,
        );
        final serverWithCandidateIp =
            Server(ipLink, template.name, ip, port);
        final firstOk = await _ipAutoCoreOk(serverWithCandidateIp, url);
        if (halted()) return false;
        if (!firstOk) continue;
        final secondOk = await _ipAutoCoreOk(serverWithCandidateIp, url);
        if (halted()) return false;
        if (secondOk) {
          verifiedWithMatchingConfig = true;
          break;
        }
      }
      if (!verifiedWithMatchingConfig) {
        // Every original configuration for this exact pair gets a chance.
        // A transient failure keeps the pair queued for a later retry.
        say('تست $checked • جواب‌داده: $found • هیچ‌یک از کانفیگ‌های دقیق تأیید نشد؛ برای نوبت بعد حفظ شد');
        continue;
      }
      ipAutoPendingCore.remove(c);
      ipAutoHits.insert(0, c);
      // Core outbound delay is not proof of a clean IP or Android TUN health.
      // Keep it as a candidate only; promotion requires a real user tunnel test.
      seen.add(c);
      found++;
      if (!await _ipAutoSave()) {
        say('ذخیرهٔ نتیجهٔ IP Auto ناموفق بود؛ صف بازیابی برای اجرای بعد حفظ می‌شود.');
        return false;
      }
      say('تست $checked • جواب‌داده: $found');
    }
    if (halted()) {
      say('متوقف شد؛ نتایج این اجرا کامل نیستند.');
      return false;
    }
    if (ipAutoPendingCore.isNotEmpty) {
      say('این نوبت تمام شد: $found IP جدید؛ ${ipAutoPendingCore.length} مورد برای ادامه در صف باقی ماند.');
    } else {
      say('تمام شد: $found IP جدید در حالت ${runNationalMode ? 'نت ملی' : 'جهانی'}.');
    }
    return true;
  }

  Future<void> ipAutoSheet(BuildContext ctx0) async {
    var sheetScanRunning = false;
    await ipAutoLoad();
    await goldLoad();
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
                      'IPهای پاسخ‌گو فقط کاندیدا هستند؛ پذیرش نهایی نیازمند عبور واقعی ترافیک از تونل است.'),
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
                  if ((_goldScan['ip_candidates'] ?? const <String>[]).isNotEmpty) ...[
                    Text('موجودی مستقل IP: ${(_goldScan['ip_candidates'] ?? const <String>[]).length} نامزد (IPv4/IPv6، تأییدنشده)'),
                    OutlinedButton(
                      onPressed: () async {
                        final values = _goldScan['ip_candidates'] ?? const <String>[];
                        await Clipboard.setData(ClipboardData(text: values.join('\n')));
                        if (!ctx0.mounted) return;
                        ScaffoldMessenger.maybeOf(ctx0)?.showSnackBar(SnackBar(
                            content: Text('${values.length} IP کاندیدا کپی شد')));
                      },
                      child: Text('کپی همهٔ IPهای کاندیدا (${(_goldScan['ip_candidates'] ?? const <String>[]).length})'),
                    ),
                    SelectableText((_goldScan['ip_candidates'] ?? const <String>[]).join('\n')),
                    const Divider(height: 20),
                  ],
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
