import 'dart:async';

import 'king_network_engines.dart';

class KingEngineConnectResult {
  const KingEngineConnectResult({
    required this.started,
    required this.trafficVerified,
    this.detail = '',
  });
  final bool started;
  final bool trafficVerified;
  final String detail;
}

abstract class KingConnectionAdapter {
  String get id;
  bool get available;
  Future<KingEngineConnectResult> connect();
  Future<bool> verifyTraffic();
  Future<void> disconnect();
}

class KingAutoSwitchResult {
  const KingAutoSwitchResult({
    required this.connected,
    required this.engine,
    this.detail = '',
  });
  final bool connected;
  final String? engine;
  final String detail;
}

class KingAutoSwitchCoordinator {
  KingAutoSwitchCoordinator({required List<KingConnectionAdapter> adapters})
      : adapters = List<KingConnectionAdapter>.unmodifiable(adapters) {
    final ids = <String>{};
    for (final adapter in adapters) {
      if (!ids.add(adapter.id)) {
        throw ArgumentError('Duplicate adapter identifier: ${adapter.id}');
      }
    }
  }

  final List<KingConnectionAdapter> adapters;
  int _generation = 0;
  KingConnectionAdapter? _active;
  KingConnectionAdapter? _connecting;
  Future<void> _teardownBarrier = Future<void>.value();
  Future<KingAutoSwitchResult>? _connectFlight;
  int _flightGeneration = -1;
  bool _teardownFailed = false;

  List<KingConnectionAdapter> get _orderedAdapters {
    final rank = <String, int>{
      KingEngineId.xray: 0,
      KingEngineId.amneziaWg: 10,
      KingEngineId.wireGuard: 20,
      KingEngineId.singBox: 30,
      KingEngineId.hysteria2: 40,
      KingEngineId.shadowsocks: 50,
      KingEngineId.openConnect: 60,
      KingEngineId.openVpn: 70,
      KingEngineId.nthLink: 80,
    };
    return adapters.where((a) => !KingEngineId.localTransportIds.contains(a.id))
      .toList()..sort((a, b) =>
        (rank[a.id] ?? 1000).compareTo(rank[b.id] ?? 1000));
  }

  Future<KingAutoSwitchResult> connect() async {
    final active = _active;
    if (active != null) {
      return KingAutoSwitchResult(connected: true, engine: active.id, detail: 'already active');
    }
    final existing = _connectFlight;
    if (existing != null && _flightGeneration == _generation) return existing;
    if (existing != null) {
      try { await existing; } catch (_) {}
    }
    final token = ++_generation;
    final future = _connectInternal(token);
    _connectFlight = future;
    _flightGeneration = token;
    try {
      return await future;
    } finally {
      if (identical(_connectFlight, future)) {
        _connectFlight = null;
        _flightGeneration = -1;
      }
    }
  }

  Future<KingAutoSwitchResult> _connectInternal(int token) async {
    try {
      await _teardownBarrier;
    } catch (error) {
      _teardownFailed = true;
      return KingAutoSwitchResult(connected: false, engine: null,
          detail: 'teardown failed; failover halted: $error');
    }
    if (_teardownFailed) {
      return const KingAutoSwitchResult(connected: false, engine: null,
          detail: 'teardown failed; failover halted');
    }
    if (token != _generation) {
      return const KingAutoSwitchResult(connected: false, engine: null, detail: 'cancelled');
    }
    for (final adapter in _orderedAdapters) {
      if (token != _generation) break;
      if (!adapter.available) continue;
      _connecting = adapter;
      KingEngineConnectResult start;
      try {
        start = await adapter.connect();
      } catch (error) {
        _connecting = null;
        try { await adapter.disconnect(); } catch (_) {
          return KingAutoSwitchResult(connected: false, engine: null,
              detail: 'teardown failed after connect error: $error');
        }
        continue;
      }
      if (token != _generation) {
        _connecting = null;
        if (start.started) {
          try { await adapter.disconnect(); } catch (_) {}
        }
        return const KingAutoSwitchResult(connected: false, engine: null, detail: 'cancelled');
      }
      if (!start.started) {
        _connecting = null;
        try { await adapter.disconnect(); } catch (error) {
          return KingAutoSwitchResult(connected: false, engine: null,
              detail: 'teardown failed: $error');
        }
        continue;
      }
      bool traffic = start.trafficVerified;
      if (!traffic) {
        try { traffic = await adapter.verifyTraffic(); } catch (_) { traffic = false; }
      }
      if (token != _generation) {
        _connecting = null;
        try { await adapter.disconnect(); } catch (_) {}
        return const KingAutoSwitchResult(connected: false, engine: null, detail: 'cancelled');
      }
      if (traffic) {
        _connecting = null;
        _active = adapter;
        return KingAutoSwitchResult(connected: true, engine: adapter.id,
            detail: start.detail);
      }
      _connecting = null;
      try { await adapter.disconnect(); } catch (error) {
        return KingAutoSwitchResult(connected: false, engine: null,
            detail: 'teardown failed: $error');
      }
    }
    return const KingAutoSwitchResult(connected: false, engine: null,
        detail: 'no engine produced verified tunnel traffic');
  }

  Future<void> disconnect() async {
    ++_generation;
    final target = _active ?? _connecting;
    _active = null;
    if (target == null) return;
    final teardown = target.disconnect();
    _teardownBarrier = teardown;
    try {
      await teardown;
      _teardownFailed = false;
    } catch (_) {
      _teardownFailed = true;
      rethrow;
    }
  }

  Future<KingAutoSwitchResult> recoverFromTrafficFailure() async {
    final target = _active;
    if (target != null) {
      _active = null;
      ++_generation;
      try {
        final teardown = target.disconnect();
        _teardownBarrier = teardown;
        await teardown;
        _teardownFailed = false;
      } catch (error) {
        return KingAutoSwitchResult(connected: false, engine: null,
            detail: 'recovery halted: teardown failed: $error');
      }
    }
    return connect();
  }
}

class KingBatchResult<T> {
  const KingBatchResult({required this.value, required this.succeeded, this.error});
  final T? value;
  final bool succeeded;
  final Object? error;
}

class KingAdaptiveBatchRunner {
  static Future<List<KingBatchResult<R>>> run<T, R>({
    required Iterable<T> items,
    required int initialBatchSize,
    required Future<R> Function(T item) probe,
    int Function(int previousBatchSize, int completedInBatch)? nextBatchSize,
  }) async {
    if (initialBatchSize <= 0) throw ArgumentError.value(initialBatchSize, 'initialBatchSize');
    final source = items.iterator;
    final results = <KingBatchResult<R>>[];
    var batchSize = initialBatchSize;
    var exhausted = false;
    while (!exhausted) {
      var completed = 0;
      for (var i = 0; i < batchSize; i++) {
        if (!source.moveNext()) { exhausted = true; break; }
        try {
          results.add(KingBatchResult<R>(value: await probe(source.current), succeeded: true));
        } catch (error) {
          results.add(KingBatchResult<R>(value: null, succeeded: false, error: error));
        }
        completed++;
      }
      if (nextBatchSize != null && completed > 0) {
        final next = nextBatchSize(batchSize, completed);
        if (next <= 0) throw ArgumentError.value(next, 'nextBatchSize');
        batchSize = next;
      }
    }
    return List<KingBatchResult<R>>.unmodifiable(results);
  }
}
