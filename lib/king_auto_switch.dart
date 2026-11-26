enum KingEngineId { xray, psiphon }

class KingEngineConnectResult {
  const KingEngineConnectResult({
    required this.started,
    required this.trafficVerified,
    this.elapsed = Duration.zero,
    this.detail = '',
  });
  final bool started;
  final bool trafficVerified;
  final Duration elapsed;
  final String detail;
  bool get healthy => started && trafficVerified;
}

abstract interface class KingConnectionAdapter {
  KingEngineId get id;
  bool get available;
  Future<KingEngineConnectResult> connect();
  Future<bool> verifyTraffic();
  Future<void> disconnect();
}

class KingAutoSwitchResult {
  const KingAutoSwitchResult({
    required this.engine,
    required this.connected,
    required this.attempts,
    this.detail = '',
  });
  final KingEngineId? engine;
  final bool connected;
  final List<KingEngineConnectResult> attempts;
  final String detail;
}

/// Xray-first, Psiphon-next coordinator. Adapters are always run serially:
/// Android must not have two competing full-device VPN services.
class KingAutoSwitchCoordinator {
  KingAutoSwitchCoordinator({required List<KingConnectionAdapter> adapters})
      : _adapters = List.unmodifiable(
          adapters.toList()..sort((a, b) => a.id.index.compareTo(b.id.index)),
        ) {
    final ids = _adapters.map((a) => a.id).toList();
    if (ids.toSet().length != ids.length) {
      throw ArgumentError('Each engine must have exactly one adapter');
    }
  }

  final List<KingConnectionAdapter> _adapters;
  KingConnectionAdapter? _active;
  Future<KingAutoSwitchResult>? _flight;
  int _generation = 0;
  bool _stoppedByUser = false;

  KingEngineId? get activeEngine => _active?.id;

  Future<KingAutoSwitchResult> connect() {
    final pending = _flight;
    if (pending != null) return pending;
    _stoppedByUser = false;
    final generation = ++_generation;
    final future = _connectInOrder(generation, _adapters);
    _flight = future;
    return future.whenComplete(() {
      if (identical(_flight, future)) _flight = null;
    });
  }

  Future<KingAutoSwitchResult> _connectInOrder(
    int generation,
    List<KingConnectionAdapter> adapters,
  ) async {
    final attempts = <KingEngineConnectResult>[];
    for (final adapter in adapters) {
      if (_stoppedByUser || generation != _generation) {
        return KingAutoSwitchResult(
          engine: null,
          connected: false,
          attempts: List.unmodifiable(attempts),
          detail: 'Connection attempt cancelled',
        );
      }
      if (!adapter.available) continue;

      final previous = _active;
      _active = null;
      if (previous != null) {
        try {
          await previous.disconnect();
        } catch (_) {}
      }

      try {
        final result = await adapter.connect();
        attempts.add(result);
        if (_stoppedByUser || generation != _generation) {
          await adapter.disconnect();
          return KingAutoSwitchResult(
            engine: null,
            connected: false,
            attempts: List.unmodifiable(attempts),
            detail: 'Connection attempt cancelled',
          );
        }
        final trafficOk = result.healthy && await adapter.verifyTraffic();
        if (_stoppedByUser || generation != _generation) {
          await adapter.disconnect();
          return KingAutoSwitchResult(
            engine: null,
            connected: false,
            attempts: List.unmodifiable(attempts),
            detail: 'Connection attempt cancelled',
          );
        }
        if (trafficOk) {
          _active = adapter;
          return KingAutoSwitchResult(
            engine: adapter.id,
            connected: true,
            attempts: List.unmodifiable(attempts),
          );
        }
      } catch (error) {
        attempts.add(KingEngineConnectResult(
          started: false,
          trafficVerified: false,
          detail: error.toString(),
        ));
      }
      try {
        await adapter.disconnect();
      } catch (_) {}
    }
    return KingAutoSwitchResult(
      engine: null,
      connected: false,
      attempts: List.unmodifiable(attempts),
      detail: 'No engine passed end-to-end traffic verification',
    );
  }

  Future<KingAutoSwitchResult> recoverFromTrafficFailure() async {
    final active = _active;
    if (active == null) return connect();
    var healthy = false;
    try {
      healthy = await active.verifyTraffic();
    } catch (_) {}
    if (healthy) {
      return KingAutoSwitchResult(
        engine: active.id,
        connected: true,
        attempts: const [],
        detail: 'Active engine remains healthy',
      );
    }
    _active = null;
    try {
      await active.disconnect();
    } catch (_) {}
    final generation = ++_generation;
    // Give every other adapter one chance, including the primary engine when
    // the active fallback has failed and Xray may have recovered meanwhile.
    return _connectInOrder(
      generation,
      _adapters.where((adapter) => !identical(adapter, active)).toList(),
    );
  }

  Future<void> disconnect() async {
    _stoppedByUser = true;
    ++_generation;
    final active = _active;
    _active = null;
    if (active != null) await active.disconnect();
  }
}

/// Adaptive batch executor for adapters which expose independent probe items.
/// It processes the entire iterable and never truncates the inventory.
class KingAdaptiveBatchRunner {
  static Future<List<R>> run<T, R>({
    required Iterable<T> items,
    required Future<R> Function(T item) probe,
    int initialBatchSize = 20,
    int Function(int previousBatchSize, int completedCount)? nextBatchSize,
  }) async {
    if (initialBatchSize < 1) {
      throw ArgumentError.value(initialBatchSize, 'initialBatchSize');
    }
    final iterator = items.iterator;
    final results = <R>[];
    var batchSize = initialBatchSize;
    var completed = 0;
    while (true) {
      final batch = <T>[];
      while (batch.length < batchSize && iterator.moveNext()) {
        batch.add(iterator.current);
      }
      if (batch.isEmpty) break;
      results.addAll(await Future.wait(batch.map(probe)));
      completed += batch.length;
      final next = nextBatchSize?.call(batchSize, completed) ?? batchSize;
      if (next < 1) throw ArgumentError.value(next, 'nextBatchSize result');
      batchSize = next;
    }
    return List.unmodifiable(results);
  }
}
