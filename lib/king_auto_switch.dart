import 'king_network_engines.dart';

/// Stable identifiers for the built-in engines. Additional adapters may use
/// their own IDs and register descriptors without changing this type.
abstract final class KingEngineId {
  static const xray = 'xray';
  static const vpnGate = 'vpn_gate';
  static const calyxVpn = 'calyx_vpn';
  static const nthLink = 'nthlink';
  static const tor = 'tor';
  static const i2p = 'i2p';
  static const lantern = 'lantern';
  static const cloudflareWarp = 'cloudflare_warp';
  static const aviraPhantom = 'avira_phantom';
  static const shroudly = 'shroudly';
  static const ceno = 'ceno';
  static const byeDpi = 'byedpi';
  static const powerTunnel = 'powertunnel';
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

/// Runs real adapters serially. Android allows only one active VpnService
/// owner, so the previous adapter is always torn down before another starts.
class KingAutoSwitchCoordinator {
  factory KingAutoSwitchCoordinator({
    required List<KingConnectionAdapter> adapters,
    KingNetworkEngineCatalog? catalog,
  }) {
    final registry = catalog ?? KingNetworkEngineCatalog();
    final indexed = adapters.asMap().entries.toList()
      ..sort((a, b) {
        final byPriority =
            registry.priorityOf(a.value.id).compareTo(registry.priorityOf(b.value.id));
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
      // A new start after Stop waits for the cancelled native startup to finish
      // tearing down; this prevents two VPN owners from racing for Android's TUN.
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

      _starting = adapter;
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
          _starting = null;
          _active = adapter;
          return KingAutoSwitchResult(
            engine: adapter.id,
            connected: true,
            attempts: List.unmodifiable(attempts),
          );
        }
      } catch (error) {
        if (identical(_starting, adapter)) _starting = null;
        attempts.add(KingEngineConnectResult(
          started: false,
          trafficVerified: false,
          detail: error.toString(),
        ));
      }
      if (identical(_starting, adapter)) _starting = null;
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
      return const KingAutoSwitchResult(
        engine: null,
        connected: false,
        attempts: [],
        detail: 'Connection attempt cancelled',
      );
    }
    final active = _active;
    if (active == null) return _connectInOrder(++_generation, _adapters);
    var healthy = false;
    try {
      healthy = await active.verifyTraffic();
    } catch (_) {}
    if (_stoppedByUser || generationAtStart != _generation) {
      return const KingAutoSwitchResult(
        engine: null,
        connected: false,
        attempts: [],
        detail: 'Connection attempt cancelled',
      );
    }
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
    if (_stoppedByUser || generationAtStart != _generation) {
      return const KingAutoSwitchResult(
        engine: null,
        connected: false,
        attempts: [],
        detail: 'Connection attempt cancelled',
      );
    }
    final generation = ++_generation;
    return _connectInOrder(
      generation,
      _adapters.where((adapter) => !identical(adapter, active)).toList(),
    );
  }

  Future<void> disconnect() async {
    _stoppedByUser = true;
    ++_generation;
    final active = _active;
    final starting = _starting;
    _active = null;
    _starting = null;
    if (active != null) await active.disconnect();
    if (starting != null && !identical(starting, active)) {
      await starting.disconnect();
    }
  }
}

class KingProbeResult<R> {
  const KingProbeResult.success(this.value)
      : error = null,
        stackTrace = null;
  const KingProbeResult.failure(this.error, this.stackTrace) : value = null;

  final R? value;
  final Object? error;
  final StackTrace? stackTrace;
  bool get succeeded => error == null;
}

/// Adaptive executor for independent probes. The entire supplied iterable is
/// consumed; the batch size is runtime-selected and is not an inventory cap.
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
