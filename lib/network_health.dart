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
    // Confidence follows the evidence actually collected. Do not assume a
    // fixed probe count: scanners may add/remove targets over time.
    final domesticAttempts = domesticSamples > 0 ? domesticSamples : 0;
    final globalAttempts = globalSamples > 0 ? globalSamples : 0;
    final totalAttempts = domesticAttempts + globalAttempts;
    if (totalAttempts == 0) return 0;

    // Successful handshakes cannot exceed the number of recorded attempts.
    // Clamp each route independently so malformed counters cannot inflate
    // the confidence score or let one route hide missing evidence on the other.
    final domesticOk = domesticSuccesses < 0
        ? 0
        : domesticSuccesses > domesticAttempts
            ? domesticAttempts
            : domesticSuccesses;
    final globalOk = globalSuccesses < 0
        ? 0
        : globalSuccesses > globalAttempts
            ? globalAttempts
            : globalSuccesses;
    final successfulSamples = domesticOk + globalOk;
    final coverage = (successfulSamples / totalAttempts).clamp(0.0, 1.0);

    // TLS verification adds confidence only when that route has at least
    // one successful sample; a stale flag cannot validate an empty route.
    final verified = (domesticTlsReachabilityVerified && domesticOk > 0 ? 1 : 0) +
        (globalTlsReachabilityVerified && globalOk > 0 ? 1 : 0);
    return (coverage * (0.55 + verified * 0.225)).clamp(0.0, 1.0).toDouble();
  }
}


/// Conservative strategy selection with minimum evidence requirements.
/// Partial evidence preserves the last strategy instead of guessing.
PilotNetworkStrategy choosePilotNetworkStrategy(NetworkEvidence evidence) {
  // A single successful endpoint is only a hint (degraded), not enough to
  // change the active route. Require the scanner's >=2/3 quorum on each side.
  final domesticConfirmed = evidence.domestic == LinkHealth.healthy &&
      evidence.domesticSamples >= 3;
  final globalConfirmed = evidence.global == LinkHealth.healthy &&
      evidence.globalSamples >= 3;
  final domesticFailed = evidence.domestic == LinkHealth.unreachable &&
      evidence.domesticSamples >= 2;
  final globalFailed = evidence.global == LinkHealth.unreachable &&
      evidence.globalSamples >= 2;

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
