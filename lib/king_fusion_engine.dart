import 'dart:async';

/// KING Fusion Engine foundation.
///
/// This module defines an honest adapter boundary for multi-engine routing.
/// It does not claim that an engine is bundled merely because it has a descriptor.
/// Only adapters explicitly injected by the application can be executed.
enum KingEngineFamily { xray, singBox, wireGuard, amneziaWG, psiphon, tor, custom }

enum KingEngineAvailability {
  /// A native adapter is installed and supplied to the fusion engine.
  integrated,
  /// The engine is known, but its native runtime/adapter is not installed.
  adapterRequired,
}

class KingEngineDescriptor {
  final String id;
  final String title;
  final KingEngineFamily family;
  final KingEngineAvailability availability;
  final Set<String> supportedTransports;
  final bool supportsMultiHop;

  const KingEngineDescriptor({
    required this.id,
    required this.title,
    required this.family,
    required this.availability,
    this.supportedTransports = const <String>{},
    this.supportsMultiHop = false,
  });
}

class KingFusionHop {
  /// Stable adapter id. Configuration is intentionally opaque to this layer.
  final String engineId;
  final String configuration;

  const KingFusionHop({
    required this.engineId,
    required this.configuration,
  });
}

class KingFusionPlan {
  final List<KingFusionHop> hops;
  /// Require a real data-plane probe after every native hop has started.
  final bool requireTrafficVerification;

  KingFusionPlan(
    Iterable<KingFusionHop> hops, {
    this.requireTrafficVerification = false,
  }) : hops = List<KingFusionHop>.unmodifiable(hops);
}

/// Verifies traffic through the resulting route, not merely native start state.
abstract interface class KingFusionTrafficVerifier {
  Future<bool> verify(KingFusionPlan plan);
}

class KingEngineStartResult {
  final bool connected;
  /// Opaque native handle; never serialize or log it.
  final Object? handle;
  final String? failureCode;

  const KingEngineStartResult.connected([this.handle])
      : connected = true,
        failureCode = null;

  const KingEngineStartResult.failed(this.failureCode)
      : connected = false,
        handle = null;
}

abstract interface class KingEngineAdapter {
  KingEngineDescriptor get descriptor;

  /// Start this hop over the preceding hop, when supplied.
  Future<KingEngineStartResult> start({
    required String configuration,
    Object? upstreamHandle,
  });

  Future<void> stop(Object? handle);

  /// Explicit compatibility contract; false by default in adapters.
  bool canChainTo(KingEngineAdapter next);
}

enum KingFusionState { idle, starting, connected, stopping, failed }

class KingFusionResult {
  /// All adapters accepted their start calls; this is not end-to-end traffic proof.
  final bool connected;
  /// True only when the plan requested and passed a traffic verifier.
  final bool trafficVerified;
  final String? failedEngineId;
  final String? failureCode;
  final int startedHops;
  /// Engines whose native stop operation failed and still need cleanup.
  final List<String> cleanupFailedEngineIds;

  const KingFusionResult._({
    required this.connected,
    required this.trafficVerified,
    required this.failedEngineId,
    required this.failureCode,
    required this.startedHops,
    this.cleanupFailedEngineIds = const <String>[],
  });

  const KingFusionResult.success(
    int startedHops, {
    bool trafficVerified = false,
  }) : this._(
          connected: true,
          trafficVerified: trafficVerified,
          failedEngineId: null,
          failureCode: null,
          startedHops: startedHops,
        );

  const KingFusionResult.failure({
    required String? failedEngineId,
    required String? failureCode,
    required int startedHops,
    List<String> cleanupFailedEngineIds = const <String>[],
  }) : this._(
          connected: false,
          trafficVerified: false,
          failedEngineId: failedEngineId,
          failureCode: failureCode,
          startedHops: startedHops,
          cleanupFailedEngineIds: cleanupFailedEngineIds,
        );
}

/// Coordinates only adapters that the host application has actually installed.
///
/// Multi-hop is opt-in at every edge. A missing adapter, duplicate hop, or
/// unsupported chain is rejected before any native engine is started. If a
/// later hop fails, previously started hops are stopped in reverse order.
class KingFusionEngine {
  final Map<String, KingEngineAdapter> _adapters;
  final KingFusionTrafficVerifier? _trafficVerifier;
  final Duration trafficVerificationTimeout;
  final List<({KingEngineAdapter adapter, Object? handle})> _active = [];

  KingFusionState state = KingFusionState.idle;
  bool _busy = false;
  bool _disconnectRequested = false;
  Completer<void>? _operationDone;

