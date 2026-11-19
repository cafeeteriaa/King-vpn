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
    this.domesticLatencyMs,
    this.globalLatencyMs,
    this.domesticDataPlaneVerified = false,
    this.globalDataPlaneVerified = false,
  });

  final LinkHealth domestic;
  final LinkHealth global;
  final int domesticSamples;
  final int globalSamples;
  final int? domesticLatencyMs;
  final int? globalLatencyMs;
  final bool domesticDataPlaneVerified;
  final bool globalDataPlaneVerified;

  DetectedNetworkMode get mode {
    if (domestic == LinkHealth.unknown && global == LinkHealth.unknown) {
      return DetectedNetworkMode.unknown;
    }
    final domesticUp = domestic == LinkHealth.healthy || domestic == LinkHealth.degraded;
    final globalUp = global == LinkHealth.healthy || global == LinkHealth.degraded;
    if (!domesticUp && !globalUp) return DetectedNetworkMode.offline;
    if (domesticUp && globalUp) return DetectedNetworkMode.dualStack;
    if (domesticUp) return DetectedNetworkMode.domesticOnly;
    return DetectedNetworkMode.globalOnly;
  }

  /// Health of one address family must not be inferred from the other.
  bool acceptsTunnel({required bool nationalOnly}) =>
      nationalOnly ? domesticDataPlaneVerified : globalDataPlaneVerified;

  double get confidence {
    final sampleCount = domesticSamples + globalSamples;
    if (sampleCount <= 0) return 0;
    final coverage = (sampleCount / 8).clamp(0, 1).toDouble();
    final verified = (domesticDataPlaneVerified ? 1 : 0) +
        (globalDataPlaneVerified ? 1 : 0);
    return (coverage * (0.55 + verified * 0.225)).clamp(0, 1).toDouble();
  }
}


/// Conservative strategy selection with minimum evidence requirements.
/// Partial evidence preserves the last strategy instead of guessing.
PilotNetworkStrategy choosePilotNetworkStrategy(NetworkEvidence evidence) {
  final domesticUsable = evidence.domestic == LinkHealth.healthy ||
      evidence.domestic == LinkHealth.degraded;
  final globalUsable = evidence.global == LinkHealth.healthy ||
      evidence.global == LinkHealth.degraded;
  final domesticConfirmed = domesticUsable && evidence.domesticSamples >= 2;
  final globalConfirmed = globalUsable && evidence.globalSamples >= 2;
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
