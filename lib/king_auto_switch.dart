import 'king_network_engines.dart';

abstract final class KingEngineId {
  static const xray = 'xray';
  static const hysteria2 = 'hysteria2';
  static const singBox = 'sing_box';
  static const nthLink = 'nthlink';
  static const shroudly = 'shroudly';
  static const byeDpi = 'byedpi';
  static const powerTunnel = 'powertunnel';
  static const amneziaWg = 'amneziawg';
  static const openVpn = 'openvpn';
  static const shadowsocks = 'shadowsocks';
  static const openConnect = 'openconnect';
  static const wireGuard = 'wireguard';
}

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
  String get id;
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
  final String? engine;
  final bool connected;
  final List<KingEngineConnectResult> attempts;
  final String detail;
}

/// Adapters run serially. A new VPN owner starts only after the previous
/// adapter's disconnect future completes and releases its Android TUN.
class KingAutoSwitchCoordinator {
  factory KingAutoSwitchCoordinator({
    required List<KingConnectionAdapter> adapters,
    KingNetworkEngineCatalog? catalog,
  }) {
    final registry = catalog ?? KingNetworkEngineCatalog();
    final eligible = adapters.where((adapter) {
      final role = registry[adapter.id]?.role;
      // Local DPI/proxy modules are composed inside a tunnel; they must never
      // be treated as independent Android VPN owners.
      return role == KingEngineRole.fullDeviceVpn;
    }).toList(growable: false);
    final indexed = eligible.asMap().entries.toList()
      ..sort((a, b) {
        final byPriority = registry.priorityOf(a.value.id)
            .compareTo(registry.priorityOf(b.value.id));
        return byPriority != 0 ? byPriority : a.key.compareTo(b.key);
      });
    final sorted = indexed.map((entry) => entry.value).toList(growable: false);
    final ids = sorted.map((adapter) => adapter.id).toList();
    if (ids.toSet().length != ids.length) {
      throw ArgumentError('Each engine must have exactly one adapter');
    }
    return KingAutoSwitchCoordinator._(sorted, registry);
  }

  KingAutoSwitchCoordinator._(this._adapters, this.catalog);

  final List<KingConnectionAdapter> _adapters;
  final KingNetworkEngineCatalog catalog;
  KingConnectionAdapter? _active;
  KingConnectionAdapter? _starting;
  Future<KingAutoSwitchResult>? _flight;
  int _generation = 0;
  bool _stoppedByUser = false;

  String? get activeEngine => _active?.id;

  Future<KingAutoSwitchResult> connect() async {
    final pending = _flight;
    if (pending != null) {
      if (!_stoppedByUser) return pending;
      await pending;
      return connect();
    }
    _stoppedByUser = false;
    final generation = ++_generation;
    late final Future<KingAutoSwitchResult> tracked;
    tracked = _connectInOrder(generation, _adapters).whenComplete(() {
      if (identical(_flight, tracked)) _flight = null;
    });
    _flight = tracked;
    return tracked;
  }

  Future<KingAutoSwitchResult> _connectInOrder(
    int generation,
    List<KingConnectionAdapter> adapters,
  ) async {
    final attempts = <KingEngineConnectResult>[];
    for (final adapter in adapters) {
      if (_stoppedByUser || generation != _generation) {
        return KingAutoSwitchResult(engine: null, connected: false,
            attempts: List.unmodifiable(attempts), detail: 'Connection attempt cancelled');
      }
      if (!adapter.available) continue;
      final previous = _active;
      _active = null;
      if (previous != null) {
        try {
          await previous.disconnect();
        } catch (error) {
          return KingAutoSwitchResult(
            engine: null, connected: false,
            attempts: List.unmodifiable(attempts),
            detail: 'Previous VPN owner did not confirm TUN release; failover halted: $error',
          );
        }
      }
      _starting = adapter;
      try {
        final result = await adapter.connect();
        attempts.add(result);
        if (_stoppedByUser || generation != _generation) {
          await adapter.disconnect();
          return KingAutoSwitchResult(engine: null, connected: false,
              attempts: List.unmodifiable(attempts), detail: 'Connection attempt cancelled');
        }
        final trafficOk = result.healthy && await adapter.verifyTraffic();
        if (_stoppedByUser || generation != _generation) {
          await adapter.disconnect();
          return KingAutoSwitchResult(engine: null, connected: false,
              attempts: List.unmodifiable(attempts), detail: 'Connection attempt cancelled');
        }
        if (trafficOk) {
          _starting = null;
          _active = adapter;
          return KingAutoSwitchResult(engine: adapter.id, connected: true,
              attempts: List.unmodifiable(attempts));
        }
      } catch (error) {
        if (identical(_starting, adapter)) _starting = null;
        attempts.add(KingEngineConnectResult(started: false,
            trafficVerified: false, detail: error.toString()));
      }
      if (identical(_starting, adapter)) _starting = null;
      try {
        await adapter.disconnect();
      } catch (error) {
        return KingAutoSwitchResult(
          engine: null, connected: false,
          attempts: List.unmodifiable(attempts),
          detail: 'Engine teardown failed; next VPN owner was not started: $error',
        );
      }
    }
    return KingAutoSwitchResult(engine: null, connected: false,
        attempts: List.unmodifiable(attempts),
        detail: 'No engine passed end-to-end traffic verification');
  }

