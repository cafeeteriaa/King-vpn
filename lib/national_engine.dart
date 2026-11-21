part of 'main.dart';

// King VPN - National Network Intelligence Engine (NNIE)
// This module is deliberately additive: it records evidence and ranks candidates;
// it does not rewrite a V2Ray URI or claim that a probe proves tunnel reachability.

/// Bounded, privacy-preserving history. Only a SHA-256 key is persisted, never
/// the raw V2Ray link, UUID, password, server name, or full endpoint string.
class NationalNetworkIntelligence {
  static const String _prefsKey = 'nnie_profiles_v2'; // v2: key includes transport + TLS
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
    var preferencesAvailable = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      preferencesAvailable = true;
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final restored = <String, NatEndpointMemory>{};
          for (final e in decoded.entries) {
            if (e.key is String) {
              try {
                restored[e.key as String] = NatEndpointMemory.fromJson(e.value);
              } catch (e, st) {
                logError(e, st);
              }
            }
          }
          _memory = restored;
        }
      }
    } catch (e, st) {
      // A temporary SharedPreferences failure must not permanently disable
      // learned endpoint history for the lifetime of this process.
      logError(e, st);
    } finally {
      _loaded = preferencesAvailable;
      _loading = null;
    }
  }

  /// Key = hash(transport + TLS flag + canonical endpoint). The raw link is never stored.
  static String keyOfServer(Server s) =>
      keyFor(s.key, '${s.net}|${s.tls ? 'tls' : 'plain'}');

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
    Future<bool> Function() verifyStableTraffic, {
    bool Function()? stillValid,
  }) {
    _stableTimer?.cancel();
    _stableTimer = Timer(const Duration(minutes: 5), () {
      _stableTimer = null;
      unawaited(() async {
        try {
          if (await verifyStableTraffic()) {
            await recordStable(endpointKey, stillValid: stillValid);
          }
        } catch (_) {
          // Missing probe evidence is never counted as a successful stable run.
        }
      }());
    });
  }

  static Future<void> recordStable(
    String endpointKey, {
    bool Function()? stillValid,
  }) async {
    await load();
    // load() awaits persistent storage. The connection may have changed while
    // waiting, so validate once more immediately before mutating the evidence.
    if (stillValid != null && !stillValid()) return;
    final old = _memory[endpointKey];
    if (old == null) return; // only extend entries that already have a real success
    _memory[endpointKey] = NatEndpointMemory(
      attempts: old.attempts, successes: old.successes, failStreak: old.failStreak,
      ewmaConnectMs: old.ewmaConnectMs, lastSuccessMs: old.lastSuccessMs,
      stableSuccesses: min(1000, old.stableSuccesses + 1),
    );
    await _save();
  }

  static Future<void> _save() {
    // Serialize preference writes. Concurrent connect/failover callbacks must
    // never let an older snapshot overwrite newer endpoint evidence.
    final next = _saveQueue.then((_) => _saveImpl());
    _saveQueue = next;
    return next;
  }

  static Future<void> _saveQueue = Future<void>.value();

  static Future<void> _saveImpl() async {
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

/// Bounded persistent route evidence grouped by coarse interface and
/// normalized operator label. No IP, SSID, SIM ID, tunnel link or credential
/// is written to this history.
class PilotRouteHistory {
  static const String _prefsKey = 'pilot_route_history_v1';
  static const int _maxGroups = 64;
  static final Map<String, Map<String, Object?>> _entries = {};
  static String _activeGroup = '';
  static bool _loaded = false;
  static Future<void>? _loading;
  static Future<void> _writeQueue = Future<void>.value();

  static bool _validGroup(String value) {
    final parts = value.split('|');
    return parts.length == 2 &&
        const ['wifi', 'mob', 'net'].contains(parts[0]) &&
        RegExp(r'^[a-z0-9_-]{1,24}$').hasMatch(parts[1]);
  }

  /// Uses interface *names* only to classify Wi-Fi/mobile/other.
  /// The app's existing operator label is normalized before persistence.
  static Future<String> networkGroup() async {
    var kind = 'net';
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false);
      final names = interfaces.map((item) => item.name.toLowerCase()).toList();
      if (names.any((name) => name.startsWith('wlan') || name.startsWith('wifi'))) {
        kind = 'wifi';
      } else if (names.any((name) =>
          name.startsWith('rmnet') ||
          name.startsWith('ccmni') ||
          name.startsWith('wwan') ||
          name.startsWith('pdp') ||
          name.startsWith('cell'))) {
        kind = 'mob';
      }
    } catch (_) {
      // Unknown interface is grouped conservatively as "net".
    }
    final operator = natOpKey.trim().toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '');
    final label = operator.isEmpty
        ? 'unknown'
        : operator.substring(0, operator.length.clamp(0, 24).toInt());
    return '$kind|$label';
  }

  static String get currentGroup => _activeGroup;
  /// Loads persisted aggregates without delaying app startup or VPN setup.
  static Future<void> loadForCurrentNetwork() async {
    await load();
    _activeGroup = await networkGroup();
  }

  static Map<String, Object?>? forNetwork(String group) => _entries[group];

  static Future<void> load() async {
    if (_loaded) return;
    _loading ??= _loadImpl();
    await _loading;
  }

  static Future<void> _loadImpl() async {
    var available = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      available = true;
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final item in decoded.entries) {
            if (item.key is! String ||
                !_validGroup(item.key as String) ||
                item.value is! Map) continue;
            final value = <String, Object?>{};
            (item.value as Map).forEach((key, rawValue) {
              if (key is String && rawValue is num) value[key] = rawValue;
            });
            _entries[item.key as String] = value;
          }
        }
      }
    } catch (e, st) {
      logError(e, st);
    } finally {
      _loaded = available;
      _loading = null;
    }
  }

  static Future<void> record({
    required String networkGroup,
    required NetworkEvidence evidence,
  }) {
    if (!_validGroup(networkGroup)) return Future<void>.value();
    _activeGroup = networkGroup;
    if (evidence.domesticSamples < 3 ||
        evidence.globalSamples < 3 ||
        evidence.domesticSuccesses < 0 ||
        evidence.globalSuccesses < 0 ||
        evidence.domesticSuccesses > evidence.domesticSamples ||
        evidence.globalSuccesses > evidence.globalSamples) {
      return Future<void>.value();
    }
    final next = _writeQueue.then((_) async {
      await load();
      final old = _entries[networkGroup] ?? <String, Object?>{};
      int count(String key) {
        final value = old[key];
        return value is num ? value.toInt().clamp(0, 1000000).toInt() : 0;
      }
      double? ewma(String key, int? sample) {
        final previous = old[key];
        final prior = previous is num ? previous.toDouble() : null;
        if (sample == null || sample < 0 || sample > 60000) return prior;
        return prior == null ? sample.toDouble() : prior * 0.75 + sample * 0.25;
      }
      final mode = evidence.mode.name;
      _entries[networkGroup] = <String, Object?>{
        'observations': (count('observations') + 1).clamp(0, 1000000),
        'domesticSamples': (count('domesticSamples') + evidence.domesticSamples).clamp(0, 1000000),
        'domesticSuccesses': (count('domesticSuccesses') + evidence.domesticSuccesses).clamp(0, 1000000),
        'globalSamples': (count('globalSamples') + evidence.globalSamples).clamp(0, 1000000),
        'globalSuccesses': (count('globalSuccesses') + evidence.globalSuccesses).clamp(0, 1000000),
        'domesticLatencyEwmaMs': ewma('domesticLatencyEwmaMs', evidence.domesticLatencyMs),
        'globalLatencyEwmaMs': ewma('globalLatencyEwmaMs', evidence.globalLatencyMs),
        'domesticOnly': (count('domesticOnly') + (mode == 'domesticOnly' ? 1 : 0)).clamp(0, 1000000),
        'globalOnly': (count('globalOnly') + (mode == 'globalOnly' ? 1 : 0)).clamp(0, 1000000),
        'dualStack': (count('dualStack') + (mode == 'dualStack' ? 1 : 0)).clamp(0, 1000000),
        'offline': (count('offline') + (mode == 'offline' ? 1 : 0)).clamp(0, 1000000),
        'unknown': (count('unknown') + (mode == 'unknown' ? 1 : 0)).clamp(0, 1000000),
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      };
      final ordered = _entries.entries.toList()
        ..sort((a, b) => ((b.value['updatedAtMs'] as num?)?.toInt() ?? 0)
            .compareTo((a.value['updatedAtMs'] as num?)?.toInt() ?? 0));
      if (ordered.length > _maxGroups) {
        _entries
          ..clear()
          ..addEntries(ordered.take(_maxGroups));
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode(_entries));
      } catch (e, st) {
        logError(e, st);
      }
    });
    _writeQueue = next.catchError((Object _) {});
    return next;
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
      // No enumerated interface address means there is no reliable network
      // identity. A hash of only the operator (or an empty string) would be
      // reused across unrelated networks and must never become a cache key.
      if (parts.isEmpty) return '';
      // Operator identity matters even when two carriers reuse the same
      // private interface address and Android interface name.
      return sha256.convert(utf8.encode('$natOpKey|${parts.join(';')}')).toString();
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
      if (!force && id.isNotEmpty && at != null && id == _identityAtCheck &&
          DateTime.now().difference(at) < _ttl) {
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
      // A public DNS answer combined with failed TCP/443 does NOT prove DNS
      // poisoning: a carrier may simply block the destination transport. Keep
      // that evidence in the transportRestricted classifier; only set
      // dnsPoisonSuspected when a future probe can independently prove injection.
      // Interface identity can change while DNS/TCP probes are in flight
      // (Wi-Fi <-> mobile, VPN handoff, or roaming). Never publish evidence
      // collected across two different networks as the current route verdict.
      final identityAfterProbe = await _identityHash();
      if (identityAfterProbe != id) {
        current = NatNetworkClass.unknown;
        _checkedAt = null;
        _identityAtCheck = null;
        dbg('NNIE-DIAG: discarded probe results because the network changed');
        return current;
      }
      final ev = NatProbeEvidence(
        domesticDnsOk: domesticDnsOk,
        domesticTcpOk: domesticTcpOk,
        globalDnsOk: globalDnsOk,
        globalTcpOk: globalTcpOk,
        sampleCount: domesticTcp.length + globalTcp.length +
            globalDnsRes.length + domesticDnsRes.length,
        domesticTcpSuccesses: domesticTcp.where((ok) => ok).length,
        globalTcpSuccesses: globalTcp.where((ok) => ok).length,
      );
      current = ev.classify();
      // If interface enumeration is unavailable, use this sample once but
      // never cache it as belonging to an identifiable network.
      _checkedAt = id.isNotEmpty ? DateTime.now() : null;
      _identityAtCheck = id.isNotEmpty ? id : null;
      dbg('NNIE-DIAG: ${natNetworkClassLabel(current)} '
          '(domesticTcp=${ev.domesticTcpOk} domesticDns=$domesticDnsOk '
          'globalTcp=${ev.globalTcpOk} globalDns=${ev.globalDnsOk})');
    } catch (e, st) {
      logError(e, st);
      current = NatNetworkClass.unknown;
      _checkedAt = null;
      _identityAtCheck = null;
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
    if (!force && identity.isNotEmpty && lastAt != null && identity == _lastIdentity &&
        DateTime.now().difference(lastAt) < const Duration(minutes: 2)) {
      return _last;
    }
    final domesticFuture = Future.wait(domesticTargets.map(_probeHttps));
    final globalFuture = Future.wait(globalTargets.map(_probeHttps));
    final domestic = await domesticFuture;
    final global = await globalFuture;
    // The route may have changed during the concurrent TLS checks. Discard
    // that mixed snapshot instead of steering Smart Pilot with stale evidence.
    final identityAfterProbe = await _networkIdentity();
    if (identityAfterProbe != identity) {
      _last = const NetworkEvidence(
        domestic: LinkHealth.unknown,
        global: LinkHealth.unknown,
      );
      _lastAt = null;
      _lastIdentity = null;
      dbg('PILOT-TLS-PROBE: discarded results because the network changed');
      return _last;
    }
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
    // Persist one complete, identity-verified snapshot under a coarse
    // physical-interface/operator group; raw interface addresses stay transient.
    if (identity.isNotEmpty) {
      final group = await PilotRouteHistory.networkGroup();
      // History is advisory; never hold up VPN connection decisions on disk I/O.
      unawaited(PilotRouteHistory.record(
        networkGroup: group,
        evidence: _last,
      ).catchError((Object error, StackTrace stack) {
        logError(error, stack);
      }));
    }
    // An unknown interface identity is not a safe cache key.
    _lastAt = identity.isNotEmpty ? DateTime.now() : null;
    _lastIdentity = identity.isNotEmpty ? identity : null;
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
      // Without interface addresses the operator alone is not a unique
      // network identity, so disable caching until a real identity is visible.
      if (values.isEmpty) return '';
      // Include the active operator to avoid reusing a route verdict after
      // a SIM/carrier handoff that happens to retain the same local address.
      return sha256.convert(utf8.encode('$natOpKey|${values.join(';')}')).toString();
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
