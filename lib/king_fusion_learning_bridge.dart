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
    required this.trafficVerificationPassed,
    required this.trafficVerificationFailed,
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
  final int trafficVerificationPassed;
  final int trafficVerificationFailed;
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
  int _trafficVerificationPassed = 0;
  int _trafficVerificationFailed = 0;
  String? _lastFailureCode;
  KingFusionRecoveryHint _recoveryHint = KingFusionRecoveryHint.observe;

  /// Starts a fresh coordinator session; sequence numbers are scoped to a coordinator.
  void beginSession() {
    _eventCounts.clear();
    _failureStreaks.clear();
    _lastSequence = 0;
    _totalEvents = 0;
    _failureEvents = 0;
    _trafficVerificationPassed = 0;
    _trafficVerificationFailed = 0;
    _lastFailureCode = null;
    _recoveryHint = KingFusionRecoveryHint.observe;
  }

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

  /// Records the app's independent Android-TUN traffic gate after Fusion start.
  /// This signal does not forge a Fusion event or alter its sequence numbers.
  void recordExternalTrafficVerification(bool passed) {
    if (passed) {
      _trafficVerificationPassed++;
      _failureStreaks.clear();
      _lastFailureCode = null;
      _recoveryHint = KingFusionRecoveryHint.observe;
      return;
    }
    _trafficVerificationFailed++;
    _failureEvents++;
    _lastFailureCode = 'E-FUSION-TRAFFIC-UNVERIFIED';
    _recoveryHint = KingFusionRecoveryHint.verifyTraffic;
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

  /// Compact, secret-free context that the conversational KING AI can inspect.
  /// It is evidence only and is wrapped by the caller as untrusted app telemetry.
  String toPromptContext() {
    final current = snapshot;
    if (current.totalEvents == 0) return '';
    final engineStreaks = current.consecutiveFailuresByEngine.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(',');
    return <String>[
      'Fusion events=${current.totalEvents}',
      'failures=${current.failureEvents}',
      'traffic_verified=${current.trafficVerificationPassed}',
      'traffic_unverified=${current.trafficVerificationFailed}',
      'recovery_hint=${current.recoveryHint.name}',
      if (current.lastFailureCode != null)
        'last_failure=${current.lastFailureCode}',
      if (engineStreaks.isNotEmpty) 'engine_failure_streaks=$engineStreaks',
    ].join('; ');
  }

  KingFusionLearningSnapshot get snapshot => KingFusionLearningSnapshot(
        lastSequence: _lastSequence,
        totalEvents: _totalEvents,
        failureEvents: _failureEvents,
        trafficVerificationPassed: _trafficVerificationPassed,
        trafficVerificationFailed: _trafficVerificationFailed,
        lastFailureCode: _lastFailureCode,
        recoveryHint: _recoveryHint,
        eventCounts: _eventCounts,
        consecutiveFailuresByEngine: _failureStreaks,
      );
}

/// Shared current-session evidence consumed by the app and conversational KING AI.
final KingFusionLearningBridge kingFusionLearning = KingFusionLearningBridge();
