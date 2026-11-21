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


/// Bounded persistent aggregate route history for coarse network groups.
/// Only interface type and public ASN are stored; IPs, SSIDs, SIM identifiers,
/// VPN links, server names and credentials are deliberately excluded.
class PilotRouteHistory {
  static const String _prefsKey = 'pilot_route_history_v1';
  static const int _maxGroups = 64;
  static final Map<String, Map<String, Object?>> _entries = {};
  static bool _loaded = false;
  static Future<void>? _loading;
  static Future<void> _writeQueue = Future<void>.value();

  static bool _validGroup(String value) {
    if (value == 'wifi' || value == 'mob' || value == 'net') return true;
    final parts = value.split('|');
    if (parts.length != 2) return false;
    if (!['wifi', 'mob', 'net'].contains(parts[0])) return false;
    if (!parts[1].startsWith('AS')) return false;
    final asn = int.tryParse(parts[1].substring(2));
    return asn != null && asn >= 100 && asn <= 9999999;
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
            if (item.key is! String || !_validGroup(item.key as String) || item.value is! Map) continue;
            final value = <String, Object?>{};
            (item.value as Map).forEach((key, rawValue) {
              if (key is String && (rawValue is num || rawValue is String)) {
                value[key] = rawValue;
              }
            });
            _entries[item.key as String] = value;
          }
        }
      }
    } catch (_) {
      // Retry on next access if storage is temporarily unavailable.
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
      final updated = <String, Object?>{
        'observations': (count('observations') + 1).clamp(0, 1000000),
        'domesticSamples': (count('domesticSamples') + evidence.domesticSamples).clamp(0, 1000000),
        'domesticSuccesses': (count('domesticSuccesses') + evidence.domesticSuccesses).clamp(0, 1000000),
        'globalSamples': (count('globalSamples') + evidence.globalSamples).clamp(0, 1000000),
        'globalSuccesses': (count('globalSuccesses') + evidence.globalSuccesses).clamp(0, 1000000),
        'domesticLatencyEwmaMs': ewma('domesticLatencyEwmaMs', evidence.domesticLatencyMs),
        'globalLatencyEwmaMs': ewma('globalLatencyEwmaMs', evidence.globalLatencyMs),
        'domesticOnly': count('domesticOnly') + (mode == 'domesticOnly' ? 1 : 0),
        'globalOnly': count('globalOnly') + (mode == 'globalOnly' ? 1 : 0),
        'dualStack': count('dualStack') + (mode == 'dualStack' ? 1 : 0),
        'offline': count('offline') + (mode == 'offline' ? 1 : 0),
        'unknown': count('unknown') + (mode == 'unknown' ? 1 : 0),
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      };
      _entries[networkGroup] = updated;
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
      } catch (_) {
        // Keep in-memory evidence and retry persistence on the next sample.
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
