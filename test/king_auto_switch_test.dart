import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/king_auto_switch.dart';

class FakeAdapter implements KingConnectionAdapter {
  FakeAdapter(this.id, {this.available = true, this.startOk = true,
    this.trafficOk = true, this.events});
  @override
  final KingEngineId id;
  @override
  final bool available;
  final bool startOk;
  bool trafficOk;
  final List<String>? events;
  @override
  Future<KingEngineConnectResult> connect() async {
    events?.add('connect:${id.name}');
    return KingEngineConnectResult(started: startOk, trafficVerified: trafficOk);
  }
  @override
  Future<bool> verifyTraffic() async => trafficOk;
  @override
  Future<void> disconnect() async => events?.add('disconnect:${id.name}');
}

void main() {
  group('KING AutoSwitch', () {
    test('tries Xray before Psiphon and verifies actual traffic', () async {
      final events = <String>[];
      final xray = FakeAdapter(KingEngineId.xray, trafficOk: false, events: events);
      final psiphon = FakeAdapter(KingEngineId.psiphon, events: events);
      final result = await KingAutoSwitchCoordinator(
        adapters: [xray, psiphon],
      ).connect();
      expect(result.connected, isTrue);
      expect(result.engine, KingEngineId.psiphon);
      expect(events, ['connect:xray', 'disconnect:xray', 'connect:psiphon']);
    });

    test('does not start unavailable engines', () async {
      final events = <String>[];
      final result = await KingAutoSwitchCoordinator(adapters: [
        FakeAdapter(KingEngineId.xray, available: false, events: events),
        FakeAdapter(KingEngineId.psiphon, events: events),
      ]).connect();
      expect(result.engine, KingEngineId.psiphon);
      expect(events, ['connect:psiphon']);
    });

    test('rejects duplicate engine adapters', () {
      expect(() => KingAutoSwitchCoordinator(adapters: [
        FakeAdapter(KingEngineId.xray),
        FakeAdapter(KingEngineId.xray),
      ]), throwsArgumentError);
    });

    test('does not accept core CONNECTED without data-plane proof', () async {
      final result = await KingAutoSwitchCoordinator(adapters: [
        FakeAdapter(KingEngineId.xray, trafficOk: false),
      ]).connect();
      expect(result.connected, isFalse);
      expect(result.engine, isNull);
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
      expect(result, List<int>.generate(75, (i) => i * 2));
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
