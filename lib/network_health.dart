import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Independent domestic/global network evidence model for Smart Pilot ∞.
enum LinkHealth { unknown, healthy, degraded, unreachable }
enum DetectedNetworkMode { unknown, domesticOnly, globalOnly, dualStack, offline }

/// Internal route selected by the single Smart Pilot controller.
enum PilotNetworkStrategy { domestic, global, preserve, offline }

class NetworkEvidence {
  const NetworkEvidence({
    required this.domestic,
    required this.global,
    this.domesticSamples = 0,
    this.globalSamples = 0,
    this.domesticSuccesses = 0,
    this.globalSuccesses = 0,
    this.domesticLatencyMs,
    this.globalLatencyMs,
    this.domesticTlsReachabilityVerified = false,
    this.globalTlsReachabilityVerified = false,
  });

  final LinkHealth domestic;
  final LinkHealth global;
  final int domesticSamples;
  final int globalSamples;
  final int domesticSuccesses;
  final int globalSuccesses;
  final int? domesticLatencyMs;
  final int? globalLatencyMs;
  final bool domesticTlsReachabilityVerified;
  final bool globalTlsReachabilityVerified;

  DetectedNetworkMode get mode {
    if (domestic == LinkHealth.unknown && global == LinkHealth.unknown) {
      return DetectedNetworkMode.unknown;
    }
    // A degraded group means only one endpoint responded; do not label it
    // as a confirmed network class or infer the other side is unavailable.
    if (domestic == LinkHealth.degraded || global == LinkHealth.degraded) {
      return DetectedNetworkMode.unknown;
    }
    final domesticUp = domestic == LinkHealth.healthy;
    final globalUp = global == LinkHealth.healthy;
    if (!domesticUp && !globalUp) {
      return domestic == LinkHealth.unreachable && global == LinkHealth.unreachable
          ? DetectedNetworkMode.offline
          : DetectedNetworkMode.unknown;
    }
    if (domesticUp && globalUp) return DetectedNetworkMode.dualStack;
    if (domesticUp && global == LinkHealth.unreachable) return DetectedNetworkMode.domesticOnly;
    if (globalUp && domestic == LinkHealth.unreachable) return DetectedNetworkMode.globalOnly;
    return DetectedNetworkMode.unknown;
  }

  /// TLS reachability is not proof that VPN tunnel traffic is passing.
  /// This helper reports only the matching endpoint group's TLS evidence.
  bool acceptsTlsReachability({required bool nationalOnly}) =>
      nationalOnly ? domesticTlsReachabilityVerified : globalTlsReachabilityVerified;

  double get confidence {
    // Count actual successful TLS handshakes, not attempts. Failed probes are
    // evidence for route classification but must never inflate reachability confidence.
    final successfulSamples = (domesticSuccesses + globalSuccesses).clamp(0, 6);
    if (successfulSamples <= 0) return 0;
    // The dedicated pilot scanner samples exactly three domestic and three global targets.
    // Six successful samples with both groups verified reach 100%.
    final coverage = (successfulSamples / 6).clamp(0, 1).toDouble();
    final verified = (domesticTlsReachabilityVerified ? 1 : 0) +
        (globalTlsReachabilityVerified ? 1 : 0);
    return (coverage * (0.55 + verified * 0.225)).clamp(0, 1).toDouble();
  }
}


/// Persisted aggregate route evidence for one coarse network group.
/// The group is limited to interface type + public ASN (for example mob|AS1234);
/// IP addresses, SIM identifiers, SSIDs, server links and credentials are never stored.
class PilotRouteHistoryEntry {
  const PilotRouteHistoryEntry({
    required this.networkGroup,
    this.observations = 0,
    this.domesticSamples = 0,
    this.domesticSuccesses = 0,
    this.globalSamples = 0,
    this.globalSuccesses = 0,
    this.domesticLatencyEwmaMs,
    this.globalLatencyEwmaMs,
    this.domesticOnly = 0,
    this.globalOnly = 0,
    this.dualStack = 0,
    this.offline = 0,
    this.unknown = 0,
    this.updatedAtMs = 0,
  });

