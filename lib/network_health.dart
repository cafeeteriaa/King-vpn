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


/// A probe snapshot is usable only when both identity reads succeeded and
/// refer to the same underlying network. Empty/changed identities invalidate
/// the whole sample; they are not interpreted as an outage.
bool sameKnownNetworkProbeIdentity(String before, String after) =>
    before.isNotEmpty && after.isNotEmpty && before == after;

/// A cached probe may guide routing only while its timestamp is trustworthy.
/// Reject future timestamps (clock rollback) and evidence at or beyond the TTL.
bool isNetworkProbeEvidenceFresh({
  required DateTime? checkedAt,
  required DateTime now,
  required Duration ttl,
}) {
  if (checkedAt == null || ttl <= Duration.zero) return false;
  final age = now.difference(checkedAt);
  return age >= Duration.zero && age < ttl;
}

/// Serializes network-probe refreshes and preserves a forced refresh request.
/// A forced caller arriving during a non-forced scan queues exactly one follow-up;
/// callers arriving during that follow-up share it instead of spawning more scans.
class NetworkProbeRefreshCoordinator<T> {
  Future<T>? _flight;
  Future<T>? _forcedFlight;
  bool _flightIsForced = false;

  Future<T> run(
    Future<T> Function({required bool force}) refresh, {
    bool force = false,
  }) {
    final active = _flight;
    if (active != null) {
      if (!force || _flightIsForced) return active;
      final pending = _forcedFlight;
      if (pending != null) return pending;

      late final Future<T> queued;
      queued = _runAfter(active, refresh).whenComplete(() {
        if (identical(_flight, queued)) {
          _flight = null;
          _flightIsForced = false;
        }
        if (identical(_forcedFlight, queued)) _forcedFlight = null;
      });
      // Publish the queued future immediately: later non-forced callers must
      // join the whole sequence, not slip into the gap between the two scans.
      _forcedFlight = queued;
      _flight = queued;
      _flightIsForced = true;
      return queued;
    }

    late final Future<T> flight;
    flight = refresh(force: force).whenComplete(() {
      if (identical(_flight, flight)) {
        _flight = null;
        _flightIsForced = false;
      }
    });
    _flight = flight;
    _flightIsForced = force;
    return flight;
  }

  Future<T> _runAfter(
    Future<T> active,
    Future<T> Function({required bool force}) refresh,
  ) async {
    // A failed ordinary scan must not cancel the explicit forced retry.
    try {
      await active;
    } catch (_) {
      // The forced scan below is the authoritative result for queued callers.
    }
    return refresh(force: true);
  }
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

  /// A positive route requires the same 2-of-3 TLS quorum used by the
  /// strategy controller. A caller cannot promote a hand-built/stale
  /// "healthy" label without matching sample counts and verified handshakes.
  bool get domesticConfirmed =>
      domestic == LinkHealth.healthy &&
      domesticSamples >= 3 &&
      domesticSuccesses >= 2 &&
      domesticSuccesses <= domesticSamples &&
      domesticTlsReachabilityVerified;

  bool get globalConfirmed =>
      global == LinkHealth.healthy &&
      globalSamples >= 3 &&
      globalSuccesses >= 2 &&
      globalSuccesses <= globalSamples &&
      globalTlsReachabilityVerified;

  /// A negative route requires at least two actual failed samples. Missing
  /// samples and inconsistent labels are unknown, never proof of blocking.
  bool get domesticFailed =>
      domestic == LinkHealth.unreachable &&
      domesticSamples >= 2 &&
      domesticSuccesses == 0;

  bool get globalFailed =>
      global == LinkHealth.unreachable &&
      globalSamples >= 2 &&
      globalSuccesses == 0;

  DetectedNetworkMode get mode {
    if (domesticConfirmed && globalConfirmed) {
      return DetectedNetworkMode.dualReachable;
    }
    if (domesticConfirmed && globalFailed) {
      return DetectedNetworkMode.domesticOnly;
    }
    if (globalConfirmed && domesticFailed) {
      return DetectedNetworkMode.globalOnly;
    }
    if (domesticFailed && globalFailed) {
      return DetectedNetworkMode.offline;
    }
    return DetectedNetworkMode.unknown;
  }

  /// TLS reachability is not proof that VPN tunnel traffic is passing.
  /// This helper reports only quorum-confirmed endpoint reachability.
  bool acceptsTlsReachability({required bool nationalOnly}) =>
      nationalOnly ? domesticConfirmed : globalConfirmed;

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
    final verified = (domesticConfirmed ? 1 : 0) +
        (globalConfirmed ? 1 : 0);
    return (coverage * (0.55 + verified * 0.225)).clamp(0, 1).toDouble();
  }
}


/// Conservative strategy selection with minimum evidence requirements.
/// Partial evidence preserves the last strategy instead of guessing.
PilotNetworkStrategy choosePilotNetworkStrategy(NetworkEvidence evidence) {
  // Share exactly the same evidence gates as the user-visible network mode.
  final domesticConfirmed = evidence.domesticConfirmed;
  final globalConfirmed = evidence.globalConfirmed;
  final domesticFailed = evidence.domesticFailed;
  final globalFailed = evidence.globalFailed;

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
  if (domesticFailed && globalFailed) return PilotNetworkStrategy.offline;
  return PilotNetworkStrategy.preserve;
}

/// Source/protocol learning must be isolated by route. Old unscoped profile
/// keys are intentionally not reused across domestic and global modes.
String networkScopedProfileKey(String profileKey, {required bool nationalMode}) =>
    '${nationalMode ? 'domestic' : 'global'}|$profileKey';

/// Domestic source ordering is enabled by the legacy diagnosis or by the
/// unified Pilot only when its domestic TLS quorum is confirmed.
bool shouldPreferDomesticCandidates({
  required bool legacyDiagnosisPrefersDomestic,
  required bool localPilotEnabled,
  required bool nationalMode,
  required bool pilotDomesticConfirmed,
}) =>
    legacyDiagnosisPrefersDomestic ||
    (localPilotEnabled && nationalMode && pilotDomesticConfirmed);
