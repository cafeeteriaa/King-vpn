part of 'main.dart';

// King VPN - National Network Intelligence Engine (NNIE)
// This module is deliberately additive: it records evidence and ranks candidates;
// it does not rewrite a V2Ray URI or claim that a probe proves tunnel reachability.

/// Complete, privacy-preserving history. Only a SHA-256 key is persisted, never
/// the raw V2Ray link, UUID, password, server name, or full endpoint string.
class NationalNetworkIntelligence {
  static const String _prefsKey = 'nnie_profiles_v2'; // Legacy migration source; new writes use the disk snapshot.
  static Future<void> _saveTail = Future<void>.value();
  static Map<String, NatEndpointMemory> _memory = <String, NatEndpointMemory>{};
  static bool _loaded = false;
  static Future<void>? _loading;

  static Future<void> load() async {
    if (_loaded) return;
    _loading ??= _loadImpl();
    await _loading;
  }

  static Future<File> _evidenceFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/king_nat_strategy_evidence_v1.json');
  }

  static Future<void> _loadImpl() async {
    try {
      File? file;
      String? raw;
      try {
        file = await _evidenceFile();
        if (await file.exists()) raw = await file.readAsString();
      } catch (e, st) {
        // Preserve the legacy preferences fallback if path-provider is
        // temporarily unavailable (e.g. during early Android startup).
        logError(e, st);
      }
      if (raw == null || raw.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        raw = prefs.getString(_prefsKey);
      }
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _memory = <String, NatEndpointMemory>{};
          for (final e in decoded.entries) {
            if (e.key is String) {
              _memory[e.key as String] = NatEndpointMemory.fromJson(e.value);
            }
          }
          if (file != null && !await file.exists()) await _save();
        }
      }
    } catch (e, st) {
      logError(e, st);
    } finally {
      _loaded = true;
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
    final attempts = old.attempts + 1;
    final successes = min(attempts, old.successes + (success ? 1 : 0));
    final ewma = success
        ? (old.ewmaConnectMs <= 0 ? elapsedMs.toDouble() : old.ewmaConnectMs * 0.75 + elapsedMs * 0.25)
        : old.ewmaConnectMs;
    _memory[endpointKey] = NatEndpointMemory(
      attempts: attempts,
      successes: successes,
      failStreak: success ? 0 : old.failStreak + 1,
      ewmaConnectMs: ewma,
      lastSuccessMs: success ? DateTime.now().millisecondsSinceEpoch : old.lastSuccessMs,
      stableSuccesses: stableForFiveMinutes ? old.stableSuccesses + 1 : old.stableSuccesses,
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
      stableSuccesses: old.stableSuccesses + 1,
    );
    await _save();
  }

  static Future<void> _save() {
    final next = _saveTail.then((_) async {
      final file = await _evidenceFile();
      final temporary = File('${file.path}.tmp');
      final snapshot = jsonEncode(
        _memory.map((key, value) => MapEntry(key, value.toJson())),
      );
      await temporary.writeAsString(snapshot, flush: true);
      await temporary.rename(file.path);
    });
    _saveTail = next.catchError((Object error, StackTrace stack) {
      logError(error, stack);
    });
    return next;
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
  // Re-evaluate more frequently so a mobile carrier route change is not
  // hidden behind a long-lived classification cache.
  static const Duration _ttl = Duration(minutes: 2);
  static const List<String> _domesticHosts = <String>[
    'www.aparat.com',
    'www.digikala.com',
    'divar.ir',
    'www.snapp.ir',
    'www.tsetmc.com',
  ];
  static const List<String> _globalHosts = <String>[
    'www.google.com',
    'www.cloudflare.com',
    'github.com',
    'www.wikipedia.org',
    'www.microsoft.com',
  ];
  static const List<String> _globalResolvers = <String>[
    '8.8.8.8',
    '1.1.1.1',
    '9.9.9.9',
  ];
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

  /// A TCP SYN/ACK is not enough to call a route reachable. Complete a
  /// certificate-validated TLS handshake against the intended hostname.
  static Future<bool> _tlsOk(String host) async {
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(
        host,
        443,
        timeout: const Duration(seconds: 4),
      );
      return socket.peerCertificate != null;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// Used only as a secondary DNS-answer diagnostic. It is deliberately not
  /// treated as proof that the hostname's HTTPS service is healthy.
  static Future<bool> _tcpOpen(String host) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        443,
        timeout: const Duration(seconds: 3),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
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
      if (!force && at != null && id == _identityAtCheck &&
          DateTime.now().difference(at) < _ttl) {
        return current;
      }
      // All probes start together. Awaiting the groups one after another made
      // the total time the SUM of their timeouts (a black-holed TCP connect
      // waits the full timeout), so the caller's deadline usually expired first.
      final domesticF = Future.wait(_domesticHosts.map(_tlsOk));
      final globalF = Future.wait(_globalHosts.map(_tlsOk));
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
      final domesticTcpOk = domesticTcp.where((x) => x).length >= 2;
      final globalTcpOk = globalTcp.any((x) => x);
      // DNS poisoning / blockpage check: a resolver returned a public A answer,
      // yet none of the answered addresses accepts TCP/443, while domestic hosts
      // do. That is the typical signature of an injected answer, not a live Google.
      var poison = false;
      if (globalDnsOk && !globalTcpOk && domesticTcpOk) {
        final answered = [
          for (final r in globalDnsRes) if (r.ok) ...r.addresses,
        ].toSet().take(2).toList();
        final reach = await Future.wait(answered.map(_tcpOpen));
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
          '(domesticTls=${domesticTcp.where((x) => x).length}/${domesticTcp.length} '
          'domesticDns=$domesticDnsOk globalTls=${globalTcp.where((x) => x).length}/${globalTcp.length} '
          'globalDns=${ev.globalDnsOk} poison=$poison)');
    } catch (e, st) {
      logError(e, st);
      current = NatNetworkClass.unknown;
    } finally {
      _running = false;
    }
    return current;
  }
}