  final String networkGroup;
  final int observations;
  final int domesticSamples;
  final int domesticSuccesses;
  final int globalSamples;
  final int globalSuccesses;
  final double? domesticLatencyEwmaMs;
  final double? globalLatencyEwmaMs;
  final int domesticOnly;
  final int globalOnly;
  final int dualStack;
  final int offline;
  final int unknown;
  final int updatedAtMs;

  factory PilotRouteHistoryEntry.fromJson(String group, Object? value) {
    if (value is! Map) throw const FormatException('Invalid route history entry');
    int number(String key) {
      final v = value[key];
      return v is num ? v.toInt().clamp(0, 1000000) : 0;
    }
    double? decimal(String key) {
      final v = value[key];
      if (v is! num || !v.isFinite || v < 0 || v > 60000) return null;
      return v.toDouble();
    }
    return PilotRouteHistoryEntry(
      networkGroup: group,
      observations: number('observations'),
      domesticSamples: number('domesticSamples'),
      domesticSuccesses: number('domesticSuccesses'),
      globalSamples: number('globalSamples'),
      globalSuccesses: number('globalSuccesses'),
      domesticLatencyEwmaMs: decimal('domesticLatencyEwmaMs'),
      globalLatencyEwmaMs: decimal('globalLatencyEwmaMs'),
      domesticOnly: number('domesticOnly'),
      globalOnly: number('globalOnly'),
      dualStack: number('dualStack'),
      offline: number('offline'),
      unknown: number('unknown'),
      updatedAtMs: number('updatedAtMs'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'observations': observations,
        'domesticSamples': domesticSamples,
        'domesticSuccesses': domesticSuccesses,
        'globalSamples': globalSamples,
        'globalSuccesses': globalSuccesses,
        'domesticLatencyEwmaMs': domesticLatencyEwmaMs,
        'globalLatencyEwmaMs': globalLatencyEwmaMs,
        'domesticOnly': domesticOnly,
        'globalOnly': globalOnly,
        'dualStack': dualStack,
        'offline': offline,
        'unknown': unknown,
        'updatedAtMs': updatedAtMs,
      };

  PilotRouteHistoryEntry observe(NetworkEvidence evidence, int nowMs) {
    double? ewma(double? old, int? sample) {
      if (sample == null || sample < 0 || sample > 60000) return old;
      return old == null ? sample.toDouble() : old * 0.75 + sample * 0.25;
    }

    int increment(int value) => (value + 1).clamp(0, 1000000);
    final nextMode = evidence.mode;
    return PilotRouteHistoryEntry(
      networkGroup: networkGroup,
      observations: increment(observations),
      domesticSamples: (domesticSamples + evidence.domesticSamples).clamp(0, 1000000),
      domesticSuccesses: (domesticSuccesses + evidence.domesticSuccesses).clamp(0, 1000000),
      globalSamples: (globalSamples + evidence.globalSamples).clamp(0, 1000000),
      globalSuccesses: (globalSuccesses + evidence.globalSuccesses).clamp(0, 1000000),
      domesticLatencyEwmaMs: ewma(domesticLatencyEwmaMs, evidence.domesticLatencyMs),
      globalLatencyEwmaMs: ewma(globalLatencyEwmaMs, evidence.globalLatencyMs),
      domesticOnly: nextMode == DetectedNetworkMode.domesticOnly ? increment(domesticOnly) : domesticOnly,
      globalOnly: nextMode == DetectedNetworkMode.globalOnly ? increment(globalOnly) : globalOnly,
      dualStack: nextMode == DetectedNetworkMode.dualStack ? increment(dualStack) : dualStack,
      offline: nextMode == DetectedNetworkMode.offline ? increment(offline) : offline,
      unknown: nextMode == DetectedNetworkMode.unknown ? increment(unknown) : unknown,
      updatedAtMs: nowMs,
    );
  }
}

/// Small persistent history keyed only by coarse interface type and public ASN.
/// It is advisory learning data; it never overrides fresh route evidence.
class PilotRouteHistory {
  static const String _prefsKey = 'pilot_route_history_v1';
  static const int _maxGroups = 64;
  static final Map<String, PilotRouteHistoryEntry> _entries = {};
  static bool _loaded = false;
  static Future<void>? _loading;
  static Future<void> _writeQueue = Future<void>.value();

  static bool _validGroup(String value) =>
      RegExp(r'^(wifi|mob|net)(\\|AS\\d{3,7})?/// Partial evidence preserves the last strategy instead of guessing.
PilotNetworkStrategy choosePilotNetworkStrategy(NetworkEvidence evidence) {
  // A route verdict must agree with the underlying counters. This prevents
  // stale, partial, or malformed evidence from steering the active mode.
  bool confirmed({
    required LinkHealth health,
    required int samples,
    required int successes,
    required bool tlsVerified,
  }) =>
      health == LinkHealth.healthy &&
      samples >= 3 &&
      successes >= 2 &&
      successes <= samples &&
      tlsVerified;

  bool failed({
    required LinkHealth health,
    required int samples,
    required int successes,
  }) =>
      health == LinkHealth.unreachable &&
      samples >= 2 &&
      successes == 0;

  final domesticConfirmed = confirmed(
    health: evidence.domestic,
    samples: evidence.domesticSamples,
    successes: evidence.domesticSuccesses,
    tlsVerified: evidence.domesticTlsReachabilityVerified,
  );
  final globalConfirmed = confirmed(
    health: evidence.global,
    samples: evidence.globalSamples,
    successes: evidence.globalSuccesses,
    tlsVerified: evidence.globalTlsReachabilityVerified,
  );
  final domesticFailed = failed(
    health: evidence.domestic,
    samples: evidence.domesticSamples,
    successes: evidence.domesticSuccesses,
  );
  final globalFailed = failed(
    health: evidence.global,
    samples: evidence.globalSamples,
    successes: evidence.globalSuccesses,
  );

  if (domesticConfirmed && globalFailed) return PilotNetworkStrategy.domestic;
  if (globalConfirmed && domesticFailed) return PilotNetworkStrategy.global;
  if (domesticConfirmed && globalConfirmed) {
    final domesticMs = evidence.domesticLatencyMs;
    final globalMs = evidence.globalLatencyMs;
    if (domesticMs != null && globalMs != null) {
      // Switch only for a material gain; avoid oscillation on tiny variations.
      if (domesticMs <= globalMs * 0.80 && globalMs - domesticMs >= 80) {
        return PilotNetworkStrategy.domestic;
      }
      if (globalMs <= domesticMs * 0.80 && domesticMs - globalMs >= 80) {
        return PilotNetworkStrategy.global;
      }
    }
    return PilotNetworkStrategy.preserve;
  }
  if (domesticConfirmed && !globalConfirmed && globalFailed) return PilotNetworkStrategy.domestic;
  if (globalConfirmed && !domesticConfirmed && domesticFailed) return PilotNetworkStrategy.global;
  if (domesticFailed && globalFailed) return PilotNetworkStrategy.offline;
  return PilotNetworkStrategy.preserve;
}
).hasMatch(value);

  static PilotRouteHistoryEntry? forNetwork(String group) => _entries[group];

  static List<PilotRouteHistoryEntry> get summaries => _entries.values.toList()
    ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));

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
            if (item.key is! String || !_validGroup(item.key as String)) continue;
            try {
              _entries[item.key as String] =
                  PilotRouteHistoryEntry.fromJson(item.key as String, item.value);
            } catch (_) {
              // Ignore one malformed record without discarding other groups.
            }
          }
        }
      }
    } catch (_) {
      // Retry on the next access if preferences are temporarily unavailable.
    } finally {
      _loaded = available;
      _loading = null;
    }
  }

  static Future<void> record({
    required String networkGroup,
    required NetworkEvidence evidence,
  }) {
    if (!_validGroup(networkGroup) ||
        evidence.domesticSamples < 3 ||
        evidence.globalSamples < 3 ||
        evidence.domesticSuccesses < 0 ||
        evidence.globalSuccesses < 0 ||
        evidence.domesticSuccesses > evidence.domesticSamples ||
        evidence.globalSuccesses > evidence.globalSamples) {
      return Future<void>.value();
    }
    final next = _writeQueue.then((_) async {
      await load();
      final old = _entries[networkGroup] ??
          PilotRouteHistoryEntry(networkGroup: networkGroup);
      _entries[networkGroup] = old.observe(
        evidence,
        DateTime.now().millisecondsSinceEpoch,
      );
      final ordered = _entries.values.toList()
        ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      if (ordered.length > _maxGroups) {
        _entries
          ..clear()
          ..addEntries(ordered.take(_maxGroups).map((e) => MapEntry(e.networkGroup, e)));
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _prefsKey,
          jsonEncode(_entries.map((key, value) => MapEntry(key, value.toJson()))),
        );
      } catch (_) {
        // In-memory evidence remains useful; persistence is retried next sample.
      }
    });
    _writeQueue = next.catchError((Object _) {});
    return next;
  }

  static Future<void> resetForTesting() async {
    _entries.clear();
    _loaded = false;
    _loading = null;
    _writeQueue = Future<void>.value();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}

