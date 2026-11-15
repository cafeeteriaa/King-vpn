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

  /// Counts a stable run only after 5 minutes on the same server. [stillSame] is
  /// re-checked when the timer fires, so a dropped tunnel never gets counted.
  static void armStable(String endpointKey, bool Function() stillSame) {
    _stableTimer?.cancel();
    _stableTimer = Timer(const Duration(minutes: 5), () {
      _stableTimer = null;
      if (!stillSame()) return;
      unawaited(recordStable(endpointKey));
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
    final out = items.toList();
    out.sort((a, b) => scoreFor(key(b)).compareTo(scoreFor(key(a))));
    return out;
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

  static NatNetworkClass current = NatNetworkClass.unknown;
  static DateTime? _checkedAt;
  static String? _identityAtCheck;
  static bool _running = false;

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

  static Future<NatNetworkClass> refresh({bool force = false}) async {
    if (_running) return current;
    final at = _checkedAt;
    final id = await _identityHash();
    if (!force && at != null && id == _identityAtCheck &&
        DateTime.now().difference(at) < _ttl) {
      return current;
    }
    _running = true;
    try {
      final domesticTcp = await Future.wait(_domesticHosts.map(_tcpOk));
      final globalTcp = await Future.wait(_globalHosts.map(_tcpOk));
      final globalDns = await Future.wait(_globalResolvers.map(
          (r) => NatDnsWireProbe.probe(r, 'google.com').then((x) => x.ok)));
      final ev = NatProbeEvidence(
        domesticDnsOk: false, // no domestic resolver probe is configured yet
        domesticTcpOk: domesticTcp.any((x) => x),
        globalDnsOk: globalDns.any((x) => x),
        globalTcpOk: globalTcp.any((x) => x),
        sampleCount: domesticTcp.length + globalTcp.length + globalDns.length,
      );
      current = ev.classify();
      _checkedAt = DateTime.now();
      _identityAtCheck = id;
      dbg('NNIE-DIAG: ${natNetworkClassLabel(current)} '
          '(domesticTcp=${ev.domesticTcpOk} globalTcp=${ev.globalTcpOk} globalDns=${ev.globalDnsOk})');
    } catch (e, st) {
      logError(e, st);
      current = NatNetworkClass.unknown;
    } finally {
      _running = false;
    }
    return current;
  }
}

String natNetworkClassLabel(NatNetworkClass value) => switch (value) {
      NatNetworkClass.globalReachable => 'دسترسی جهانی برقرار',
      NatNetworkClass.domesticOnlyLikely => 'احتمالاً فقط مسیرهای داخلی فعال‌اند',
      NatNetworkClass.dnsDegraded => 'اختلال یا دست‌کاری DNS محتمل است',
      NatNetworkClass.transportRestricted => 'محدودیت مسیر یا پروتکل محتمل است',
      NatNetworkClass.unknown => 'وضعیت شبکه نامشخص است',
    };
