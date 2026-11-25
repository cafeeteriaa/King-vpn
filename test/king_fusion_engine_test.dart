import 'package:flutter_test/flutter_test.dart';
import '../lib/king_fusion_engine.dart';

class _FakeAdapter implements KingEngineAdapter {
  @override
  final KingEngineDescriptor descriptor;
  final List<String> events;
  final bool failStart;
  final Set<String> chainTargets;

  _FakeAdapter(
    String id,
    this.events, {
    this.failStart = false,
    this.chainTargets = const <String>{},
    bool supportsMultiHop = true,
  }) : descriptor = KingEngineDescriptor(
          id: id,
          title: id,
          family: KingEngineFamily.custom,
          availability: KingEngineAvailability.integrated,
          supportsMultiHop: supportsMultiHop,
        );

  @override
  bool canChainTo(KingEngineAdapter next) =>
      chainTargets.contains(next.descriptor.id);

  @override
  Future<KingEngineStartResult> start({
    required String configuration,
    Object? upstreamHandle,
  }) async {
    events.add('start:${descriptor.id}:${upstreamHandle ?? '-'}');
    if (failStart) return const KingEngineStartResult.failed('E-TEST-START');
    return KingEngineStartResult.connected('handle-${descriptor.id}');
  }

  @override
  Future<void> stop(Object? handle) async {
    events.add('stop:${descriptor.id}:$handle');
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

void main() {
  group('KING Fusion Engine', () {
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
  });
}
