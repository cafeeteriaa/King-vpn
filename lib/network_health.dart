/// Independent domestic/global network evidence model for Smart Pilot ∞.
enum LinkHealth { unknown, healthy, degraded, unreachable }
enum DetectedNetworkMode { unknown, domesticOnly, globalOnly, dualReachable, offline }

/// Internal route selected by the single Smart Pilot controller.
enum PilotNetworkStrategy { domestic, global, preserve, offline }

/// Reuse probe evidence only when its network identity is known and its age
/// is within the TTL. An unavailable identity or a backwards clock must force
/// a fresh probe rather than reusing potentially stale routing evidence.
bool shouldReuseNetworkProbeCache({
  required bool force,
  required String currentIdentity,
  required String? cachedIdentity,
  required DateTime? checkedAt,
  required DateTime now,
  required Duration ttl,
}) {
  if (force || currentIdentity.isEmpty || cachedIdentity == null ||
      cachedIdentity.isEmpty || currentIdentity != cachedIdentity ||
      checkedAt == null) {
    return false;
  }
  final age = now.difference(checkedAt);
  return age >= Duration.zero && age < ttl;
}

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
    // This is geographic endpoint reachability, not IPv4/IPv6 dual-stack support.
    if (domesticUp && globalUp) return DetectedNetworkMode.dualReachable;
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
    // Treat the evidence object as an external boundary: malformed counters
    // must not claim more successes than the scanner actually sampled.
    final domesticCount = domesticSamples < 0 ? 0 : domesticSamples;
    final globalCount = globalSamples < 0 ? 0 : globalSamples;
    final domesticOk = domesticSuccesses.clamp(0, domesticCount);
    final globalOk = globalSuccesses.clamp(0, globalCount);
    final successfulSamples = (domesticOk + globalOk).clamp(0, 6);
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
  // A single successful endpoint is only a hint (degraded), not enough to
  // change the active route. Require the scanner's >=2/3 quorum on each side.
  final domesticConfirmed = evidence.domestic == LinkHealth.healthy &&
      evidence.domesticSamples >= 3 &&
      evidence.domesticSuccesses >= 2 &&
      evidence.domesticTlsReachabilityVerified;
  final globalConfirmed = evidence.global == LinkHealth.healthy &&
      evidence.globalSamples >= 3 &&
      evidence.globalSuccesses >= 2 &&
      evidence.globalTlsReachabilityVerified;
  final domesticFailed = evidence.domestic == LinkHealth.unreachable &&
      evidence.domesticSamples >= 2 &&
      evidence.domesticSuccesses == 0;
  final globalFailed = evidence.global == LinkHealth.unreachable &&
      evidence.globalSamples >= 2 &&
      evidence.globalSuccesses == 0;

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
