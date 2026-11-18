/// Independent domestic/global network evidence model for Smart Pilot ∞.
enum LinkHealth { unknown, healthy, degraded, unreachable }
enum DetectedNetworkMode { unknown, domesticOnly, globalOnly, dualStack, offline }

class NetworkEvidence {
  const NetworkEvidence({
    required this.domestic,
    required this.global,
    this.domesticSamples = 0,
    this.globalSamples = 0,
    this.domesticDataPlaneVerified = false,
    this.globalDataPlaneVerified = false,
  });

  final LinkHealth domestic;
  final LinkHealth global;
  final int domesticSamples;
  final int globalSamples;
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

  /// Global failure must never invalidate a proven domestic-only tunnel.
  bool acceptsTunnel({required bool nationalOnly}) {
    if (nationalOnly) return domesticDataPlaneVerified;
    return domesticDataPlaneVerified || globalDataPlaneVerified;
  }

  double get confidence {
    final sampleCount = domesticSamples + globalSamples;
    if (sampleCount <= 0) return 0;
    final coverage = (sampleCount / 8).clamp(0, 1).toDouble();
    final verified = (domesticDataPlaneVerified ? 1 : 0) +
        (globalDataPlaneVerified ? 1 : 0);
    return (coverage * (0.55 + verified * 0.225)).clamp(0, 1).toDouble();
  }
}
