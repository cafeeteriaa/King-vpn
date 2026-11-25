/// True only for a syntactically valid HTTP/1.x final response line.
/// Any final status (including 4xx/5xx) proves the TLS peer completed an
/// application-layer exchange; status alone is not interpreted as site health.
bool isValidHttpResponseLine(String line) =>
    RegExp(r'^HTTP/1\.[01]\s+([2-5][0-9]{2})(?:\s|$)').hasMatch(line.trim());

/// Reuse cached probe evidence only when its network identity and clock age
/// are trustworthy. Empty identities (interface lookup failure) and future
/// timestamps must force a fresh observation rather than freezing stale state.
bool isProbeCacheFresh({
  required bool force,
  required String currentIdentity,
  required String? cachedIdentity,
  required DateTime? cachedAt,
  required DateTime now,
  required Duration ttl,
}) {
  if (force || currentIdentity.isEmpty || cachedAt == null ||
      cachedIdentity != currentIdentity || ttl <= Duration.zero) {
    return false;
  }
  final age = now.difference(cachedAt);
  return age >= Duration.zero && age < ttl;
}

/// Canonical, order-independent representation of active interface addresses.
/// Empty entries are ignored; duplicate observations are preserved rather than
/// silently changing the source inventory.
String canonicalNetworkIdentity(Iterable<String> interfaceAddresses) {
  final values = interfaceAddresses
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList()
    ..sort();
  return values.join(';');
}

/// Builds a standards-compliant HTTP/1.1 HEAD request for the Smart Pilot
/// TLS reachability probe. CRLF delimiters are wire bytes, not backslash text.
String buildPilotHttpHeadRequest(String host) =>
    'HEAD / HTTP/1.1\r\n'
    'Host: $host\r\n'
    'User-Agent: KING-VPN-Pilot/1.0\r\n'
    'Connection: close\r\n\r\n';

/// Whether a concurrent Smart Pilot refresh may share an in-flight probe.
/// A forced request must not silently inherit a non-forced cached refresh.
bool shouldJoinInFlightProbe({
  required bool requestForce,
  required bool activeForced,
}) => !requestForce || activeForced;

/// Median of non-negative latency observations; null/invalid samples are ignored.
int? medianLatencyMs(Iterable<int?> values) {
  final sorted = values.whereType<int>().where((value) => value >= 0).toList()
    ..sort();
  if (sorted.isEmpty) return null;
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return ((sorted[middle - 1] + sorted[middle]) / 2).round();
}

/// Independent domestic/global network evidence model for Smart Pilot ∞.
enum LinkHealth { unknown, healthy, degraded, unreachable }
enum DetectedNetworkMode { unknown, domesticOnly, globalOnly, dualStack, offline }


/// Classifies one independent probe group without treating absent attempts as
/// failures. Only two or more actual successes establish a healthy group.
/// Two-thirds success quorum, with a minimum of two independent responses.
/// Integer arithmetic keeps the boundary deterministic for arbitrarily growing
/// endpoint inventories without imposing an inventory-size ceiling.
int requiredProbeSuccessQuorum(int attempted) {
  if (attempted <= 0) return 0;
  final twoThirds = (attempted * 2 + 2) ~/ 3;
  return twoThirds < 2 ? 2 : twoThirds;
}

LinkHealth classifyLinkHealth({
  required int attempted,
  required int successful,
}) {
  if (attempted <= 0) return LinkHealth.unknown;
  final observedSuccesses = successful.clamp(0, attempted).toInt();
  if (observedSuccesses >= requiredProbeSuccessQuorum(attempted)) {
    return LinkHealth.healthy;
  }
  if (observedSuccesses > 0) return LinkHealth.degraded;
  return LinkHealth.unreachable;
}

/// Checks that a group's label agrees with the actual attempt/success counts.
bool isProbeGroupEvidenceConsistent({
  required LinkHealth health,
  required int attempted,
  required int successful,
}) {
  if (attempted < 0 || successful < 0 || successful > attempted) return false;
  return classifyLinkHealth(attempted: attempted, successful: successful) == health;
}

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
    // A route class requires observations from both independent groups.
    // Empty/partial snapshots must never be promoted to an offline verdict.
    if (domesticSamples < 2 || globalSamples < 2 ||
        !isProbeGroupEvidenceConsistent(
          health: domestic,
          attempted: domesticSamples,
          successful: domesticSuccesses,
        ) ||
        !isProbeGroupEvidenceConsistent(
          health: global,
          attempted: globalSamples,
          successful: globalSuccesses,
        )) {
      return DetectedNetworkMode.unknown;
    }
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
    // Confidence is computed from observed success rates in each independent
    // group, not a fixed three-target inventory. This remains correct when
    // endpoint inventories grow or the number of completed probes varies.
    // Missing groups contribute zero coverage; malformed counters fail closed.
    if (domesticSamples < 0 ||
        globalSamples < 0 ||
        domesticSuccesses < 0 ||
        globalSuccesses < 0 ||
        domesticSuccesses > domesticSamples ||
        globalSuccesses > globalSamples) {
      return 0;
    }
    if (domesticSamples == 0 && globalSamples == 0) return 0;
    final domesticRate = domesticSamples == 0
        ? 0.0
        : domesticSuccesses / domesticSamples;
    final globalRate =
        globalSamples == 0 ? 0.0 : globalSuccesses / globalSamples;
    // Average both independent groups so an unobserved side cannot disappear
    // from the denominator and make one-sided evidence look fully certain.
    final coverage = ((domesticRate + globalRate) / 2).clamp(0, 1).toDouble();
    final verified =
        (domesticTlsReachabilityVerified && domesticSuccesses >= 2 ? 1 : 0) +
        (globalTlsReachabilityVerified && globalSuccesses >= 2 ? 1 : 0);
    return (coverage * (0.55 + verified * 0.225)).clamp(0, 1).toDouble();
  }
}


/// Conservative strategy selection with minimum evidence requirements.
/// Partial evidence preserves the last strategy instead of guessing.
PilotNetworkStrategy choosePilotNetworkStrategy(NetworkEvidence evidence) {
  // Never let contradictory labels/counters steer the user's route.
  if (!isProbeGroupEvidenceConsistent(
        health: evidence.domestic,
        attempted: evidence.domesticSamples,
        successful: evidence.domesticSuccesses,
      ) ||
      !isProbeGroupEvidenceConsistent(
        health: evidence.global,
        attempted: evidence.globalSamples,
        successful: evidence.globalSuccesses,
      )) {
    return PilotNetworkStrategy.preserve;
  }
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
