/// Independent domestic/global network evidence model for Smart Pilot ∞.
enum LinkHealth { unknown, healthy, degraded, unreachable }
/// Reachability classes for domestic and international endpoint groups.
/// `domesticAndGlobal` means both groups are reachable; it does NOT mean
/// that IPv4 and IPv6 were both verified (those require separate probes).
enum DetectedNetworkMode { unknown, domesticOnly, globalOnly, domesticAndGlobal, offline }

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
    if (domesticUp && globalUp) return DetectedNetworkMode.domesticAndGlobal;
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