/// Conservative strategy selection with minimum evidence requirements.
/// Partial evidence preserves the last strategy instead of guessing.
PilotNetworkStrategy choosePilotNetworkStrategy(NetworkEvidence evidence) {
  // A route verdict must agree with the underlying counters. This prevents
  // stale, partial, or malformed evidence from steering the active mode.
  bool confirmed({
    required LinkHealth health,
    required int samples,
    required int successes,
    required bool tlsVerified,
  }) =>
      health == LinkHealth.healthy &&
      samples >= 3 &&
      successes >= 2 &&
      successes <= samples &&
      tlsVerified;

  bool failed({
    required LinkHealth health,
    required int samples,
    required int successes,
  }) =>
      health == LinkHealth.unreachable &&
      samples >= 2 &&
      successes == 0;

  final domesticConfirmed = confirmed(
    health: evidence.domestic,
    samples: evidence.domesticSamples,
    successes: evidence.domesticSuccesses,
    tlsVerified: evidence.domesticTlsReachabilityVerified,
  );
  final globalConfirmed = confirmed(
    health: evidence.global,
    samples: evidence.globalSamples,
    successes: evidence.globalSuccesses,
    tlsVerified: evidence.globalTlsReachabilityVerified,
  );
  final domesticFailed = failed(
    health: evidence.domestic,
    samples: evidence.domesticSamples,
    successes: evidence.domesticSuccesses,
  );
  final globalFailed = failed(
    health: evidence.global,
    samples: evidence.globalSamples,
    successes: evidence.globalSuccesses,
  );

  if (domesticConfirmed && globalFailed) return PilotNetworkStrategy.domestic;
  if (globalConfirmed && domesticFailed) return PilotNetworkStrategy.global;
  if (domesticConfirmed && globalConfirmed) {
    final domesticMs = evidence.domesticLatencyMs;
    final globalMs = evidence.globalLatencyMs;
    if (domesticMs != null && globalMs != null) {
      // Switch only for a material gain; avoid oscillation on tiny variations.
      if (domesticMs <= globalMs * 0.80 && globalMs - domesticMs >= 80) {
        return PilotNetworkStrategy.domestic;
      }
      if (globalMs <= domesticMs * 0.80 && domesticMs - globalMs >= 80) {
        return PilotNetworkStrategy.global;
      }
    }
    return PilotNetworkStrategy.preserve;
  }
  if (domesticConfirmed && !globalConfirmed && globalFailed) return PilotNetworkStrategy.domestic;
  if (globalConfirmed && !domesticConfirmed && domesticFailed) return PilotNetworkStrategy.global;
  if (domesticFailed && globalFailed) return PilotNetworkStrategy.offline;
  return PilotNetworkStrategy.preserve;
}
