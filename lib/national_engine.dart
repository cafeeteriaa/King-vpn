part of 'main.dart';

// King VPN - National Network Intelligence Engine (NNIE)
// This module is deliberately additive: it records evidence and ranks candidates;
// it does not rewrite a V2Ray URI or claim that a probe proves tunnel reachability.

/// Bounded, privacy-preserving history. Only a SHA-256 key is persisted, never
/// the raw V2Ray link, UUID, password, server name, or full endpoint string.
class NationalNetworkIntelligence {
  static const String _prefsKey = 'nnie_profiles_v3'; // v3: endpoint + transport + TLS + domestic/global scope
  static const int _maxEntries = 500;
  static Map<String, NatEndpointMemory> _memory = <String, NatEndpointMemory>{};
  static bool _loaded = false;
  static Future<void>? _loading;

  static Future<void> load() async {
    if (_loaded) return;
    _loading ??= _loadImpl();
    await _loading;
  }

  static Future<void> _loadImpl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _memory = <String, NatEndpointMemory>{};
          for (final e in decoded.entries) {
            if (e.key is String) _memory[e.key as String] = NatEndpointMemory.fromJson(e.value);
          }
        }
      }
    } catch (e, st) {
      logError(e, st);
    } finally {
      _loaded = true;
      _loading = null;
    }
  }

  /// Key = hash(network scope + transport + TLS flag + canonical endpoint).
  /// Domestic and global tunnel outcomes must never train each other's ranking.
  /// The raw link is never stored; old v2 mixed-scope history is intentionally not reused.
  static String keyOfServer(Server s, {required bool nationalMode}) =>
      keyFor(s.key, '${nationalMode ? 'domestic' : 'global'}|${s.net}|${s.tls ? 'tls' : 'plain'}');

  static String keyFor(String canonicalEndpoint, String transport) {
    final raw = '${transport.toLowerCase()}|${canonicalEndpoint.trim().toLowerCase()}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  static NatEndpointMemory memoryFor(String endpointKey) =>
      _memory[endpointKey] ?? const NatEndpointMemory(
        attempts: 0, successes: 0, failStreak: 0,
        ewmaConnectMs: 0, lastSuccessMs: 0, stableSuccesses: 0,
      );

  static double scoreFor(String endpointKey) => memoryFor(endpointKey).score;

  static Future<void> record({
    required String endpointKey,
    required bool success,
    required int elapsedMs,
    required bool stableForFiveMinutes,
  }) async {
    await load();
    final old = memoryFor(endpointKey);
    final attempts = min(10000, old.attempts + 1);
    final successes = min(attempts, old.successes + (success ? 1 : 0));
    final ewma = success
        ? (old.ewmaConnectMs <= 0 ? elapsedMs.toDouble() : old.ewmaConnectMs * 0.75 + elapsedMs * 0.25)
        : old.ewmaConnectMs;
    _memory[endpointKey] = NatEndpointMemory(
      attempts: attempts,
      successes: successes,
      failStreak: success ? 0 : min(50, old.failStreak + 1),
      ewmaConnectMs: ewma,
      lastSuccessMs: success ? DateTime.now().millisecondsSinceEpoch : old.lastSuccessMs,
      stableSuccesses: stableForFiveMinutes ? min(1000, old.stableSuccesses + 1) : old.stableSuccesses,
    );
    await _save();
  }

  static Timer? _stableTimer;

  /// Counts a stable run only after five minutes AND a fresh end-to-end
  /// traffic verification. A CONNECTED state alone is not stable-traffic proof.
  static void armStable(
    String endpointKey,
    Future<bool> Function() verifyStableTraffic,
  ) {
    _stableTimer?.cancel();
    _stableTimer = Timer(const Duration(minutes: 5), () {
      _stableTimer = null;
      unawaited(() async {
        try {
          if (await verifyStableTraffic()) await recordStable(endpointKey);
        } catch (_) {
          // Missing probe evidence is never counted as a successful stable run.
        }
      }());
    });
  }

  static Future<void> recordStable(String endpointKey) async {
    await load();
    final old = _memory[endpointKey];
    if (old == null) return; // only extend entries that already have a real success
    _memory[endpointKey] = NatEndpointMemory(
      attempts: old.attempts, successes: old.successes, failStreak: old.failStreak,
      ewmaConnectMs: old.ewmaConnectMs, lastSuccessMs: old.lastSuccessMs,
      stableSuccesses: min(1000, old.stableSuccesses + 1),
    );
    await _save();
  }

  static Future<void> _save() async {
    try {
      // Keep most useful/recent entries; do not let history grow indefinitely.
      final entries = _memory.entries.toList()
        ..sort((a, b) => b.value.score.compareTo(a.value.score));
      if (entries.length > _maxEntries) {
        _memory = Map<String, NatEndpointMemory>.fromEntries(entries.take(_maxEntries));
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_memory.map((k, v) => MapEntry(k, v.toJson()))));
    } catch (e, st) {
      logError(e, st);
    }
  }

  /// First stage is cheap and broad; expensive transports are deferred until
  /// cheap compatible candidates have been exhausted. The stage is a ranking
  /// hint, never a hard ban on a valid user-supplied configuration.
  static NatAttemptStage stageFor({required int variantIndex, required bool isKcp,
      required bool isKnownWinner, required bool isCdnCompatible}) =>
      natStageFor(variantIndex: variantIndex, isKcp: isKcp,
          isKnownWinner: isKnownWinner, isCdnCompatible: isCdnCompatible);

  static List<T> rank<T>(Iterable<T> items, String Function(T) key) {
    return natStableSorted(items,
        (a, b) => scoreFor(key(b)).compareTo(scoreFor(key(a))));
  }
}