/// Dedicated Smart Pilot link scanner. It verifies TLS handshakes against
/// fixed HTTPS targets and combines an independent IPv6 path probe. Its target
/// inventory is separate from general DNS/IP/SNI scanners; it never sweeps subnets.
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
    if (!force && lastAt != null && identity == _lastIdentity &&
        DateTime.now().difference(lastAt) < const Duration(minutes: 2)) {
      return _last;
    }
    final domesticFuture = Future.wait(domesticTargets.map(_probeHttps));
    final globalFuture = Future.wait(globalTargets.map(_probeHttps));
    final domestic = await domesticFuture;
    final global = await globalFuture;
    // IPv6 path probes are independent of the TLS quorum. They can veto a
    // false "offline/domestic-only" inference, but never count as TLS success.
    final ipv6 = await PilotIpv6Probe.refresh(force: force);
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
      domesticIpv6Successes: ipv6.domesticIpv6Successes,
      globalIpv6Successes: ipv6.globalIpv6Successes,
      domesticIpv6LatencyMs: ipv6.domesticIpv6LatencyMs,
      globalIpv6LatencyMs: ipv6.globalIpv6LatencyMs,
    );
    _lastAt = DateTime.now();
    _lastIdentity = identity;
    dbg('PILOT-TLS-PROBE: domestic=${domestic.whereType<int>().length}/${domestic.length} '
        'global=${global.whereType<int>().length}/${global.length} '
        'latencyDomestic=${_median(domestic)}ms latencyGlobal=${_median(global)}ms '
        'ipv6Domestic=${ipv6.domesticIpv6Successes} ipv6Global=${ipv6.globalIpv6Successes}');
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

/// IPv6 reachability is deliberately independent from the TLS route quorum.
/// A successful IPv6 TCP connect is path evidence only, not proof of HTTPS or
/// successful VPN tunnel traffic.
class PilotIpv6Evidence {
  const PilotIpv6Evidence({
    this.domesticIpv6Successes = 0,
    this.globalIpv6Successes = 0,
    this.domesticIpv6LatencyMs,
    this.globalIpv6LatencyMs,
  });

  final int domesticIpv6Successes;
  final int globalIpv6Successes;
  final int? domesticIpv6LatencyMs;
  final int? globalIpv6LatencyMs;