  Future<KingAutoSwitchResult> recoverFromTrafficFailure() {
    final pending = _flight;
    if (pending != null) return pending;
    late final Future<KingAutoSwitchResult> tracked;
    tracked = _recoverFromTrafficFailure().whenComplete(() {
      if (identical(_flight, tracked)) _flight = null;
    });
    _flight = tracked;
    return tracked;
  }

  Future<KingAutoSwitchResult> _recoverFromTrafficFailure() async {
    final generationAtStart = _generation;
    if (_stoppedByUser) {
      return const KingAutoSwitchResult(engine: null, connected: false,
          attempts: [], detail: 'Connection attempt cancelled');
    }
    final active = _active;
    if (active == null) return _connectInOrder(++_generation, _adapters);
    var healthy = false;
    try { healthy = await active.verifyTraffic(); } catch (_) {}
    if (_stoppedByUser || generationAtStart != _generation) {
      return const KingAutoSwitchResult(engine: null, connected: false,
          attempts: [], detail: 'Connection attempt cancelled');
    }
    if (healthy) {
      return KingAutoSwitchResult(engine: active.id, connected: true,
          attempts: const [], detail: 'Active engine remains healthy');
    }
    _active = null;
    try {
      await active.disconnect();
    } catch (error) {
      return KingAutoSwitchResult(
        engine: null, connected: false, attempts: const [],
        detail: 'Active VPN owner did not confirm TUN release; recovery halted: $error',
      );
    }
    if (_stoppedByUser || generationAtStart != _generation) {
      return const KingAutoSwitchResult(engine: null, connected: false,
          attempts: [], detail: 'Connection attempt cancelled');
    }
    final generation = ++_generation;
    return _connectInOrder(generation,
        _adapters.where((adapter) => !identical(adapter, active)).toList());
  }

  Future<void> disconnect() async {
    _stoppedByUser = true;
    ++_generation;
    final active = _active;
    final starting = _starting;
    _active = null;
    _starting = null;
    if (active != null) await active.disconnect();
    if (starting != null && !identical(starting, active)) await starting.disconnect();
  }
}

class KingProbeResult<R> {
  const KingProbeResult.success(this.value) : error = null, stackTrace = null;
  const KingProbeResult.failure(this.error, this.stackTrace) : value = null;
  final R? value;
  final Object? error;
  final StackTrace? stackTrace;
  bool get succeeded => error == null;
}

/// Consumes the complete iterable; batch size is an execution parameter,
/// never an inventory or result-count ceiling.
class KingAdaptiveBatchRunner {
  static Future<List<KingProbeResult<R>>> run<T, R>({
    required Iterable<T> items,
    required Future<R> Function(T item) probe,
    int initialBatchSize = 20,
    int Function(int previousBatchSize, int completedCount)? nextBatchSize,
  }) async {
    if (initialBatchSize < 1) {
      throw ArgumentError.value(initialBatchSize, 'initialBatchSize');
    }
    final iterator = items.iterator;
    final results = <KingProbeResult<R>>[];
    var batchSize = initialBatchSize;
    var completed = 0;
    while (true) {
      final batch = <T>[];
      while (batch.length < batchSize && iterator.moveNext()) {
        batch.add(iterator.current);
      }
      if (batch.isEmpty) break;
      final batchResults = await Future.wait(batch.map((item) async {
        try {
          return KingProbeResult<R>.success(await probe(item));
        } catch (error, stackTrace) {
          return KingProbeResult<R>.failure(error, stackTrace);
        }
      }));
      results.addAll(batchResults);
      completed += batch.length;
      final next = nextBatchSize?.call(batchSize, completed) ?? batchSize;
      if (next < 1) throw ArgumentError.value(next, 'nextBatchSize result');
      batchSize = next;
    }
    return List.unmodifiable(results);
  }
}