/// Multi-source reachability check (NNIE section A). Advisory only: it never
/// disables the VPN, never changes user settings and never blocks a connect.
/// Caller must run it while the tunnel is down, otherwise probes go through it.
class NatNetworkDiagnosis {
  static const Duration _ttl = Duration(minutes: 10);
  static const List<String> _domesticHosts = <String>['www.aparat.com', 'www.digikala.com'];
  static const List<String> _globalHosts = <String>['www.google.com', 'www.cloudflare.com'];
  static const List<String> _globalResolvers = <String>['8.8.8.8', '1.1.1.1'];
  // Dedicated domestic DNS probes belong to this engine; they do not reuse
  // the general-purpose DNS scanner, its ranges, or its cached IP inventory.
  static const List<String> _domesticResolvers = <String>[
    '178.22.122.100', '185.51.200.2', '78.157.42.100',
  ];
  static const List<String> _domesticDnsNames = <String>[
    'aparat.com', 'digikala.com',
  ];

  static NatNetworkClass current = NatNetworkClass.unknown;
  static DateTime? _checkedAt;
  static String? _identityAtCheck;
  static bool _running = false;
  static final NatSingleFlight<NatNetworkClass> _refreshFlight =
      NatSingleFlight<NatNetworkClass>();

  /// Network identity from local interfaces (no native code). Hashed, so the
  /// cache can tell "same network" from "network changed" without storing IPs.
  static Future<String> _identityHash() async {
    try {
      final ifs = await NetworkInterface.list(includeLoopback: false);
      final parts = <String>[
        for (final i in ifs) for (final a in i.addresses) '${i.name}=${a.address}',
      ]..sort();
      return sha256.convert(utf8.encode(parts.join(';'))).toString();
    } catch (_) {
      return '';
    }
  }

