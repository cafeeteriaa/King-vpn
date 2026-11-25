import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../lib/king_fusion_engine.dart';
import '../lib/king_v2ray_adapter.dart';

void main() {
  group('KingV2RayAdapter', () {
    test('bridges plugin start and stop while preserving host verification boundary', () async {
      final calls = <String>[];
      final adapter = KingV2RayAdapter(
        start: (configuration) async {
          calls.add('start:$configuration');
        },
        stop: () async {
          calls.add('stop');
        },
      );
      final engine = KingFusionEngine([adapter]);

      expect(engine.availableEngines.single.id, 'king-v2ray-xray');
      expect(engine.availableEngines.single.family, KingEngineFamily.xray);
      expect(engine.availableEngines.single.availability,
          KingEngineAvailability.integrated);
      expect(engine.availableEngines.single.supportsMultiHop, isFalse);

      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'king-v2ray-xray',
          configuration: 'opaque-vless-config',
        ),
      ]));

      expect(result.connected, isTrue);
      expect(result.trafficVerified, isFalse);
      expect(engine.state, KingFusionState.connected);
      expect(calls, ['start:opaque-vless-config']);

      await engine.disconnect();

      expect(calls, ['start:opaque-vless-config', 'stop']);
      expect(engine.state, KingFusionState.idle);
      expect(engine.snapshot.activeEngineIds, isEmpty);
    });

    test('maps native start exceptions to a stable secret-free failure code', () async {
      final adapter = KingV2RayAdapter(
        start: (_) async => throw StateError('secret-config-must-not-escape'),
        stop: () async {},
      );
      final engine = KingFusionEngine([adapter]);

      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'king-v2ray-xray',
          configuration: 'private-config',
        ),
      ]));

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-V2RAY-START');
      expect(result.failureCode, isNot(contains('private-config')));
      expect(engine.recentEvents.map((event) => event.failureCode),
          isNot(contains('secret-config-must-not-escape')));
      expect(engine.snapshot.activeEngineIds, isEmpty);
    });

    test('rejects empty config without crossing native boundary', () async {
      var starts = 0;
      final adapter = KingV2RayAdapter(
        start: (_) async {
          starts++;
        },
        stop: () async {},
      );
      final result = await adapter.start(configuration: '  ');

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-V2RAY-CONFIG-EMPTY');
      expect(starts, 0);
    });

    test('cancels a pending native start and stops again after late completion', () async {
      final startGate = Completer<void>();
      final startEntered = Completer<void>();
      final firstStopEntered = Completer<void>();
      var stops = 0;
      final adapter = KingV2RayAdapter(
        start: (_) {
          if (!startEntered.isCompleted) startEntered.complete();
          return startGate.future;
        },
        stop: () async {
          stops++;
          if (!firstStopEntered.isCompleted) firstStopEntered.complete();
        },
      );
      final engine = KingFusionEngine([adapter]);
      final connecting = engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'king-v2ray-xray',
          configuration: 'opaque-config',
        ),
      ]));

      await startEntered.future;
      final disconnecting = engine.disconnect();
      await firstStopEntered.future;
      expect(stops, 1);
      // Let the first stop Future settle before allowing a deliberately late
      // start completion; the adapter must then issue a fresh cleanup stop.
      await Future<void>.delayed(Duration.zero);

      startGate.complete();
      final result = await connecting;
      await disconnecting;

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-CANCELLED');
      expect(stops, 2);
      expect(engine.state, KingFusionState.idle);
      expect(engine.snapshot.activeEngineIds, isEmpty);
    });

    test('coalesces cancellation and late-start cleanup while stop is in flight', () async {
      final startGate = Completer<void>();
      final stopGate = Completer<void>();
      final startEntered = Completer<void>();
      final stopEntered = Completer<void>();
      var stopCalls = 0;
      final adapter = KingV2RayAdapter(
        start: (_) {
          if (!startEntered.isCompleted) startEntered.complete();
          return startGate.future;
        },
        stop: () async {
          stopCalls++;
          if (!stopEntered.isCompleted) stopEntered.complete();
          await stopGate.future;
        },
      );
      final engine = KingFusionEngine([adapter]);
      final connecting = engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'king-v2ray-xray',
          configuration: 'opaque-config',
        ),
      ]));

      await startEntered.future;
      final disconnecting = engine.disconnect();
      await stopEntered.future;
      startGate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(stopCalls, 1);

      stopGate.complete();
      final result = await connecting;
      await disconnecting;

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-CANCELLED');
      expect(stopCalls, 1);
      expect(engine.state, KingFusionState.idle);
    });

    test('retains a timed-out native start until late completion can be stopped', () async {
      final startGate = Completer<void>();
      var stopCalls = 0;
      final adapter = KingV2RayAdapter(
        nativeStartTimeout: const Duration(milliseconds: 5),
        start: (_) => startGate.future,
        stop: () async {
          stopCalls++;
        },
      );
      final engine = KingFusionEngine(
        [adapter],
        nativeStopTimeout: const Duration(milliseconds: 5),
      );

      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'king-v2ray-xray',
          configuration: 'opaque-config',
        ),
      ]));

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-V2RAY-START-TIMEOUT');
      expect(result.cleanupFailedEngineIds, ['king-v2ray-xray']);
      expect(engine.cleanupPendingEngineIds, ['king-v2ray-xray']);
      expect(stopCalls, 0);

      startGate.complete();
      await engine.disconnect();

      expect(stopCalls, 1);
      expect(engine.cleanupPendingEngineIds, isEmpty);
      expect(engine.state, KingFusionState.idle);
    });

    test('retains partially started native core when initial cleanup fails', () async {
      var stopCalls = 0;
      final adapter = KingV2RayAdapter(
        start: (_) async => throw StateError('native core partially started'),
        stop: () async {
          stopCalls++;
          if (stopCalls < 3) throw StateError('native stop not confirmed');
        },
      );
      final engine = KingFusionEngine([adapter]);

      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'king-v2ray-xray',
          configuration: 'opaque-config',
        ),
      ]));

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-V2RAY-START');
      expect(result.cleanupFailedEngineIds, ['king-v2ray-xray']);
      expect(engine.cleanupPendingEngineIds, ['king-v2ray-xray']);
      expect(stopCalls, 2);

      await engine.disconnect();

      expect(stopCalls, 3);
      expect(engine.cleanupPendingEngineIds, isEmpty);
      expect(engine.state, KingFusionState.idle);
    });

    test('stop is idempotent for an already released native handle', () async {
      var stops = 0;
      final adapter = KingV2RayAdapter(
        start: (_) async {},
        stop: () async {
          stops++;
        },
      );
      final result = await adapter.start(configuration: 'opaque-config');
      expect(result.connected, isTrue);

      await adapter.stop(result.handle);
      await adapter.stop(result.handle);

      expect(stops, 1);
    });
  });
}
