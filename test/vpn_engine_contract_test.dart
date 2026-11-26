import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../lib/vpn_engine_contract.dart';

class FakeEngineAdapter implements KingVpnEngineAdapter {
  FakeEngineAdapter(this.descriptor, {this.available = true, this.health});

  @override
  final KingEngineDescriptor descriptor;
  final bool available;
  final KingEngineHealth? health;
  final List<String> calls = <String>[];
  bool failStart = false;
  bool failHealth = false;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> prepare() async {
    calls.add('prepare');
  }

  @override
  Future<void> start(KingEngineStartRequest request) async {
    calls.add('start');
    if (failStart) throw StateError('start failed');
  }

  @override
  Future<KingEngineHealth> checkHealth() async {
    calls.add('health');
    if (failHealth) throw StateError('health failed');
    return health ??
        const KingEngineHealth(
          coreConnected: true,
          dataPlaneVerified: true,
        );
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
  }
}

KingEngineDescriptor descriptor(String id) => KingEngineDescriptor(
      id: id,
      name: id,
      kind: KingEngineKind.fullDeviceTunnel,
      integrationNote: 'test adapter',
    );

void main() {
  group('KingEngineCatalog', () {
    test('contains the complete requested technology inventory', () {
      final catalog = KingEngineCatalog();
      for (final id in <String>[
        'psiphon',
        'tor',
        'vpn_gate',
        'nthlink',
        'calyx_vpn',
        'cloudflare_warp',
        'lantern',
        'avira_phantom',
        'shroudly',
        'ceno',
        'byedpi',
        'powertunnel',
        'i2p',
      ]) {
        expect(catalog[id], isNotNull, reason: 'Missing $id');
      }
      expect(catalog.all.length, greaterThanOrEqualTo(13));
    });

    test('allows registering additional discovered technologies', () {
      final catalog = KingEngineCatalog();
      catalog.register(descriptor('future_engine'));
      expect(catalog['future_engine']?.name, 'future_engine');
    });

    test('rejects duplicate identifiers rather than silently replacing them', () {
      final catalog = KingEngineCatalog();
      expect(
        () => catalog.register(descriptor('psiphon')),
        throwsStateError,
      );
    });
  });

  group('KingVpnEngineCoordinator', () {
    test('does not claim an engine is available without an executable adapter', () async {
      final coordinator = KingVpnEngineCoordinator();
      await expectLater(
        coordinator.start(
          'psiphon',
          const KingEngineStartRequest(configuration: 'opaque'),
        ),
        throwsStateError,
      );
      expect(coordinator.activeEngineId, isNull);
    });

    test('requires data-plane proof, not only core CONNECTED', () async {
      final coordinator = KingVpnEngineCoordinator();
      final adapter = FakeEngineAdapter(
        descriptor('psiphon'),
        health: const KingEngineHealth(
          coreConnected: true,
          dataPlaneVerified: false,
          detail: 'No verified traffic through tunnel',
        ),
      );
      coordinator.registerAdapter(adapter);

      final session = await coordinator.start(
        'psiphon',
        const KingEngineStartRequest(configuration: 'opaque'),
      );

      expect(session.state, KingEngineState.degraded);
      expect(session.operational, isFalse);
      expect(coordinator.activeEngineId, isNull);
      expect(adapter.calls, contains('stop'));
    });

    test('stops the previous adapter before starting another', () async {
      final coordinator = KingVpnEngineCoordinator();
      final first = FakeEngineAdapter(descriptor('first'));
      final second = FakeEngineAdapter(descriptor('second'));
      coordinator.registerAdapter(first);
      coordinator.registerAdapter(second);
      const request = KingEngineStartRequest(configuration: 'opaque');

      expect((await coordinator.start('first', request)).operational, isTrue);
      expect((await coordinator.start('second', request)).operational, isTrue);
      expect(coordinator.activeEngineId, 'second');
      expect(first.calls, contains('stop'));
      expect(second.calls, contains('start'));
    });

    test('cleans up the adapter when startup fails', () async {
      final coordinator = KingVpnEngineCoordinator();
      final adapter = FakeEngineAdapter(descriptor('broken'))..failStart = true;
      coordinator.registerAdapter(adapter);

      await expectLater(
        coordinator.start(
          'broken',
          const KingEngineStartRequest(configuration: 'opaque'),
        ),
        throwsStateError,
      );

      expect(adapter.calls, contains('stop'));
      expect(coordinator.activeEngineId, isNull);
    });

    test('cleans up the adapter when health verification throws', () async {
      final coordinator = KingVpnEngineCoordinator();
      final adapter = FakeEngineAdapter(descriptor('broken'))..failHealth = true;
      coordinator.registerAdapter(adapter);

      await expectLater(
        coordinator.start(
          'broken',
          const KingEngineStartRequest(configuration: 'opaque'),
        ),
        throwsStateError,
      );

      expect(adapter.calls, contains('stop'));
      expect(coordinator.activeEngineId, isNull);
    });

    test('rejects concurrent lifecycle transitions', () async {
      final coordinator = KingVpnEngineCoordinator();
      final adapter = FakeEngineAdapter(descriptor('slow'));
      final enteredAvailability = Completer<void>();
      final releaseAvailability = Completer<void>();

      final blockingAdapter = _BlockingAvailabilityAdapter(
        adapter,
        enteredAvailability,
        releaseAvailability,
      );
      coordinator.registerAdapter(blockingAdapter);

      final startFuture = coordinator.start(
        'slow',
        const KingEngineStartRequest(configuration: 'opaque'),
      );
      await enteredAvailability.future;
      expect(coordinator.transitioning, isTrue);
      await expectLater(coordinator.stopActive(), throwsStateError);

      releaseAvailability.complete();
      expect((await startFuture).operational, isTrue);
      await coordinator.stopActive();
      expect(coordinator.activeEngineId, isNull);
    });
  });
}

class _BlockingAvailabilityAdapter implements KingVpnEngineAdapter {
  _BlockingAvailabilityAdapter(
    this.delegate,
    this.entered,
    this.release,
  );

  final FakeEngineAdapter delegate;
  final Completer<void> entered;
  final Completer<void> release;

  @override
  KingEngineDescriptor get descriptor => delegate.descriptor;

  @override
  Future<bool> isAvailable() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return true;
  }

  @override
  Future<void> prepare() => delegate.prepare();

  @override
  Future<void> start(KingEngineStartRequest request) => delegate.start(request);

  @override
  Future<KingEngineHealth> checkHealth() => delegate.checkHealth();

  @override
  Future<void> stop() => delegate.stop();

  @override
  Future<void> dispose() => delegate.dispose();
}
