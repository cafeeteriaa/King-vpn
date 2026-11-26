import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/king_auto_switch.dart';
import 'package:king_vpn/king_network_engines.dart';

class FakeAdapter implements KingConnectionAdapter {
  FakeAdapter(this.id, {this.available = true, this.startOk = true,
    this.trafficOk = true, this.events});
  @override
  final String id;
  @override
  final bool available;
  final bool startOk;
  bool trafficOk;
  final List<String>? events;
  @override
  Future<KingEngineConnectResult> connect() async {
    events?.add('connect:$id');
    return KingEngineConnectResult(started: startOk, trafficVerified: trafficOk);
  }
  @override
  Future<bool> verifyTraffic() async => trafficOk;
  @override
  Future<void> disconnect() async => events?.add('disconnect:$id');
}

class BlockingAdapter implements KingConnectionAdapter {
  BlockingAdapter(this.delegate, this.started);
  final FakeAdapter delegate;
  final Completer<KingEngineConnectResult> started;
  @override
  String get id => delegate.id;
  @override
  bool get available => delegate.available;
  @override
  Future<KingEngineConnectResult> connect() => started.future;
  @override
  Future<bool> verifyTraffic() => delegate.verifyTraffic();
  @override
  Future<void> disconnect() => delegate.disconnect();
}

void main() {
  group('KING multi-engine coordinator', () {
    test('Xray stays primary and VPN Gate is the next configured full VPN', () async {
      final events = <String>[];
      final result = await KingAutoSwitchCoordinator(adapters: [
        FakeAdapter(KingEngineId.vpnGate, events: events),
        FakeAdapter(KingEngineId.xray, trafficOk: false, events: events),
      ]).connect();
      expect(result.connected, isTrue);
      expect(result.engine, KingEngineId.vpnGate);
      expect(events, [
        'connect:xray',
        'disconnect:xray',
        'connect:vpn_gate',
      ]);
    });

    test('does not start unavailable engines', () async {
      final events = <String>[];
      final result = await KingAutoSwitchCoordinator(adapters: [
        FakeAdapter(KingEngineId.xray, available: false, events: events),
        FakeAdapter(KingEngineId.tor, events: events),
      ]).connect();
      expect(result.engine, KingEngineId.tor);
      expect(events, ['connect:tor']);
    });

    test('user disconnect cancels a late engine startup', () async {
      final started = Completer<KingEngineConnectResult>();
      final events = <String>[];
      final adapter = FakeAdapter(KingEngineId.xray, events: events);
      final blocking = BlockingAdapter(adapter, started);
      final coordinator = KingAutoSwitchCoordinator(adapters: [blocking]);
      final pending = coordinator.connect();
      await Future<void>.delayed(Duration.zero);
      await coordinator.disconnect();
      started.complete(const KingEngineConnectResult(
        started: true,
        trafficVerified: true,
      ));
      final result = await pending;
      expect(result.connected, isFalse);
      expect(result.engine, isNull);
      expect(events, ['disconnect:xray']);
    });

    test('rejects duplicate adapter identifiers', () {
      expect(() => KingAutoSwitchCoordinator(adapters: [
        FakeAdapter(KingEngineId.xray),
        FakeAdapter(KingEngineId.xray),
      ]), throwsArgumentError);
    });

    test('does not accept CONNECTED without data-plane proof', () async {
      final result = await KingAutoSwitchCoordinator(adapters: [
        FakeAdapter(KingEngineId.xray, trafficOk: false),
      ]).connect();
      expect(result.connected, isFalse);
      expect(result.engine, isNull);
    });

    test('recovers from a failed secondary engine back to Xray', () async {
      final events = <String>[];
      final xray = FakeAdapter(KingEngineId.xray, trafficOk: false, events: events);
      final tor = FakeAdapter(KingEngineId.tor, events: events);
      final coordinator = KingAutoSwitchCoordinator(adapters: [xray, tor]);
      final initial = await coordinator.connect();
      expect(initial.engine, KingEngineId.tor);
      xray.trafficOk = true;
      tor.trafficOk = false;
      final recovered = await coordinator.recoverFromTrafficFailure();
      expect(recovered.engine, KingEngineId.xray);
      expect(recovered.connected, isTrue);
    });
  });

  group('Extensible engine catalog', () {
    test('contains the twelve alternatives without Psiphon', () {
      final catalog = KingNetworkEngineCatalog();
      final alternatives = catalog.all.where((engine) => engine.id != KingEngineId.xray);
      expect(alternatives, hasLength(12));
      expect(catalog[KingEngineId.vpnGate]?.role, KingEngineRole.fullDeviceVpn);
      expect(catalog[KingEngineId.ceno]?.role, KingEngineRole.browserNetwork);
      expect(catalog[KingEngineId.byeDpi]?.role, KingEngineRole.localTransport);
    });

    test('allows future engines without a fixed inventory ceiling', () {
      final catalog = KingNetworkEngineCatalog();
      catalog.register(const KingEngineDescriptor(
        id: 'future_engine',
        name: 'Future Engine',
        role: KingEngineRole.fullDeviceVpn,
        state: KingIntegrationState.sourceAndLicenseReviewRequired,
        priority: 200,
        summary: 'Dynamically registered adapter.',
      ));
      expect(catalog['future_engine']?.name, 'Future Engine');
    });
  });

  group('Adaptive batches', () {
    test('processes every item while increasing batch sizes', () async {
      final seen = <int>[];
      final result = await KingAdaptiveBatchRunner.run<int, int>(
        items: List<int>.generate(75, (i) => i),
        initialBatchSize: 20,
        probe: (item) async { seen.add(item); return item * 2; },
        nextBatchSize: (previous, completed) => completed == 20 ? 30 : 25,
      );
      expect(seen, List<int>.generate(75, (i) => i));
      expect(result.map((item) => item.value).toList(), List<int>.generate(75, (i) => i * 2));
    });

    test('records a failed probe and continues through the inventory', () async {
      final result = await KingAdaptiveBatchRunner.run<int, int>(
        items: List<int>.generate(45, (i) => i),
        initialBatchSize: 20,
        probe: (item) async {
          if (item == 7) throw StateError('probe failed');
          return item;
        },
      );
      expect(result, hasLength(45));
      expect(result[7].succeeded, isFalse);
      expect(result[7].error, isA<StateError>());
      expect(result.where((item) => item.succeeded), hasLength(44));
    });

    test('rejects an invalid batch size', () async {
      await expectLater(
        KingAdaptiveBatchRunner.run<int, int>(
          items: const [1],
          initialBatchSize: 0,
          probe: (item) async => item,
        ),
        throwsArgumentError,
      );
    });
  });
}
