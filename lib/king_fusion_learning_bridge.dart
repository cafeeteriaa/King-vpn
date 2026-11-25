import 'dart:collection';

import 'king_fusion_engine.dart';

/// Converts secret-free Fusion lifecycle events into compact KING AI evidence.
///
/// This is an observational bridge only: it does not execute recovery actions,
/// change VPN settings, persist event payloads, or access native handles/configs.
enum KingFusionRecoveryHint {
  observe,
  inspectEngine,
  verifyTraffic,
  retryCleanup,
}

class KingFusionLearningSnapshot {
  KingFusionLearningSnapshot({
    required this.lastSequence,
    required this.totalEvents,
    required this.failureEvents,
    required this.lastFailureCode,
    required this.recoveryHint,
    required Map<KingFusionEventType, int> eventCounts,
    required Map<String, int> consecutiveFailuresByEngine,
  })  : eventCounts = UnmodifiableMapView(
          Map<KingFusionEventType, int>.of(eventCounts),
        ),
        consecutiveFailuresByEngine = UnmodifiableMapView(
          Map<String, int>.of(consecutiveFailuresByEngine),
        );

  final int lastSequence;
  final int totalEvents;
  final int failureEvents;
  final String? lastFailureCode;
  final KingFusionRecoveryHint recoveryHint;
  final Map<KingFusionEventType, int> eventCounts;
  final Map<String, int> consecutiveFailuresByEngine;

  int get consecutiveFailureCount =>
      consecutiveFailuresByEngine.values.fold<int>(0, (sum, value) => sum + value);
}

class KingFusionLearningBridge {
  final Map<KingFusionEventType, int> _eventCounts =
      <KingFusionEventType, int>{};
  final Map<String, int> _failureStreaks = <String, int>{};

  int _lastSequence = 0;
  int _totalEvents = 0;
  int _failureEvents = 0;
  String? _lastFailureCode;
  KingFusionRecoveryHint _recoveryHint = KingFusionRecoveryHint.observe;

  /// Returns false for duplicate or out-of-order delivery.
  bool observe(KingFusionEvent event) {
    if (event.sequence <= _lastSequence) return false;

    _lastSequence = event.sequence;
    _totalEvents++;
    _eventCounts.update(event.type, (count) => count + 1, ifAbsent: () => 1);

    switch (event.type) {
      case KingFusionEventType.validationRejected:
      case KingFusionEventType.hopFailed:
        _recordFailure(event, KingFusionRecoveryHint.inspectEngine);
        break;
      case KingFusionEventType.verificationFailed:
        _recordFailure(event, KingFusionRecoveryHint.verifyTraffic);
        break;
      case KingFusionEventType.cleanupFailed:
        _recordFailure(event, KingFusionRecoveryHint.retryCleanup);
        break;
      case KingFusionEventType.verificationPassed:
        // Only verified traffic clears the accumulated failure streak.
        _failureStreaks.clear();
        _lastFailureCode = null;
        _recoveryHint = KingFusionRecoveryHint.observe;
        break;
      default:
        break;
    }
    return true;
  }

  void _recordFailure(
    KingFusionEvent event,
    KingFusionRecoveryHint hint,
  ) {
    _failureEvents++;
    _lastFailureCode = event.failureCode;
    _recoveryHint = hint;
    final engineId = event.engineId;
    if (engineId != null) {
      _failureStreaks.update(
        engineId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
  }

  KingFusionLearningSnapshot get snapshot => KingFusionLearningSnapshot(
        lastSequence: _lastSequence,
        totalEvents: _totalEvents,
        failureEvents: _failureEvents,
        lastFailureCode: _lastFailureCode,
        recoveryHint: _recoveryHint,
        eventCounts: _eventCounts,
        consecutiveFailuresByEngine: _failureStreaks,
      );
}