  KingFusionEngine(
    Iterable<KingEngineAdapter> adapters, {
    KingFusionTrafficVerifier? trafficVerifier,
    this.trafficVerificationTimeout = const Duration(seconds: 12),
  })  : _adapters = _indexAdapters(adapters),
        _trafficVerifier = trafficVerifier {
    if (trafficVerificationTimeout <= Duration.zero) {
      throw ArgumentError.value(
        trafficVerificationTimeout,
        'trafficVerificationTimeout',
        'Must be positive',
      );
    }
  }

  static Map<String, KingEngineAdapter> _indexAdapters(
    Iterable<KingEngineAdapter> adapters,
  ) {
    final result = <String, KingEngineAdapter>{};
    for (final adapter in adapters) {
      final id = adapter.descriptor.id.trim();
      if (id.isEmpty) {
        throw ArgumentError('Engine adapter id must not be empty');
      }
      if (result.containsKey(id)) {
        throw ArgumentError('Duplicate engine adapter: $id');
      }
      result[id] = adapter;
    }
    return Map<String, KingEngineAdapter>.unmodifiable(result);
  }

  List<KingEngineDescriptor> get availableEngines =>
      List<KingEngineDescriptor>.unmodifiable(
        _adapters.values.map((adapter) => adapter.descriptor),
      );

  /// Adapter IDs still tracked because native cleanup has not succeeded.
  List<String> get cleanupPendingEngineIds =>
      List<String>.unmodifiable(
        _active.map((item) => item.adapter.descriptor.id),
      );

  bool get isBusy => _busy;

  Future<KingFusionResult> connect(KingFusionPlan plan) async {
    if (_disconnectRequested) {
      return const KingFusionResult.failure(
        failedEngineId: null,
        failureCode: 'E-FUSION-DISCONNECT-PENDING',
        startedHops: 0,
      );
    }
    if (_busy) {
      return const KingFusionResult.failure(
        failedEngineId: null,
        failureCode: 'E-FUSION-BUSY',
        startedHops: 0,
      );
    }
    if (_active.isNotEmpty || state == KingFusionState.connected) {
      return const KingFusionResult.failure(
        failedEngineId: null,
        failureCode: 'E-FUSION-ALREADY-ACTIVE',
        startedHops: 0,
      );
    }

    final validationError = _validate(plan);
    if (validationError != null) {
      state = KingFusionState.failed;
      return KingFusionResult.failure(
        failedEngineId: validationError.$1,
        failureCode: validationError.$2,
        startedHops: 0,
      );
    }

    _busy = true;
    _disconnectRequested = false;
    _operationDone = Completer<void>();
    state = KingFusionState.starting;
    String? currentEngineId;
    Object? upstreamHandle;
    try {
      for (final hop in plan.hops) {
        if (_disconnectRequested) {
          final startedCount = _active.length;
          final cleanupFailures = await _rollback();
          state = KingFusionState.failed;
          return KingFusionResult.failure(
            failedEngineId: null,
            failureCode: 'E-FUSION-CANCELLED',
            startedHops: startedCount,
            cleanupFailedEngineIds: cleanupFailures,
          );
        }
        currentEngineId = hop.engineId.trim();
        final adapter = _adapters[currentEngineId]!;
        final result = await adapter.start(
          configuration: hop.configuration,
          upstreamHandle: upstreamHandle,
        );
        if (!result.connected) {
          final startedCount = _active.length;
          final cleanupFailures = await _rollback();
          state = KingFusionState.failed;
          return KingFusionResult.failure(
            failedEngineId: currentEngineId,
            failureCode: result.failureCode ?? 'E-FUSION-START',
            startedHops: startedCount,
            cleanupFailedEngineIds: cleanupFailures,
          );
        }
        _active.add((adapter: adapter, handle: result.handle));
        upstreamHandle = result.handle;
        if (_disconnectRequested) {
          final startedCount = _active.length;
          final cleanupFailures = await _rollback();
          state = KingFusionState.failed;
          return KingFusionResult.failure(
            failedEngineId: currentEngineId,
            failureCode: 'E-FUSION-CANCELLED',
            startedHops: startedCount,
            cleanupFailedEngineIds: cleanupFailures,
          );
        }
      }
      if (plan.requireTrafficVerification) {
        final verifier = _trafficVerifier;
        if (verifier == null) {
          final startedCount = _active.length;
          final cleanupFailures = await _rollback();
          state = KingFusionState.failed;
          return KingFusionResult.failure(
            failedEngineId: null,
            failureCode: 'E-FUSION-VERIFIER-MISSING',
            startedHops: startedCount,
            cleanupFailedEngineIds: cleanupFailures,
          );
        }
        final verified = await verifier
            .verify(plan)
            .timeout(trafficVerificationTimeout);
        if (_disconnectRequested) {
          final startedCount = _active.length;
          final cleanupFailures = await _rollback();
          state = KingFusionState.failed;
          return KingFusionResult.failure(
            failedEngineId: null,
            failureCode: 'E-FUSION-CANCELLED',
            startedHops: startedCount,
            cleanupFailedEngineIds: cleanupFailures,
          );
        }
        if (!verified) {
          final startedCount = _active.length;
          final cleanupFailures = await _rollback();
          state = KingFusionState.failed;
          return KingFusionResult.failure(
            failedEngineId: null,
            failureCode: 'E-FUSION-TRAFFIC-UNVERIFIED',
            startedHops: startedCount,
            cleanupFailedEngineIds: cleanupFailures,
          );
        }
      }
      state = KingFusionState.connected;
      return KingFusionResult.success(
        _active.length,
        trafficVerified: plan.requireTrafficVerification,
      );
    } on TimeoutException {
      final startedCount = _active.length;
      final cleanupFailures = await _rollback();
      state = KingFusionState.failed;
      return KingFusionResult.failure(
        failedEngineId: currentEngineId,
        failureCode: 'E-FUSION-VERIFY-TIMEOUT',
        startedHops: startedCount,
        cleanupFailedEngineIds: cleanupFailures,
      );
    } catch (_) {
      final startedCount = _active.length;
      final cleanupFailures = await _rollback();
      state = KingFusionState.failed;
      return KingFusionResult.failure(
        failedEngineId: currentEngineId,
        failureCode: 'E-FUSION-EXCEPTION',
        startedHops: startedCount,
        cleanupFailedEngineIds: cleanupFailures,
      );
    } finally {
      _busy = false;
      // Keep the cancellation latch raised until the waiting disconnect()
      // acquires the operation slot; otherwise a new connect could slip into
      // the microtask gap between completing this operation and its waiter.
      _operationDone?.complete();
      _operationDone = null;
    }
  }