  static Future<bool> _tcpOk(String host) async {
    try {
      final s = await Socket.connect(host, 443, timeout: const Duration(seconds: 3));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// True when the national network is up but the international one is cut.
  /// Read by the search ordering (main.dart): Iran-hosted sources go first.
  static bool get preferDomestic =>
      current == NatNetworkClass.domesticOnlyLikely ||
      current == NatNetworkClass.dnsDegraded ||
      current == NatNetworkClass.transportRestricted;

  static Future<NatNetworkClass> refresh({bool force = false}) =>
      _refreshFlight.run(() => _refreshImpl(force: force));

  static Future<NatNetworkClass> _refreshImpl({bool force = false}) async {
    if (_running) return current;
    // Mark as running BEFORE the first await, so two callers cannot both pass
    // the guard while the identity hash is being computed.
    _running = true;
    try {
      final at = _checkedAt;
      final id = await _identityHash();
      if (shouldReuseNetworkProbeCache(
          force: force,
          currentIdentity: id,
          cachedIdentity: _identityAtCheck,
          checkedAt: at,
          now: DateTime.now(),
          ttl: _ttl,
        )) {
        return current;
      }
      // All probes start together. Awaiting the groups one after another made
      // the total time the SUM of their timeouts (a black-holed TCP connect
      // waits the full timeout), so the caller's deadline usually expired first.
      final domesticF = Future.wait(_domesticHosts.map(_tcpOk));
      final globalF = Future.wait(_globalHosts.map(_tcpOk));
      final globalDnsF = Future.wait(
          _globalResolvers.map((r) => NatDnsWireProbe.probe(r, 'google.com')));
      final domesticDnsF = Future.wait([
        for (final resolver in _domesticResolvers)
          for (final domain in _domesticDnsNames)
            NatDnsWireProbe.probe(resolver, domain),
      ]);
      final domesticTcp = await domesticF;
      final globalTcp = await globalF;
      final globalDnsRes = await globalDnsF;
      final domesticDnsRes = await domesticDnsF;
      final domesticDnsOk = domesticDnsRes.any((x) => x.ok);
      final globalDnsOk = globalDnsRes.any((x) => x.ok);
      final domesticTcpOk = domesticTcp.any((x) => x);
      final globalTcpOk = globalTcp.any((x) => x);
      // DNS poisoning / blockpage check: a resolver returned a public A answer,
      // yet none of the answered addresses accepts TCP/443, while domestic hosts
      // do. That is the typical signature of an injected answer, not a live Google.
      var poison = false;
      if (globalDnsOk && !globalTcpOk && domesticTcpOk) {
        final answered = [
          for (final r in globalDnsRes) if (r.ok) ...r.addresses,
        ].toSet().take(2).toList();
        final reach = await Future.wait(answered.map(_tcpOk));
        poison = reach.isNotEmpty && !reach.any((x) => x);
      }
      final ev = NatProbeEvidence(
        domesticDnsOk: domesticDnsOk,
        domesticTcpOk: domesticTcpOk,
        globalDnsOk: globalDnsOk,
        globalTcpOk: globalTcpOk,
        dnsPoisonSuspected: poison,
        sampleCount: domesticTcp.length + globalTcp.length +
            globalDnsRes.length + domesticDnsRes.length,
      );
      current = ev.classify();
      _checkedAt = DateTime.now();
      _identityAtCheck = id;
      dbg('NNIE-DIAG: ${natNetworkClassLabel(current)} '
          '(domesticTcp=${ev.domesticTcpOk} domesticDns=$domesticDnsOk '
          'globalTcp=${ev.globalTcpOk} globalDns=${ev.globalDnsOk} poison=$poison)');
    } catch (e, st) {
      logError(e, st);
      current = NatNetworkClass.unknown;
    } finally {
      _running = false;
    }
    return current;
  }
}

/// Dedicated Smart Pilot link scanner. Its target inventory and results are
/// independent from the general DNS/IP/SNI scanners and their user-defined ranges.
/// It verifies TLS handshakes to a small fixed HTTPS endpoint set; it never sweeps subnets.
class PilotNetworkProbe {
  static const List<String> domesticTargets = <String>[
    'www.aparat.com',
    'www.digikala.com',
    'divar.ir',
  ];
  static const List<String> globalTargets = <String>[
    'www.cloudflare.com',
    'www.google.com',
    'github.com',
  ];
  static const Duration _timeout = Duration(milliseconds: 2600);
  static DateTime? _lastAt;
  static String? _lastIdentity;
  static NetworkEvidence _last = const NetworkEvidence(
    domestic: LinkHealth.unknown,
    global: LinkHealth.unknown,
  );
  static Future<NetworkEvidence>? _flight;
  static NetworkEvidence get current => _last;

  static Future<NetworkEvidence> refresh({bool force = false}) async {
    final active = _flight;
    if (active != null) return active;
    final future = _refresh(force: force);
    _flight = future;
    try {
      return await future;
    } finally {
      if (identical(_flight, future)) _flight = null;
    }
  }

  static Future<NetworkEvidence> _refresh({required bool force}) async {
    final identity = await _networkIdentity();
    final lastAt = _lastAt;
    if (shouldReuseNetworkProbeCache(
        force: force,
        currentIdentity: identity,
        cachedIdentity: _lastIdentity,
        checkedAt: lastAt,
        now: DateTime.now(),
        ttl: const Duration(minutes: 2),
      )) {
      return _last;
    }
    final domesticFuture = Future.wait(domesticTargets.map(_probeHttps));
    final globalFuture = Future.wait(globalTargets.map(_probeHttps));
    final domestic = await domesticFuture;
    final global = await globalFuture;
    LinkHealth health(List<int?> samples) {
      final successes = samples.whereType<int>().length;
      if (successes >= 2) return LinkHealth.healthy;
      if (successes == 1) return LinkHealth.degraded;
      return LinkHealth.unreachable;
    }
    _last = NetworkEvidence(
      domestic: health(domestic),
      global: health(global),
      domesticSamples: domestic.length,
      globalSamples: global.length,
      domesticSuccesses: domestic.whereType<int>().length,
      globalSuccesses: global.whereType<int>().length,
      domesticLatencyMs: _median(domestic),
      globalLatencyMs: _median(global),
      domesticTlsReachabilityVerified: domestic.whereType<int>().length >= 2,
      globalTlsReachabilityVerified: global.whereType<int>().length >= 2,
    );
    _lastAt = DateTime.now();
    _lastIdentity = identity;
    dbg('PILOT-TLS-PROBE: domestic=${domestic.whereType<int>().length}/${domestic.length} '
        'global=${global.whereType<int>().length}/${global.length} '
        'latencyDomestic=${_median(domestic)}ms latencyGlobal=${_median(global)}ms');
    return _last;
  }

  static Future<int?> _probeHttps(String host) async {
    final watch = Stopwatch()..start();
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(host, 443, timeout: _timeout);
      watch.stop();
      return watch.elapsedMilliseconds;
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  static int? _median(List<int?> values) {
    final sorted = values.whereType<int>().toList()..sort();
    return sorted.isEmpty ? null : sorted[sorted.length ~/ 2];
  }

  static Future<String> _networkIdentity() async {
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false);
      final values = <String>[
        for (final item in interfaces)
          for (final address in item.addresses)
            '${item.name}=${address.address}',
      ]..sort();
      return sha256.convert(utf8.encode(values.join(';'))).toString();
    } catch (_) {
      return '';
    }
  }
}

String natNetworkClassLabel(NatNetworkClass value) => switch (value) {
      NatNetworkClass.globalReachable => 'دسترسی جهانی برقرار',
      NatNetworkClass.domesticOnlyLikely => 'احتمالاً فقط مسیرهای داخلی فعال‌اند',
      NatNetworkClass.dnsDegraded => 'اختلال یا دست‌کاری DNS محتمل است',
      NatNetworkClass.transportRestricted => 'محدودیت مسیر یا پروتکل محتمل است',
      NatNetworkClass.unknown => 'وضعیت شبکه نامشخص است',
    };

/// NNIE-UI: shows the national-network diagnosis to the user (it used to exist
/// only in the debug log). Visible only while disconnected, because the probes
/// must run with the tunnel down. It never changes a setting by itself.
class NatNetHintCard extends StatefulWidget {
  const NatNetHintCard({super.key, required this.enabled});

