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

  KingFusionPlan(Iterable<KingFusionHop> hops)
      : hops = List<KingFusionHop>.unmodifiable(hops);
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
  final bool connected;
  final String? failedEngineId;
  final String? failureCode;
  final int startedHops;

  const KingFusionResult._({
    required this.connected,
    required this.failedEngineId,
    required this.failureCode,
    required this.startedHops,
  });

  const KingFusionResult.success(int startedHops)
      : this._(
          connected: true,
          failedEngineId: null,
          failureCode: null,
          startedHops: startedHops,
        );

  const KingFusionResult.failure({
    required String? failedEngineId,
    required String? failureCode,
    required int startedHops,
  }) : this._(
          connected: false,
          failedEngineId: failedEngineId,
          failureCode: failureCode,
          startedHops: startedHops,
        );
}

/// Coordinates only adapters that the host application has actually installed.
///
/// Multi-hop is opt-in at every edge. A missing adapter, duplicate hop, or
/// unsupported chain is rejected before any native engine is started. If a
/// later hop fails, previously started hops are stopped in reverse order.
class KingFusionEngine {
  final Map<String, KingEngineAdapter> _adapters;
  final List<({KingEngineAdapter adapter, Object? handle})> _active = [];

  KingFusionState state = KingFusionState.idle;
  bool _busy = false;

  KingFusionEngine(Iterable<KingEngineAdapter> adapters)
      : _adapters = _indexAdapters(adapters);

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

  Future<KingFusionResult> connect(KingFusionPlan plan) async {
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
    state = KingFusionState.starting;
    String? currentEngineId;
    Object? upstreamHandle;
    try {
      for (final hop in plan.hops) {
        currentEngineId = hop.engineId;
        final adapter = _adapters[hop.engineId]!;
        final result = await adapter.start(
          configuration: hop.configuration,
          upstreamHandle: upstreamHandle,
        );
        if (!result.connected) {
          final startedCount = _active.length;
          await _rollback();
          state = KingFusionState.failed;
          return KingFusionResult.failure(
            failedEngineId: currentEngineId,
            failureCode: result.failureCode ?? 'E-FUSION-START',
            startedHops: startedCount,
          );
        }
        _active.add((adapter: adapter, handle: result.handle));
        upstreamHandle = result.handle;
      }
      state = KingFusionState.connected;
      return KingFusionResult.success(_active.length);
    } catch (_) {
      final startedCount = _active.length;
      await _rollback();
      state = KingFusionState.failed;
      return KingFusionResult.failure(
        failedEngineId: currentEngineId,
        failureCode: 'E-FUSION-EXCEPTION',
        startedHops: startedCount,
      );
    } finally {
      _busy = false;
    }
  }

  (String, String)? _validate(KingFusionPlan plan) {
    if (plan.hops.isEmpty) return ( '', 'E-FUSION-EMPTY-PLAN');
    final seen = <String>{};
    final resolved = <KingEngineAdapter>[];
    for (final hop in plan.hops) {
      final id = hop.engineId.trim();
      if (!seen.add(id)) return (id, 'E-FUSION-DUPLICATE-HOP');
      final adapter = _adapters[id];
      if (adapter == null) return (id, 'E-FUSION-ADAPTER-MISSING');
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
    if (_busy) return;
    _busy = true;
    state = KingFusionState.stopping;
    try {
      await _rollback();
      state = KingFusionState.idle;
    } finally {
      _busy = false;
    }
  }

  Future<void> _rollback() async {
    for (final item in _active.reversed.toList(growable: false)) {
      try {
        await item.adapter.stop(item.handle);
      } catch (_) {
        // Continue stopping remaining hops; the host's error journal owns logs.
      }
    }
    _active.clear();
  }
}
