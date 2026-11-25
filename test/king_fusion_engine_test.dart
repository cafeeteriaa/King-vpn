import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import '../lib/king_fusion_engine.dart';

class _FakeAdapter implements KingEngineAdapter {
  @override
  final KingEngineDescriptor descriptor;
  final List<String> events;
  final bool failStart;
  final bool throwTimeoutOnStart;
  final String? startFailureCode;
  final Set<String> chainTargets;
  final Completer<void>? startGate;
  final Completer<void>? startEntered;
  int stopFailuresRemaining;
  final bool stopNeverCompletes;
  final bool throwOnChainCheck;
  final Completer<void>? stopGate;
  final Completer<void>? stopEntered;

  _FakeAdapter(
    String id,
    this.events, {
    this.failStart = false,
    this.throwTimeoutOnStart = false,
    this.startFailureCode = 'E-TEST-START',
    this.chainTargets = const <String>{},
    this.startGate,
    this.startEntered,
    this.stopFailuresRemaining = 0,
    this.stopNeverCompletes = false,
    this.throwOnChainCheck = false,
    this.stopGate,
    this.stopEntered,
    bool supportsMultiHop = true,
  }) : descriptor = KingEngineDescriptor(
          id: id,
          title: id,
          family: KingEngineFamily.custom,
          availability: KingEngineAvailability.integrated,
          supportsMultiHop: supportsMultiHop,
        );

  @override
  bool canChainTo(KingEngineAdapter next) {
    if (throwOnChainCheck) throw StateError('simulated preflight failure');
    return chainTargets.contains(next.descriptor.id);
  }

  @override
  Future<KingEngineStartResult> start({
    required String configuration,
    Object? upstreamHandle,
  }) async {
    events.add('start:${descriptor.id}:${upstreamHandle ?? '-'}');
    if (startEntered != null && !startEntered!.isCompleted) {
      startEntered!.complete();
    }
    if (startGate != null) await startGate!.future;
    if (throwTimeoutOnStart) throw TimeoutException('native start timeout');
    if (failStart) return KingEngineStartResult.failed(startFailureCode);
    return KingEngineStartResult.connected('handle-${descriptor.id}');
  }

  @override
  Future<void> stop(Object? handle) async {
    events.add('stop:${descriptor.id}:$handle');
    if (stopEntered != null && !stopEntered!.isCompleted) {
      stopEntered!.complete();
    }
    if (stopGate != null) await stopGate!.future;
    if (stopNeverCompletes) await Completer<void>().future;
    if (stopFailuresRemaining > 0) {
      stopFailuresRemaining--;
      throw StateError('simulated native stop failure');
    }
  }
}

class _CancellableStartAdapter
    implements KingFusionCancellableEngineAdapter {
  final List<String> events;
  final Completer<void> entered = Completer<void>();
  final Completer<void> gate = Completer<void>();
  int cancelCalls = 0;

  _CancellableStartAdapter(this.events);

  @override
  final KingEngineDescriptor descriptor = const KingEngineDescriptor(
    id: 'cancellable-start',
    title: 'Cancellable start',
    family: KingEngineFamily.custom,
    availability: KingEngineAvailability.integrated,
  );

  @override
  bool canChainTo(KingEngineAdapter next) => false;

  @override
  Future<KingEngineStartResult> start({
    required String configuration,
    Object? upstreamHandle,
  }) async {
    events.add('start:cancellable-start');
    if (!entered.isCompleted) entered.complete();
    await gate.future;
    return const KingEngineStartResult.connected('late-handle');
  }

  @override
  Future<void> cancelPendingStart() async {
    cancelCalls++;
    if (!gate.isCompleted) gate.complete();
  }

  @override
  Future<void> stop(Object? handle) async {
    events.add('stop:cancellable-start:$handle');
  }
}

class _UnavailableAdapter implements KingEngineAdapter {
  @override
  final KingEngineDescriptor descriptor = const KingEngineDescriptor(
    id: 'future-engine',
    title: 'Future engine',
    family: KingEngineFamily.custom,
    availability: KingEngineAvailability.adapterRequired,
  );
  final List<String> events;
  _UnavailableAdapter(this.events);
  @override
  bool canChainTo(KingEngineAdapter next) => false;
  @override
  Future<KingEngineStartResult> start({
    required String configuration,
    Object? upstreamHandle,
  }) async {
    events.add('must-not-start');
    return const KingEngineStartResult.connected();
  }
  @override
  Future<void> stop(Object? handle) async {
    events.add('must-not-stop');
  }
}

