/// Verified, finite connection pipeline shared by discovery, config repair,
/// network-identity adapters and the final connection attempt.
///
/// This layer deliberately knows nothing about a particular VPN core. Adapters
/// must supply protocol-aware operations and real data-plane evidence.
enum KingPipelinePhase {
  beforeIdentity,
  identity,
  afterIdentity,
  beforeConnect,
}

class KingTrafficProof {
  const KingTrafficProof({
    required this.tunnelObserved,
    required this.destinationMatched,
    required this.applicationResponseValidated,
    required this.protocolCompatible,
    required this.bytesSent,
    required this.bytesReceived,
  });

  final bool tunnelObserved;
  final bool destinationMatched;
  final bool applicationResponseValidated;
  final bool protocolCompatible;
  final int bytesSent;
  final int bytesReceived;

  /// CONNECTED, TCP-open, DNS-only and ping-only results are insufficient.
  bool get isRealTrafficSuccess =>
      tunnelObserved &&
      destinationMatched &&
      applicationResponseValidated &&
      protocolCompatible &&
      bytesSent > 0 &&
      bytesReceived > 0;
}

class KingConfigCandidate {
  const KingConfigCandidate({
    required this.scannerId,
    required this.field,
    required this.value,
    this.score = 0,
    this.protocols = const <String>{},
  });

  final String scannerId;
  final String field;
  final Object value;
  final double score;
  final Set<String> protocols;

  bool get isWellFormed =>
      scannerId.trim().isNotEmpty && field.trim().isNotEmpty;
}

class KingFeatureCandidate {
  const KingFeatureCandidate({
    required this.id,
    required this.phase,
    required this.supportsCurrentProtocol,
    required this.apply,
    required this.rollback,
    this.score = 0,
  });

  final String id;
  final KingPipelinePhase phase;
  final bool supportsCurrentProtocol;
  final double score;
  final Future<void> Function() apply;
  final Future<void> Function() rollback;
}

class KingPipelineScanner {
  const KingPipelineScanner({
    required this.id,
    required this.discover,
  });

  final String id;
  final Future<List<KingConfigCandidate>> Function() discover;
}

typedef KingPipelineProofProvider = Future<KingTrafficProof> Function();
typedef KingPipelineStop = bool Function();

class KingConnectionPipelineResult {
  const KingConnectionPipelineResult({
    required this.acceptedFields,
    required this.acceptedFeatures,
    required this.rejectedCandidates,
    required this.connected,
    required this.cancelled,
  });

  final List<String> acceptedFields;
  final List<String> acceptedFeatures;
  final List<String> rejectedCandidates;
  final bool connected;
  final bool cancelled;
}

/// Runs scanners serially, accepts a config field only after a real tunnel
/// transaction, then evaluates optional features in explicit phases. Every
/// unsuccessful mutation is rolled back before the next candidate is tried.
class KingConnectionPipeline {
  bool _running = false;
  bool get isRunning => _running;

  Future<KingConnectionPipelineResult> run({
    required List<KingPipelineScanner> scanners,
    required Future<void> Function(KingConfigCandidate candidate) applyConfig,
    required Future<void> Function(KingConfigCandidate candidate) rollbackConfig,
    required List<KingFeatureCandidate> Function() featureCandidates,
    required KingPipelineProofProvider verifyTraffic,
    required Future<void> Function() connect,
    required KingPipelineStop shouldStop,
  }) async {
    if (_running) {
      throw StateError('A KING connection pipeline is already running.');
    }
    _running = true;
    final acceptedFields = <String>[];
    final acceptedFeatures = <String>[];
    final rejected = <String>[];
    final committedFields = <String>{};
    var connected = false;
    var cancelled = false;

    bool halted() => shouldStop();

    Future<bool> hasProof() async {
      if (halted()) return false;
      try {
        return (await verifyTraffic()).isRealTrafficSuccess && !halted();
      } catch (_) {
        return false;
      }
    }

    try {
      // Stage 1: independent scanners. Each scanner owns discovery; the
      // coordinator serializes execution and prevents competing mutations.
      for (final scanner in scanners) {
        if (halted()) {
          cancelled = true;
          break;
        }
        if (scanner.id.trim().isEmpty) {
          rejected.add('scanner:invalid-id');
          continue;
        }
        List<KingConfigCandidate> candidates;
        try {
          candidates = await scanner.discover();
        } catch (_) {
          rejected.add('scanner:${scanner.id}:discovery-error');
          continue;
        }
        candidates.sort((a, b) => b.score.compareTo(a.score));
        for (final candidate in candidates) {
          if (halted()) {
            cancelled = true;
            break;
          }
          if (!candidate.isWellFormed ||
              candidate.scannerId != scanner.id ||
              committedFields.contains(candidate.field)) {
            rejected.add('${scanner.id}:${candidate.field}:invalid-or-already-set');
            continue;
          }
          var applied = false;
          try {
            await applyConfig(candidate);
            applied = true;
            if (await hasProof()) {
              committedFields.add(candidate.field);
              acceptedFields.add(candidate.field);
              continue;
            }
          } catch (_) {
            // The rollback below restores the last known-good config.
          }
          if (applied) {
            try {
              await rollbackConfig(candidate);
            } catch (_) {
              rejected.add('${scanner.id}:${candidate.field}:rollback-error');
            }
          }
          rejected.add('${scanner.id}:${candidate.field}:no-real-traffic-proof');
        }
        if (cancelled) break;
      }

      // Stage 2: useful capabilities. Adapters declare their correct phase;
      // unsupported protocol features are never applied to the active config.
      if (!cancelled && !halted()) {
        final features = featureCandidates()
            .where((feature) =>
                feature.id.trim().isNotEmpty &&
                feature.supportsCurrentProtocol)
            .toList()
          ..sort((a, b) {
            final phase = a.phase.index.compareTo(b.phase.index);
            return phase != 0 ? phase : b.score.compareTo(a.score);
          });
        for (final feature in features) {
          if (halted()) {
            cancelled = true;
            break;
          }
          var applied = false;
          try {
            await feature.apply();
            applied = true;
            if (await hasProof()) {
              acceptedFeatures.add(feature.id);
              continue;
            }
          } catch (_) {
            // Failed adapters are rolled back before another one is tried.
          }
          if (applied) {
            try {
              await feature.rollback();
            } catch (_) {
              rejected.add('feature:${feature.id}:rollback-error');
            }
          }
          rejected.add('feature:${feature.id}:no-real-traffic-proof');
        }
      }

      // Stage 3: start the final selected configuration and prove the data
      // plane once more. A successful start without traffic is not connected.
      if (!cancelled && !halted()) {
        try {
          await connect();
          connected = await hasProof();
          if (!connected) rejected.add('connect:no-real-traffic-proof');
        } catch (_) {
          rejected.add('connect:start-error');
        }
      } else {
        cancelled = true;
      }

      return KingConnectionPipelineResult(
        acceptedFields: List.unmodifiable(acceptedFields),
        acceptedFeatures: List.unmodifiable(acceptedFeatures),
        rejectedCandidates: List.unmodifiable(rejected),
        connected: connected,
        cancelled: cancelled,
      );
    } finally {
      _running = false;
    }
  }
}