  final bool enabled;

  @override
  State<NatNetHintCard> createState() => _NatNetHintCardState();
}

class _NatNetHintCardState extends State<NatNetHintCard> {
  NatNetworkClass _cls = NatNetworkDiagnosis.current;
  bool _checking = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _check();
    _timer = Timer.periodic(const Duration(seconds: 90), (_) => _check());
  }

  @override
  void didUpdateWidget(covariant NatNetHintCard old) {
    super.didUpdateWidget(old);
    // Re-check at the moment the user disconnects, not only on the timer.
    if (widget.enabled && !old.enabled) _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (!widget.enabled || _checking) return;
    _checking = true;
    try {
      final c = await NatNetworkDiagnosis.refresh()
          .timeout(const Duration(seconds: 6), onTimeout: () => NatNetworkDiagnosis.current);
      if (mounted) setState(() => _cls = c);
    } catch (e, st) {
      logError(e, st);
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    final nationalLikely = _cls == NatNetworkClass.domesticOnlyLikely ||
        _cls == NatNetworkClass.dnsDegraded ||
        _cls == NatNetworkClass.transportRestricted;
    final label = _checking && _cls == NatNetworkClass.unknown
        ? 'در حال بررسی شبکه…'
        : natNetworkClassLabel(_cls);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: nationalLikely ? const Color(0xFFD9AE55) : Colors.grey.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('وضعیت شبکه: $label',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
            if (nationalLikely) ...[
              const SizedBox(height: 6),
              const Text(
                'اینترنت جهانی محدود به نظر می‌رسد؛ خلبان هوشمند اصلی به‌صورت خودکار راهبرد داخلی را انتخاب می‌کند. '
                'برنامه سرورهای ایران‌محور را در اولویت قرار می‌دهد.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