class _DelayedTrafficVerifier
    implements KingFusionCancellableTrafficVerifier {
  final Completer<bool> gate = Completer<bool>();
  final Completer<void> entered = Completer<void>();
  int cancelCalls = 0;
  @override
  Future<bool> verify(KingFusionPlan plan) {
    if (!entered.isCompleted) entered.complete();
    return gate.future;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }
}

class _NeverCompletingCancellableVerifier
    implements KingFusionCancellableTrafficVerifier {
  final Completer<void> entered = Completer<void>();
  int cancelCalls = 0;

  @override
  Future<bool> verify(KingFusionPlan plan) {
    if (!entered.isCompleted) entered.complete();
    return Completer<bool>().future;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }
}

class _ThrowingTrafficVerifier implements KingFusionTrafficVerifier {
  @override
  Future<bool> verify(KingFusionPlan plan) async {
    throw StateError('verifier internal exception');
  }
}

class _FakeTrafficVerifier implements KingFusionTrafficVerifier {
  final bool result;
  int calls = 0;
  _FakeTrafficVerifier(this.result);
  @override
  Future<bool> verify(KingFusionPlan plan) async {
    calls++;
    return result;
  }
}

void main() {
  group('KING Fusion Engine', () {
    test('exposes immutable secret-free lifecycle snapshots and ordered events', () async {
      final events = <KingFusionEvent>[];
      final adapterEvents = <String>[];
      final adapter = _FakeAdapter('first', adapterEvents);
      final engine = KingFusionEngine(
        [adapter],
        onEvent: events.add,
      );
      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'first',
          configuration: 'super-secret-config',
        ),
      ]));

      expect(result.connected, isTrue);
      expect(engine.snapshot.state, KingFusionState.connected);
      expect(engine.snapshot.activeEngineIds, ['first']);
      expect(engine.snapshot.cleanupPendingEngineIds, isEmpty);
      expect(events.map((event) => event.sequence).toList(),
          List<int>.generate(events.length, (index) => index + 1));
      expect(events.map((event) => event.type), contains(KingFusionEventType.hopStarted));
      expect(events.every((event) =>
          event.failureCode == null ||
          !event.failureCode!.contains('super-secret-config')), isTrue);
      expect(events.toString(), isNot(contains('super-secret-config')));

      await engine.disconnect();
      expect(engine.snapshot.state, KingFusionState.idle);
      expect(engine.snapshot.activeEngineIds, isEmpty);
      expect(events.last.type, KingFusionEventType.disconnectCompleted);
    });

    test('event listener exceptions cannot interrupt native lifecycle', () async {
      final adapterEvents = <String>[];
      final adapter = _FakeAdapter('first', adapterEvents);
      final engine = KingFusionEngine(
        [adapter],
        onEvent: (_) => throw StateError('observer failure'),
      );

      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg'),
      ]));

      expect(result.connected, isTrue);
      expect(engine.state, KingFusionState.connected);
      await engine.disconnect();
      expect(engine.state, KingFusionState.idle);
      expect(adapterEvents, [
        'start:first:-',
        'stop:first:handle-first',
      ]);
    });

    test('validates every hop before starting any native adapter', () async {
      final events = <String>[];
      final first = _FakeAdapter('first', events);
      final engine = KingFusionEngine([first]);
      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg-1'),
        const KingFusionHop(engineId: 'missing', configuration: 'cfg-2'),
      ]));

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-ADAPTER-MISSING');
      expect(events, isEmpty);
    });

    test('starts a compatible chain in order and disconnects in reverse', () async {
      final events = <String>[];
      final second = _FakeAdapter('second', events);
      final first = _FakeAdapter(
        'first',
        events,
        chainTargets: const {'second'},
      );
      final engine = KingFusionEngine([first, second]);
      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg-1'),
        const KingFusionHop(engineId: 'second', configuration: 'cfg-2'),
      ]));

      expect(result.connected, isTrue);
      expect(result.startedHops, 2);
      expect(events, [
        'start:first:-',
        'start:second:handle-first',
      ]);

      await engine.disconnect();
      expect(events.last, 'stop:first:handle-first');
      expect(events[2], 'stop:second:handle-second');
      expect(engine.state, KingFusionState.idle);
    });

    test('rolls back an already-started hop when the next hop fails', () async {
      final events = <String>[];
      final first = _FakeAdapter(
        'first',
        events,
        chainTargets: const {'second'},
      );
      final second = _FakeAdapter('second', events, failStart: true);
      final engine = KingFusionEngine([first, second]);
      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg-1'),
        const KingFusionHop(engineId: 'second', configuration: 'cfg-2'),
      ]));

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-TEST-START');
      expect(result.startedHops, 1);
      expect(events, [
        'start:first:-',
        'start:second:handle-first',
        'stop:first:handle-first',
      ]);
      expect(engine.state, KingFusionState.failed);
    });

    test('sanitizes malformed adapter failure text before exposing it', () async {
      final events = <String>[];
      final adapter = _FakeAdapter(
        'first',
        events,
        failStart: true,
        startFailureCode: 'E-REMOTE-ERROR: token=private-config-secret',
      );
      final engine = KingFusionEngine([adapter]);
      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'first',
          configuration: 'private-config-secret',
        ),
      ]));

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-ADAPTER-START');
      expect(result.failureCode, isNot(contains('private-config-secret')));
      expect(events, ['start:first:-']);
    });

    test('rejects unsupported chaining and duplicate engine hops', () async {
      final events = <String>[];
      final first = _FakeAdapter('first', events);
      final second = _FakeAdapter('second', events);
      final engine = KingFusionEngine([first, second]);

      final unsupported = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg-1'),
        const KingFusionHop(engineId: 'second', configuration: 'cfg-2'),
      ]));
      expect(unsupported.failureCode, 'E-FUSION-CHAIN-UNSUPPORTED');

      final duplicate = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg-1'),
        const KingFusionHop(engineId: 'first', configuration: 'cfg-2'),
      ]));
      expect(duplicate.failureCode, 'E-FUSION-DUPLICATE-HOP');
      expect(events, isEmpty);
    });

    test('contains adapter compatibility-check exceptions during preflight', () async {
      final events = <String>[];
      final first = _FakeAdapter(
        'first',
        events,
        chainTargets: const {'second'},
        throwOnChainCheck: true,
      );
      final second = _FakeAdapter('second', events);
      final engine = KingFusionEngine([first, second]);

      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg-1'),
        const KingFusionHop(engineId: 'second', configuration: 'cfg-2'),
      ]));

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-VALIDATION-EXCEPTION');
      expect(result.startedHops, 0);
      expect(events, isEmpty);
      expect(engine.state, KingFusionState.failed);
    });

    test('does not execute descriptors that still require a native adapter', () async {
      final events = <String>[];
      final unavailable = _UnavailableAdapter(events);
      final engine = KingFusionEngine([unavailable]);
      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'future-engine', configuration: 'cfg'),
      ]));
      expect(result.failureCode, 'E-FUSION-ADAPTER-NOT-INTEGRATED');
      expect(events, isEmpty);
    });

    test('normalizes harmless engine-id whitespace consistently', () async {
      final events = <String>[];
      final adapter = _FakeAdapter('first', events);
      final engine = KingFusionEngine([adapter]);
      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: ' first ', configuration: 'cfg'),
      ]));
      expect(result.connected, isTrue);
      expect(result.startedHops, 1);
      await engine.disconnect();
    });

    test('empty configuration is rejected without exposing configuration data', () async {
      final events = <String>[];
      final adapter = _FakeAdapter('first', events);
      final engine = KingFusionEngine([adapter]);
      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: '  '),
      ]));

      expect(result.failureCode, 'E-FUSION-CONFIG-EMPTY');
      expect(events, isEmpty);
    });
    test('disconnect asks a cancellable native start to settle promptly', () async {
      final events = <String>[];
      final adapter = _CancellableStartAdapter(events);
      final engine = KingFusionEngine([adapter]);
      final connecting = engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'cancellable-start',
          configuration: 'cfg',
        ),
      ]));

      await adapter.entered.future;
      final disconnecting = engine.disconnect();
      final result = await connecting;
      await disconnecting;

      expect(result.failureCode, 'E-FUSION-CANCELLED');
      expect(adapter.cancelCalls, 1);
      expect(events, [
        'start:cancellable-start',
        'stop:cancellable-start:late-handle',
      ]);
      expect(engine.state, KingFusionState.idle);
    });

    test('disconnect waits for an in-flight native start and cancels the plan', () async {
      final events = <String>[];
      final gate = Completer<void>();
      final entered = Completer<void>();
      final adapter = _FakeAdapter(
        'first',
        events,
        startGate: gate,
        startEntered: entered,
      );
      final engine = KingFusionEngine([adapter]);
      final connecting = engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg'),
      ]));

      await entered.future;
      expect(engine.isBusy, isTrue);
      final competing = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'other'),
      ]));
      expect(competing.failureCode, 'E-FUSION-BUSY');
      final disconnecting = engine.disconnect();
      gate.complete();

      final result = await connecting;
      await disconnecting;
      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-CANCELLED');
      expect(events, ['start:first:-', 'stop:first:handle-first']);
      expect(engine.state, KingFusionState.idle);
    });

    test('retains failed native stops so disconnect can retry cleanup', () async {
      final events = <String>[];
      final adapter = _FakeAdapter(
        'first',
        events,
        stopFailuresRemaining: 1,
      );
      final engine = KingFusionEngine([adapter]);
      final connected = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg'),
      ]));
      expect(connected.connected, isTrue);
      expect(connected.trafficVerified, isFalse);

      await engine.disconnect();
      expect(engine.state, KingFusionState.failed);
      expect(engine.cleanupPendingEngineIds, ['first']);
      final blockedReconnect = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'new-config'),
      ]));
      expect(blockedReconnect.failureCode, 'E-FUSION-CLEANUP-PENDING');
      expect(events.where((event) => event.startsWith('start:')).length, 1);
      await engine.disconnect();

      expect(events.where((event) => event.startsWith('stop:first:')).length, 2);
      expect(engine.state, KingFusionState.idle);
    });

    test('does not stop upstream hops while downstream cleanup is failing', () async {
      final events = <String>[];
      final first = _FakeAdapter(
        'first',
        events,
        chainTargets: const {'second'},
      );
      final second = _FakeAdapter(
        'second',
        events,
        stopFailuresRemaining: 1,
      );
      final engine = KingFusionEngine([first, second]);
      final connected = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg-1'),
        const KingFusionHop(engineId: 'second', configuration: 'cfg-2'),
      ]));
      expect(connected.connected, isTrue);

      await engine.disconnect();
      expect(events.where((event) => event.startsWith('stop:')).toList(),
          ['stop:second:handle-second']);
      expect(engine.cleanupPendingEngineIds, ['first', 'second']);
      expect(engine.state, KingFusionState.failed);

      await engine.disconnect();
      expect(events.where((event) => event.startsWith('stop:')).toList(), [
        'stop:second:handle-second',
        'stop:second:handle-second',
        'stop:first:handle-first',
      ]);
      expect(engine.state, KingFusionState.idle);
    });

    test('reports and retains cleanup failures after a later hop fails', () async {
      final events = <String>[];
      final first = _FakeAdapter(
        'first',
        events,
        chainTargets: const {'second'},
        stopFailuresRemaining: 1,
      );
      final second = _FakeAdapter('second', events, failStart: true);
      final engine = KingFusionEngine([first, second]);

      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg-1'),
        const KingFusionHop(engineId: 'second', configuration: 'cfg-2'),
      ]));

      expect(result.connected, isFalse);
      expect(result.cleanupFailedEngineIds, ['first']);
      expect(engine.state, KingFusionState.failed);
      await engine.disconnect();
      expect(engine.state, KingFusionState.idle);
      expect(events.where((event) => event.startsWith('stop:first:')).length, 2);
    });


    test('requires a data-plane verifier before starting when requested', () async {
      final events = <String>[];
      final adapter = _FakeAdapter('first', events);
      final engine = KingFusionEngine([adapter]);
      final result = await engine.connect(KingFusionPlan(
        [const KingFusionHop(engineId: 'first', configuration: 'cfg')],
        requireTrafficVerification: true,
      ));

      expect(result.failureCode, 'E-FUSION-VERIFIER-MISSING');
      expect(events, isEmpty);
    });

    test('rolls back native hops when data-plane verification fails', () async {
      final events = <String>[];
      final adapter = _FakeAdapter('first', events);
      final engine = KingFusionEngine(
        [adapter],
        trafficVerifier: _FakeTrafficVerifier(false),
      );
      final result = await engine.connect(KingFusionPlan(
        [const KingFusionHop(engineId: 'first', configuration: 'cfg')],
        requireTrafficVerification: true,
      ));

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-TRAFFIC-UNVERIFIED');
      expect(result.startedHops, 1);
      expect(events, ['start:first:-', 'stop:first:handle-first']);
      expect(engine.state, KingFusionState.failed);
    });

    test('accepts the chain only after positive data-plane verification', () async {
      final events = <String>[];
      final verifier = _FakeTrafficVerifier(true);
      final adapter = _FakeAdapter('first', events);
      final engine = KingFusionEngine([adapter], trafficVerifier: verifier);
      final result = await engine.connect(KingFusionPlan(
        [const KingFusionHop(engineId: 'first', configuration: 'cfg')],
        requireTrafficVerification: true,
      ));

      expect(result.connected, isTrue);
      expect(result.trafficVerified, isTrue);
      expect(verifier.calls, 1);
      expect(engine.state, KingFusionState.connected);
      await engine.disconnect();
    });

    test('classifies verifier exceptions separately from native hop failures', () async {
      final lifecycle = <KingFusionEvent>[];
      final adapterEvents = <String>[];
      final adapter = _FakeAdapter('first', adapterEvents);
      final engine = KingFusionEngine(
        [adapter],
        trafficVerifier: _ThrowingTrafficVerifier(),
        onEvent: lifecycle.add,
      );
      final result = await engine.connect(KingFusionPlan(
        [const KingFusionHop(engineId: 'first', configuration: 'cfg')],
        requireTrafficVerification: true,
      ));

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-VERIFY-EXCEPTION');
      expect(lifecycle.any((event) =>
          event.type == KingFusionEventType.verificationFailed &&
          event.failureCode == 'E-FUSION-VERIFY-EXCEPTION'), isTrue);
      expect(lifecycle.where((event) =>
          event.type == KingFusionEventType.hopFailed), isEmpty);
      expect(adapterEvents, [
        'start:first:-',
        'stop:first:handle-first',
      ]);
      expect(engine.state, KingFusionState.failed);
    });

    test('disconnect during traffic verification cancels and rolls back', () async {
      final events = <String>[];
      final verifier = _DelayedTrafficVerifier();
      final adapter = _FakeAdapter('first', events);
      final engine = KingFusionEngine([adapter], trafficVerifier: verifier);
      final connecting = engine.connect(KingFusionPlan(
        [const KingFusionHop(engineId: 'first', configuration: 'cfg')],
        requireTrafficVerification: true,
      ));

      await verifier.entered.future;
      final disconnecting = engine.disconnect();
      verifier.gate.complete(true);

      final result = await connecting;
      await disconnecting;
      expect(result.failureCode, 'E-FUSION-CANCELLED');
      expect(events, ['start:first:-', 'stop:first:handle-first']);
      expect(engine.state, KingFusionState.idle);
    });

    test('verification timeout rolls back every started adapter', () async {
      final events = <String>[];
      final verifier = _DelayedTrafficVerifier();
      final adapter = _FakeAdapter('first', events);
      final engine = KingFusionEngine(
        [adapter],
        trafficVerifier: verifier,
        trafficVerificationTimeout: const Duration(milliseconds: 1),
      );
      final result = await engine.connect(KingFusionPlan(
        [const KingFusionHop(engineId: 'first', configuration: 'cfg')],
        requireTrafficVerification: true,
      ));

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-VERIFY-TIMEOUT');
      expect(verifier.cancelCalls, 1);
      expect(result.trafficVerified, isFalse);
      expect(events, ['start:first:-', 'stop:first:handle-first']);
      expect(engine.cleanupPendingEngineIds, isEmpty);
      expect(engine.state, KingFusionState.failed);
    });

    test('disconnect interrupts a verifier that never completes', () async {
      final events = <String>[];
      final verifier = _NeverCompletingCancellableVerifier();
      final adapter = _FakeAdapter('first', events);
      final engine = KingFusionEngine([adapter], trafficVerifier: verifier);
      final connecting = engine.connect(KingFusionPlan(
        [const KingFusionHop(engineId: 'first', configuration: 'cfg')],
        requireTrafficVerification: true,
      ));

      await verifier.entered.future;
      final disconnecting = engine.disconnect();
      final result = await connecting;
      await disconnecting;

      expect(result.failureCode, 'E-FUSION-CANCELLED');
      expect(verifier.cancelCalls, 1);
      expect(events, ['start:first:-', 'stop:first:handle-first']);
      expect(engine.state, KingFusionState.idle);
      expect(engine.isBusy, isFalse);
    });

    test('native stop timeout never overlaps a still-running stop attempt', () async {
      final events = <String>[];
      final stopGate = Completer<void>();
      final stopEntered = Completer<void>();
      final adapter = _FakeAdapter(
        'first',
        events,
        stopGate: stopGate,
        stopEntered: stopEntered,
      );
      final engine = KingFusionEngine(
        [adapter],
        nativeStopTimeout: const Duration(milliseconds: 2),
      );
      final connected = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg'),
      ]));
      expect(connected.connected, isTrue);

      await engine.disconnect();
      await stopEntered.future;
      expect(engine.cleanupPendingEngineIds, ['first']);

      await engine.disconnect();
      expect(events.where((event) => event.startsWith('stop:first:')).length, 1);

      stopGate.complete();
      await Future<void>.delayed(Duration.zero);
      await engine.disconnect();

      expect(events.where((event) => event.startsWith('stop:first:')).length, 2);
      expect(engine.state, KingFusionState.idle);
    });

    test('native stop timeout preserves the handle for later cleanup', () async {
      final events = <String>[];
      final adapter = _FakeAdapter(
        'first',
        events,
        stopNeverCompletes: true,
      );
      final engine = KingFusionEngine(
        [adapter],
        nativeStopTimeout: const Duration(milliseconds: 1),
      );
      final connected = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg'),
      ]));
      expect(connected.connected, isTrue);

      await engine.disconnect();

      expect(engine.state, KingFusionState.failed);
      expect(engine.cleanupPendingEngineIds, ['first']);
      expect(events.where((event) => event.startsWith('stop:first:')).length, 1);
    });

    test('native start exception after disconnect is classified as cancellation', () async {
      final events = <String>[];
      final first = _FakeAdapter(
        'first',
        events,
        chainTargets: const {'second'},
      );
      final gate = Completer<void>();
      final entered = Completer<void>();
      final second = _FakeAdapter(
        'second',
        events,
        startGate: gate,
        startEntered: entered,
        throwTimeoutOnStart: true,
      );
      final engine = KingFusionEngine([first, second]);
      final connecting = engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg-1'),
        const KingFusionHop(engineId: 'second', configuration: 'cfg-2'),
      ]));

      await entered.future;
      final disconnecting = engine.disconnect();
      gate.complete();

      final result = await connecting;
      await disconnecting;
      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-CANCELLED');
      expect(result.startedHops, 1);
      expect(events, [
        'start:first:-',
        'start:second:handle-first',
        'stop:first:handle-first',
      ]);
      expect(engine.state, KingFusionState.idle);
    });

    test('native adapter TimeoutException is not mislabeled as verifier timeout', () async {
      final events = <String>[];
      final adapter = _FakeAdapter(
        'first',
        events,
        throwTimeoutOnStart: true,
      );
      final engine = KingFusionEngine([adapter]);
      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg'),
      ]));

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-EXCEPTION');
      expect(result.trafficVerified, isFalse);
      expect(engine.state, KingFusionState.failed);
    });
  });
}
