import 'package:flutter_test/flutter_test.dart';

import '../lib/king_fusion_engine.dart';
import '../lib/king_fusion_learning_bridge.dart';

KingFusionEvent _event(
  int sequence,
  KingFusionEventType type, {
  String? engineId = 'v2ray',
  String? failureCode,
  KingFusionState state = KingFusionState.failed,
}) =>
    KingFusionEvent(
      sequence: sequence,
      timestamp: DateTime.utc(2026, 11, 25),
      type: type,
      state: state,
      engineId: engineId,
      failureCode: failureCode,
      activeHopCount: 0,
    );

void main() {
  group('KingFusionLearningBridge', () {
    test('aggregates safe lifecycle evidence and rejects duplicate delivery', () {
      final bridge = KingFusionLearningBridge();

      expect(
        bridge.observe(_event(
          1,
          KingFusionEventType.hopFailed,
          failureCode: 'E-V2RAY-START',
        )),
        isTrue,
      );
      expect(
        bridge.observe(_event(
          1,
          KingFusionEventType.cleanupFailed,
          failureCode: 'E-STOP',
        )),
        isFalse,
      );

      final snapshot = bridge.snapshot;
      expect(snapshot.totalEvents, 1);
      expect(snapshot.failureEvents, 1);
      expect(snapshot.lastSequence, 1);
      expect(snapshot.lastFailureCode, 'E-V2RAY-START');
      expect(snapshot.recoveryHint, KingFusionRecoveryHint.inspectEngine);
      expect(snapshot.consecutiveFailuresByEngine, {'v2ray': 1});
      expect(snapshot.eventCounts[KingFusionEventType.hopFailed], 1);
    });

    test('cleanup failure takes priority and retains retryable engine evidence', () {
      final bridge = KingFusionLearningBridge();
      bridge.observe(_event(
        1,
        KingFusionEventType.hopFailed,
        failureCode: 'E-START',
      ));
      bridge.observe(_event(
        2,
        KingFusionEventType.cleanupFailed,
        failureCode: 'E-STOP',
      ));

      expect(bridge.snapshot.recoveryHint, KingFusionRecoveryHint.retryCleanup);
      expect(bridge.snapshot.failureEvents, 2);
      expect(bridge.snapshot.consecutiveFailureCount, 2);
      expect(bridge.snapshot.lastFailureCode, 'E-STOP');
    });

    test('only verified traffic clears failure streaks', () {
      final bridge = KingFusionLearningBridge();
      bridge.observe(_event(
        1,
        KingFusionEventType.verificationFailed,
        engineId: null,
        failureCode: 'E-FUSION-TRAFFIC-UNVERIFIED',
      ));
      expect(bridge.snapshot.recoveryHint, KingFusionRecoveryHint.verifyTraffic);
      expect(bridge.snapshot.failureEvents, 1);

      bridge.observe(_event(
        2,
        KingFusionEventType.verificationPassed,
        engineId: null,
        failureCode: null,
        state: KingFusionState.connected,
      ));
      expect(bridge.snapshot.recoveryHint, KingFusionRecoveryHint.observe);
      expect(bridge.snapshot.consecutiveFailuresByEngine, isEmpty);
    });

    test('snapshot maps are immutable copies', () {
      final bridge = KingFusionLearningBridge();
      bridge.observe(_event(1, KingFusionEventType.hopFailed));
      final snapshot = bridge.snapshot;

      expect(
        () => snapshot.eventCounts[KingFusionEventType.hopFailed] = 99,
        throwsUnsupportedError,
      );
      expect(
        () => snapshot.consecutiveFailuresByEngine['v2ray'] = 99,
        throwsUnsupportedError,
      );
      bridge.observe(_event(2, KingFusionEventType.hopFailed));
      expect(snapshot.consecutiveFailureCount, 1);
      expect(bridge.snapshot.consecutiveFailureCount, 2);
    });
  });
}