  Map<String, Object?> toMap() => <String, Object?>{
    'domesticIpv6Successes': domesticIpv6Successes,
    'globalIpv6Successes': globalIpv6Successes,
    'domesticIpv6LatencyMs': domesticIpv6LatencyMs,
    'globalIpv6LatencyMs': globalIpv6LatencyMs,
  };
}

class PilotIpv6Probe {
  static const Duration _timeout = Duration(milliseconds: 2600);
  static DateTime? _lastAt;
  static String? _lastIdentity;
  static PilotIpv6Evidence _last = const PilotIpv6Evidence();
  static Future<PilotIpv6Evidence>? _flight;

  static PilotIpv6Evidence get current => _last;

  static Future<PilotIpv6Evidence> refresh({bool force = false}) async {
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

  static Future<PilotIpv6Evidence> _refresh({required bool force}) async {
    final identity = await PilotNetworkProbe._networkIdentity();
    final lastAt = _lastAt;
    if (!force && lastAt != null && identity == _lastIdentity &&
        DateTime.now().difference(lastAt) < const Duration(minutes: 2)) {
      return _last;
    }
    final domesticFuture = Future.wait(
      PilotNetworkProbe.domesticTargets.map(_probeIpv6),
    );
    final globalFuture = Future.wait(
      PilotNetworkProbe.globalTargets.map(_probeIpv6),
    );
    final domestic = await domesticFuture;
    final global = await globalFuture;
    _last = PilotIpv6Evidence(
      domesticIpv6Successes: domestic.whereType<int>().length,
      globalIpv6Successes: global.whereType<int>().length,
      domesticIpv6LatencyMs: _median(domestic),
      globalIpv6LatencyMs: _median(global),
    );
    _lastAt = DateTime.now();
    _lastIdentity = identity;
    dbg('PILOT-IPV6-PROBE: domestic=${_last.domesticIpv6Successes}/${domestic.length} '
        'global=${_last.globalIpv6Successes}/${global.length} '
        'latencyDomestic=${_last.domesticIpv6LatencyMs}ms '
        'latencyGlobal=${_last.globalIpv6LatencyMs}ms');
    return _last;
  }

  static Future<int?> _probeIpv6(String host) async {
    final watch = Stopwatch()..start();
    try {
      final addresses = await InternetAddress.lookup(
        host,
        type: InternetAddressType.IPv6,
      ).timeout(_timeout);
      for (final address in addresses) {
        if (address.type != InternetAddressType.IPv6) continue;
        Socket? socket;
        try {
          socket = await Socket.connect(address, 443, timeout: _timeout);
          watch.stop();
          return watch.elapsedMilliseconds;
        } catch (_) {
          // Try another AAAA address for the same endpoint.
        } finally {
          socket?.destroy();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static int? _median(List<int?> values) {
    final sorted = values.whereType<int>().toList()..sort();
    return sorted.isEmpty ? null : sorted[sorted.length ~/ 2];
  }
}

NetworkEvidence currentPilotNetworkEvidence() =>
    PilotNetworkProbe.current.withIpv6Evidence(
      domesticIpv6Successes: PilotIpv6Probe.current.domesticIpv6Successes,
      globalIpv6Successes: PilotIpv6Probe.current.globalIpv6Successes,
      domesticIpv6LatencyMs: PilotIpv6Probe.current.domesticIpv6LatencyMs,
      globalIpv6LatencyMs: PilotIpv6Probe.current.globalIpv6LatencyMs,
    );

Future<NetworkEvidence> refreshPilotNetworkEvidence({bool force = false}) async {
  final samples = await Future.wait<Object>(<Future<Object>>[
    PilotNetworkProbe.refresh(force: force),
    PilotIpv6Probe.refresh(force: force),
  ]);
  final route = samples[0] as NetworkEvidence;
  final ipv6 = samples[1] as PilotIpv6Evidence;
  return route.withIpv6Evidence(
    domesticIpv6Successes: ipv6.domesticIpv6Successes,
    globalIpv6Successes: ipv6.globalIpv6Successes,
    domesticIpv6LatencyMs: ipv6.domesticIpv6LatencyMs,
    globalIpv6LatencyMs: ipv6.globalIpv6LatencyMs,
  );
}

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
