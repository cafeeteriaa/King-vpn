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
      expect(
        bridge.observe(_event(
          0,
          KingFusionEventType.cleanupFailed,
          failureCode: 'E-OUT-OF-ORDER',
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
      expect(bridge.toPromptContext(), contains('recovery_hint=inspectEngine'));
      expect(bridge.toPromptContext(), contains('last_failure=E-V2RAY-START'));
      expect(bridge.toPromptContext(), isNot(contains('private-config')));
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
        engineId: 'v2ray',
        failureCode: 'E-FUSION-TRAFFIC-UNVERIFIED',
      ));
      expect(bridge.snapshot.recoveryHint, KingFusionRecoveryHint.verifyTraffic);
      expect(bridge.snapshot.failureEvents, 1);
      expect(bridge.snapshot.consecutiveFailuresByEngine, {'v2ray': 1});

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

    test('new coordinator session resets sequence and prompt evidence', () {
      final bridge = KingFusionLearningBridge();
      bridge.observe(_event(
        4,
        KingFusionEventType.hopFailed,
        failureCode: 'E-OLD',
      ));
      bridge.beginSession();

      expect(bridge.snapshot.totalEvents, 0);
      expect(bridge.toPromptContext(), isEmpty);
      expect(
        bridge.observe(_event(1, KingFusionEventType.connectStarted)),
        isTrue,
      );
      expect(bridge.snapshot.lastSequence, 1);
      expect(bridge.snapshot.failureEvents, 0);
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