  (String, String)? _validate(KingFusionPlan plan) {
    if (plan.hops.isEmpty) return ('', 'E-FUSION-EMPTY-PLAN');
    if (plan.requireTrafficVerification && _trafficVerifier == null) {
      return ('', 'E-FUSION-VERIFIER-MISSING');
    }
    final seen = <String>{};
    final resolved = <KingEngineAdapter>[];
    for (final hop in plan.hops) {
      final id = hop.engineId.trim();
      if (!seen.add(id)) return (id, 'E-FUSION-DUPLICATE-HOP');
      final adapter = _adapters[id];
      if (adapter == null) return (id, 'E-FUSION-ADAPTER-MISSING');
      if (adapter.descriptor.availability != KingEngineAvailability.integrated) {
        return (id, 'E-FUSION-ADAPTER-NOT-INTEGRATED');
      }
      if (hop.configuration.trim().isEmpty) {
        return (id, 'E-FUSION-CONFIG-EMPTY');
      }
      resolved.add(adapter);
    }
    for (var i = 0; i + 1 < resolved.length; i++) {
      final current = resolved[i];
      final next = resolved[i + 1];
      if (!current.descriptor.supportsMultiHop ||
          !current.canChainTo(next)) {
        return (current.descriptor.id, 'E-FUSION-CHAIN-UNSUPPORTED');
      }
    }
    return null;
  }

  Future<void> disconnect() async {
    if (_busy) {
      // A disconnect request must not disappear while a native start is in
      // flight. Ask connect() to roll back as soon as that start completes.
      _disconnectRequested = true;
      final pending = _operationDone?.future;
      if (pending != null) await pending;
    }
    if (_busy) return;
    _busy = true;
    _disconnectRequested = false;
    _operationDone = Completer<void>();
    state = KingFusionState.stopping;
    try {
      await _rollback();
      state = _active.isEmpty ? KingFusionState.idle : KingFusionState.failed;
    } finally {
      _busy = false;
      _operationDone?.complete();
      _operationDone = null;
    }
  }

  /// Failed stops remain tracked so a later disconnect can retry cleanup.
  Future<List<String>> _rollback() async {
    final failed = <({KingEngineAdapter adapter, Object? handle})>[];
    for (final item in _active.reversed.toList(growable: false)) {
      try {
        await item.adapter.stop(item.handle);
      } catch (_) {
        failed.add(item);
      }
    }
    _active
      ..clear()
      ..addAll(failed.reversed);
    return failed
        .map((item) => item.adapter.descriptor.id)
        .toList(growable: false);
  }

}
