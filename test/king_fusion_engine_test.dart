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
  final Set<String> supportedTransports;
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
    this.supportedTransports = const <String>{},
    this.stopGate,
    this.stopEntered,
    bool supportsMultiHop = true,
  }) : descriptor = KingEngineDescriptor(
          id: id,
          title: id,
          family: KingEngineFamily.custom,
          availability: KingEngineAvailability.integrated,
          supportedTransports: supportedTransports,
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

class _MutableDescriptorAdapter implements KingEngineAdapter {
  @override
  final KingEngineDescriptor descriptor;
  _MutableDescriptorAdapter(this.descriptor);
  @override
  bool canChainTo(KingEngineAdapter next) => false;
  @override
  Future<KingEngineStartResult> start({
    required String configuration,
    Object? upstreamHandle,
  }) async => const KingEngineStartResult.connected();
  @override
  Future<void> stop(Object? handle) async {}
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
    test('failure result snapshots caller-owned cleanup identifiers immutably', () {
      final sourceIds = <String>['engine-a'];
      final result = KingFusionResult.failure(
        failedEngineId: 'engine-b',
        failureCode: 'E-FUSION-ROLLBACK',
        startedHops: 1,
        cleanupFailedEngineIds: sourceIds,
      );

      sourceIds
        ..clear()
        ..add('tampered');
      expect(result.cleanupFailedEngineIds, ['engine-a']);
      expect(
        () => result.cleanupFailedEngineIds[0] = 'rewritten',
        throwsA(isA<UnsupportedError>()),
      );
    });

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
      expect(
        () => engine.snapshot.activeEngineIds.add('injected'),
        throwsA(isA<UnsupportedError>()),
      );
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

    test('lifecycle event sequence advances when telemetry is not configured', () async {
      final adapterEvents = <String>[];
      final engine = KingFusionEngine([
        _FakeAdapter('first', adapterEvents),
      ]);

      expect(engine.snapshot.eventSequence, 0);
      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg'),
      ]));

      expect(result.connected, isTrue);
      final connectedSequence = engine.snapshot.eventSequence;
      expect(connectedSequence, greaterThan(0));

      await engine.disconnect();

      expect(engine.snapshot.eventSequence, greaterThan(connectedSequence));
      expect(engine.snapshot.state, KingFusionState.idle);
    });

    test('disconnectRequested observer can reenter without recursive dispatch', () async {
      final adapterEvents = <String>[];
      final adapter = _FakeAdapter('first', adapterEvents);
      late final KingFusionEngine engine;
      Future<void>? reentrantDisconnect;
      var disconnectRequestedEvents = 0;
      var snapshotSawPendingDisconnect = false;
      engine = KingFusionEngine(
        [adapter],
        onEvent: (event) {
          if (event.type == KingFusionEventType.disconnectRequested) {
            disconnectRequestedEvents++;
            snapshotSawPendingDisconnect = engine.snapshot.disconnectRequested;
            reentrantDisconnect ??= engine.disconnect();
          }
        },
      );

      final connected = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg'),
      ]));
      expect(connected.connected, isTrue);

      final disconnecting = engine.disconnect();
      await disconnecting;
      await reentrantDisconnect;

      expect(disconnectRequestedEvents, 1);
      expect(snapshotSawPendingDisconnect, isTrue);
      expect(engine.snapshot.disconnectRequested, isFalse);
      expect(adapterEvents.where((event) => event.startsWith('stop:')).length, 1);
      expect(engine.state, KingFusionState.idle);
      expect(engine.isBusy, isFalse);
    });

    test('disconnectRequested observer cannot start a new connection', () async {
      final adapterEvents = <String>[];
      final adapter = _FakeAdapter('first', adapterEvents);
      late final KingFusionEngine engine;
      Future<KingFusionResult>? reentrantConnect;
      engine = KingFusionEngine(
        [adapter],
        onEvent: (event) {
          if (event.type == KingFusionEventType.disconnectRequested) {
            // The observer runs synchronously while the disconnect operation
            // is already published but before native cleanup starts.
            reentrantConnect ??= engine.connect(KingFusionPlan([
              const KingFusionHop(engineId: 'first', configuration: 'racing'),
            ]));
          }
        },
      );

      final connected = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg'),
      ]));
      expect(connected.connected, isTrue);

      await engine.disconnect();
      final attemptedConnection = await reentrantConnect;

      expect(attemptedConnection?.connected, isFalse);
      expect(attemptedConnection?.failureCode, 'E-FUSION-DISCONNECT-PENDING');
      expect(adapterEvents.where((event) => event.startsWith('start:')).length, 1);
      expect(adapterEvents.where((event) => event.startsWith('stop:')).length, 1);
      expect(engine.state, KingFusionState.idle);
      expect(engine.isBusy, isFalse);
    });

    test('event listener can request disconnect reentrantly after native start', () async {
      final adapterEvents = <String>[];
      final adapter = _FakeAdapter('first', adapterEvents);
      late KingFusionEngine engine;
      Future<void>? disconnectFuture;
      engine = KingFusionEngine(
        [adapter],
        onEvent: (event) {
          if (event.type == KingFusionEventType.hopStarted) {
            disconnectFuture ??= engine.disconnect();
          }
        },
      );

      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg'),
      ]));
      await disconnectFuture;

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-CANCELLED');
      expect(adapterEvents.where((event) => event.startsWith('stop:first:')).length, 1);
      expect(engine.snapshot.state, KingFusionState.idle);
      expect(engine.snapshot.activeEngineIds, isEmpty);
      expect(engine.isBusy, isFalse);
      expect(engine.snapshot.disconnectRequested, isFalse);
    });

    test('retains a bounded immutable lifecycle history without an observer', () async {
      final events = <String>[];
      final adapter = _FakeAdapter('first', events);
      final engine = KingFusionEngine([adapter], eventHistoryLimit: 3);

      final connected = await engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'first',
          configuration: 'private-config-must-not-enter-history',
        ),
      ]));

      expect(connected.connected, isTrue);
      expect(engine.recentEvents, hasLength(3));
      expect(engine.recentEvents.last.sequence, engine.snapshot.eventSequence);
      expect(engine.recentEvents.every((event) =>
          event.engineId == null || event.engineId == 'first'), isTrue);
      expect(engine.recentEvents.toString(),
          isNot(contains('private-config-must-not-enter-history')));
      expect(() => engine.recentEvents.clear(), throwsUnsupportedError);
      expect(() => engine.snapshot.recentEvents.clear(), throwsUnsupportedError);

      await engine.disconnect();
      expect(engine.recentEvents, hasLength(3));
      expect(engine.recentEvents.last.type,
          KingFusionEventType.disconnectCompleted);
      expect(engine.recentEvents.first.sequence,
          engine.snapshot.eventSequence - 2);
    });

    test('rejects a non-positive lifecycle history limit', () {
      expect(
        () => KingFusionEngine(
          [_FakeAdapter('first', <String>[])],
          eventHistoryLimit: 0,
        ),
        throwsArgumentError,
      );
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

    test('rejects duplicate adapter identifiers at registry construction', () {
      final events = <String>[];
      final first = _FakeAdapter('duplicate', events);
      final second = _FakeAdapter(' duplicate ', events);

      expect(
        () => KingFusionEngine([first, second]),
        throwsArgumentError,
      );
      expect(events, isEmpty);
    });

    test('rejects unsafe adapter identifiers before exposing registry data', () {
      final events = <String>[];
      final unsafe = _FakeAdapter('xray\\nprivate-secret', events);

      expect(
        () => KingFusionEngine([unsafe]),
        throwsArgumentError,
      );
      expect(events, isEmpty);
    });

    test('rejects non-positive native and verifier timeouts', () {
      final events = <String>[];
      final adapter = _FakeAdapter('first', events);

      expect(
        () => KingFusionEngine(
          [adapter],
          nativeStopTimeout: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => KingFusionEngine(
          [adapter],
          trafficVerificationTimeout: const Duration(microseconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('emits sanitized validation-rejection telemetry', () async {
      final lifecycle = <KingFusionEvent>[];
      final adapterEvents = <String>[];
      final adapter = _FakeAdapter('first', adapterEvents);
      final engine = KingFusionEngine([adapter], onEvent: lifecycle.add);

      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'first',
          configuration: 'must-not-appear-in-telemetry',
        ),
        const KingFusionHop(engineId: 'missing', configuration: 'cfg'),
      ]));

      expect(result.failureCode, 'E-FUSION-ADAPTER-MISSING');
      final rejected = lifecycle.singleWhere(
        (event) => event.type == KingFusionEventType.validationRejected,
      );
      expect(rejected.engineId, 'missing');
      expect(rejected.failureCode, 'E-FUSION-ADAPTER-MISSING');
      expect(lifecycle.toString(), isNot(contains('must-not-appear-in-telemetry')));
      expect(adapterEvents, isEmpty);
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

    test('snapshots adapter capabilities so external mutation cannot rewrite registry', () async {
      final events = <String>[];
      final mutableTransports = <String>{'tcp'};
      final adapter = _FakeAdapter(
        'first',
        events,
        supportedTransports: mutableTransports,
      );
      final engine = KingFusionEngine([adapter]);

      mutableTransports.clear();
      final published = engine.availableEngines.single;
      expect(published.supportedTransports, contains('tcp'));
      expect(
        () => published.supportedTransports.add('grpc'),
        throwsA(isA<UnsupportedError>()),
      );

      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'first',
          configuration: 'opaque',
          requiredTransport: 'tcp',
        ),
      ]));
      expect(result.connected, isTrue);
      await engine.disconnect();
    });

    test('validates an explicitly requested transport against adapter capabilities', () async {
      final events = <String>[];
      final adapter = _FakeAdapter(
        'first',
        events,
        supportedTransports: const {'tcp', 'ws'},
      );
      final engine = KingFusionEngine([adapter]);

      final supported = await engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'first',
          configuration: 'opaque-config',
          requiredTransport: ' WS ',
        ),
      ]));
      expect(supported.connected, isTrue);
      await engine.disconnect();

      final unsupported = await engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'first',
          configuration: 'opaque-config',
          requiredTransport: 'grpc',
        ),
      ]));
      expect(unsupported.failureCode, 'E-FUSION-TRANSPORT-UNSUPPORTED');
      expect(events.where((event) => event.startsWith('start:')).length, 1);
    });

    test('rejects malformed transport requirements before native start', () async {
      final events = <String>[];
      final adapter = _FakeAdapter(
        'first',
        events,
        supportedTransports: const {'tcp'},
      );
      final engine = KingFusionEngine([adapter]);
      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'first',
          configuration: 'opaque-config',
          requiredTransport: 'tcp\\nsecret',
        ),
      ]));

      expect(result.failureCode, 'E-FUSION-TRANSPORT-INVALID');
      expect(events, isEmpty);
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

    test('concurrent disconnect during native start requests cancellation once', () async {
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
      final firstDisconnect = engine.disconnect();
      final secondDisconnect = engine.disconnect();
      final result = await connecting;
      await Future.wait([firstDisconnect, secondDisconnect]);

      expect(result.failureCode, 'E-FUSION-CANCELLED');
      expect(adapter.cancelCalls, 1);
      expect(events, [
        'start:cancellable-start',
        'stop:cancellable-start:late-handle',
      ]);
      expect(engine.state, KingFusionState.idle);
      expect(engine.isBusy, isFalse);
      expect(engine.snapshot.disconnectRequested, isFalse);
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

    test('cleanupFailed observer joins disconnect without recursive stop', () async {
      final events = <String>[];
      late final KingFusionEngine engine;
      Future<void>? observerDisconnect;
      engine = KingFusionEngine(
        [
          _FakeAdapter(
            'first',
            events,
            stopFailuresRemaining: 1,
          ),
        ],
        onEvent: (event) {
          if (event.type == KingFusionEventType.cleanupFailed) {
            observerDisconnect ??= engine.disconnect();
          }
        },
      );
      final connected = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg'),
      ]));
      expect(connected.connected, isTrue);

      await engine.disconnect();
      await observerDisconnect;

      expect(
        events.where((event) => event.startsWith('stop:first:')).length,
        1,
      );
      expect(engine.state, KingFusionState.failed);
      expect(engine.cleanupPendingEngineIds, ['first']);

      await engine.disconnect();
      expect(
        events.where((event) => event.startsWith('stop:first:')).length,
        2,
      );
      expect(engine.state, KingFusionState.idle);
      expect(engine.isBusy, isFalse);
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
      expect(
        () => result.cleanupFailedEngineIds[0] = 'tampered',
        throwsUnsupportedError,
      );
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

    test('concurrent disconnect callers share native cleanup completion', () async {
      final events = <String>[];
      final stopGate = Completer<void>();
      final stopEntered = Completer<void>();
      final adapter = _FakeAdapter(
        'first',
        events,
        stopGate: stopGate,
        stopEntered: stopEntered,
      );
      final engine = KingFusionEngine([adapter]);
      final connected = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg'),
      ]));
      expect(connected.connected, isTrue);

      final firstDisconnect = engine.disconnect();
      await stopEntered.future;
      var secondCompleted = false;
      final secondDisconnect = engine.disconnect().then<void>((_) {
        secondCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(secondCompleted, isFalse);

      stopGate.complete();
      await Future.wait([firstDisconnect, secondDisconnect]);

      expect(secondCompleted, isTrue);
      expect(engine.state, KingFusionState.idle);
      expect(engine.snapshot.activeEngineIds, isEmpty);
      expect(events.where((event) => event.startsWith('stop:first:')).length, 1);
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

    test('disconnect requested by connected-state observer prevents success result', () async {
      final events = <String>[];
      final adapter = _FakeAdapter('first', events);
      late final KingFusionEngine engine;
      Future<void>? disconnecting;
      engine = KingFusionEngine(
        [adapter],
        onEvent: (event) {
          if (event.type == KingFusionEventType.stateChanged &&
              event.state == KingFusionState.connected) {
            disconnecting = engine.disconnect();
          }
        },
      );

      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg'),
      ]));
      await disconnecting;

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-CANCELLED');
      expect(result.startedHops, 1);
      expect(events.where((event) => event.startsWith('start:first:')).length, 1);
      expect(events.where((event) => event.startsWith('stop:first:')).length, 1);
      expect(engine.state, KingFusionState.idle);
      expect(engine.isBusy, isFalse);
    });

    test('disconnect requested by verification observer prevents success result', () async {
      final events = <String>[];
      final adapter = _FakeAdapter('first', events);
      late final KingFusionEngine engine;
      Future<void>? disconnecting;
      engine = KingFusionEngine(
        [adapter],
        trafficVerifier: _FakeTrafficVerifier(true),
        onEvent: (event) {
          if (event.type == KingFusionEventType.verificationPassed) {
            disconnecting = engine.disconnect();
          }
        },
      );

      final result = await engine.connect(KingFusionPlan(
        [const KingFusionHop(engineId: 'first', configuration: 'cfg')],
        requireTrafficVerification: true,
      ));
      await disconnecting;

      expect(result.connected, isFalse);
      expect(result.trafficVerified, isFalse);
      expect(result.failureCode, 'E-FUSION-CANCELLED');
      expect(result.startedHops, 1);
      expect(events.where((event) => event.startsWith('start:first:')).length, 1);
      expect(events.where((event) => event.startsWith('stop:first:')).length, 1);
      expect(engine.state, KingFusionState.idle);
      expect(engine.isBusy, isFalse);
    });

    test('hopStarting observer cancellation prevents native adapter start', () async {
      final events = <String>[];
      final adapter = _FakeAdapter('first', events);
      late final KingFusionEngine engine;
      Future<void>? disconnecting;
      engine = KingFusionEngine(
        [adapter],
        onEvent: (event) {
          if (event.type == KingFusionEventType.hopStarting) {
            disconnecting = engine.disconnect();
          }
        },
      );

      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'first', configuration: 'cfg'),
      ]));
      await disconnecting;

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-CANCELLED');
      expect(result.startedHops, 0);
      expect(events.where((event) => event.startsWith('start:first:')), isEmpty);
      expect(events.where((event) => event.startsWith('stop:first:')), isEmpty);
      expect(engine.state, KingFusionState.idle);
      expect(engine.isBusy, isFalse);
    });

    test('validation observer cannot reenter and start a second plan', () async {
      final events = <String>[];
      final adapter = _FakeAdapter('first', events);
      late final KingFusionEngine engine;
      Future<KingFusionResult>? nested;
      engine = KingFusionEngine(
        [adapter],
        onEvent: (event) {
          if (event.type == KingFusionEventType.validationRejected) {
            nested = engine.connect(KingFusionPlan([
              const KingFusionHop(engineId: 'first', configuration: 'valid-cfg'),
            ]));
          }
        },
      );

      final rejected = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'missing', configuration: 'invalid-cfg'),
      ]));
      final reentrant = await nested!;

      expect(rejected.connected, isFalse);
      expect(rejected.failureCode, 'E-FUSION-ADAPTER-MISSING');
      expect(reentrant.connected, isFalse);
      expect(reentrant.failureCode, 'E-FUSION-BUSY');
      expect(events.where((event) => event.startsWith('start:first:')), isEmpty);
      expect(engine.state, KingFusionState.failed);
      expect(engine.isBusy, isFalse);
    });

    test('disconnect during validation rejection waits for preflight release', () async {
      final events = <String>[];
      final adapter = _FakeAdapter('first', events);
      late final KingFusionEngine engine;
      Future<void>? disconnecting;
      var disconnectEvents = 0;
      engine = KingFusionEngine(
        [adapter],
        onEvent: (event) {
          if (event.type == KingFusionEventType.validationRejected) {
            disconnecting ??= engine.disconnect();
          }
          if (event.type == KingFusionEventType.disconnectRequested) {
            disconnectEvents++;
          }
        },
      );

      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'missing', configuration: 'invalid-cfg'),
      ]));
      await disconnecting;

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-ADAPTER-MISSING');
      expect(result.startedHops, 0);
      expect(disconnectEvents, 1);
      expect(events.where((event) => event.startsWith('start:first:')), isEmpty);
      expect(events.where((event) => event.startsWith('stop:first:')), isEmpty);
      expect(engine.state, KingFusionState.idle);
      expect(engine.isBusy, isFalse);
      expect(engine.snapshot.disconnectRequested, isFalse);
    });

    test('disconnect from failed-state observer serializes after validation', () async {
      late final KingFusionEngine engine;
      Future<void>? disconnecting;
      engine = KingFusionEngine(
        const <KingEngineAdapter>[],
        onEvent: (event) {
          if (event.type == KingFusionEventType.stateChanged &&
              event.state == KingFusionState.failed) {
            disconnecting ??= engine.disconnect();
          }
        },
      );

      final result = await engine.connect(KingFusionPlan([
        const KingFusionHop(engineId: 'not-installed', configuration: 'opaque'),
      ]));
      await disconnecting;

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-ADAPTER-MISSING');
      expect(result.startedHops, 0);
      expect(engine.state, KingFusionState.idle);
      expect(engine.isBusy, isFalse);
      expect(engine.snapshot.disconnectRequested, isFalse);
      expect(engine.snapshot.activeEngineIds, isEmpty);
    });

    test('engine descriptor snapshot isolates mutable adapter metadata', () async {
      final transports = <String>{'TCP'};
      final adapter = _MutableDescriptorAdapter(KingEngineDescriptor(
        id: 'mutable',
        title: 'Mutable descriptor',
        family: KingEngineFamily.custom,
        availability: KingEngineAvailability.integrated,
        supportedTransports: transports,
        supportsMultiHop: true,
      ));
      final engine = KingFusionEngine([adapter]);

      transports
        ..clear()
        ..add('udp');

      final descriptor = engine.availableEngines.single;
      expect(descriptor.id, 'mutable');
      expect(descriptor.supportedTransports, {'tcp'});
      expect(descriptor.supportsMultiHop, isTrue);
      expect(
        () => descriptor.supportedTransports.add('quic'),
        throwsUnsupportedError,
      );
      expect(
        () => engine.availableEngines.add(descriptor),
        throwsUnsupportedError,
      );

      // Validation must use the captured capability contract, not a mutable
      // Set still owned by the adapter implementation.
      final acceptedOriginalTransport = await engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'mutable',
          configuration: 'opaque-config',
          requiredTransport: 'tcp',
        ),
      ]));
      expect(acceptedOriginalTransport.connected, isTrue);
      await engine.disconnect();

      final rejectedMutatedTransport = await engine.connect(KingFusionPlan([
        const KingFusionHop(
          engineId: 'mutable',
          configuration: 'opaque-config',
          requiredTransport: 'udp',
        ),
      ]));
      expect(
        rejectedMutatedTransport.failureCode,
        'E-FUSION-TRANSPORT-UNSUPPORTED',
      );
    });

    test('verificationStarted observer cancellation prevents verifier invocation', () async {
      final events = <String>[];
      final adapter = _FakeAdapter('first', events);
      final verifier = _FakeTrafficVerifier(true);
      late final KingFusionEngine engine;
      Future<void>? disconnecting;
      engine = KingFusionEngine(
        [adapter],
        trafficVerifier: verifier,
        onEvent: (event) {
          if (event.type == KingFusionEventType.verificationStarted) {
            disconnecting = engine.disconnect();
          }
        },
      );

      final result = await engine.connect(KingFusionPlan(
        [const KingFusionHop(engineId: 'first', configuration: 'cfg')],
        requireTrafficVerification: true,
      ));
      await disconnecting;

      expect(result.connected, isFalse);
      expect(result.failureCode, 'E-FUSION-CANCELLED');
      expect(result.startedHops, 1);
      expect(verifier.calls, 0);
      expect(events.where((event) => event.startsWith('start:first:')).length, 1);
      expect(events.where((event) => event.startsWith('stop:first:')).length, 1);
      expect(engine.state, KingFusionState.idle);
      expect(engine.isBusy, isFalse);
    });
  });
}
