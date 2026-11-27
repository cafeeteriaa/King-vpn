import 'king_network_engines.dart';

abstract class KingConnectionAdapter {
  String get id;
  bool get available;
  Future<KingEngineConnectResult> connect();
  Future<bool> verifyTraffic();
  Future<void> disconnect();
}

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

/// Serializes VPN ownership transitions and never fails over until the prior
/// adapter has confirmed teardown. Local DPI helpers are not VPN owners.
class KingAutoSwitchCoordinator {
  KingAutoSwitchCoordinator({required List<KingConnectionAdapter> adapters})
      : _adapters = _orderedAdapters(adapters) {
    final ids = <String>{};
    for (final adapter in adapters) {
      if (!ids.add(adapter.id)) {
        throw ArgumentError('Duplicate engine adapter identifier: ${adapter.id}');
      }
    }
  }

  final List<KingConnectionAdapter> _adapters;
  KingConnectionAdapter? _active;
  KingConnectionAdapter? _connecting;
  Future<KingAutoSwitchResult>? _connectFuture;
  int _generation = 0;
  bool _cancelled = false;

  static const Set<String> _localOnly = <String>{
    KingEngineId.shroudly,
    KingEngineId.byeDpi,
    KingEngineId.powerTunnel,
  };

  static int _priority(String id) {
    switch (id) {
      case KingEngineId.xray: return 1000;
      case KingEngineId.hysteria2: return 900;
      case KingEngineId.singBox: return 890;
      case KingEngineId.amneziaWg: return 880;
      case KingEngineId.wireGuard: return 870;
      case KingEngineId.shadowsocks: return 760;
      case KingEngineId.openVpn: return 700;
      case KingEngineId.openConnect: return 690;
      case KingEngineId.nthLink: return 680;
      default: return 0;
    }
  }

  static List<KingConnectionAdapter> _orderedAdapters(
      List<KingConnectionAdapter> adapters) {
    final result = adapters.where((a) => !_localOnly.contains(a.id)).toList();
    result.sort((a, b) => _priority(b.id).compareTo(_priority(a.id)));
    return result;
  }

  Future<KingAutoSwitchResult> connect() {
    if (_connectFuture != null && !_cancelled) return _connectFuture!;
    final previous = _connectFuture;
    final generation = ++_generation;
    _cancelled = false;
    final future = _connectAfter(previous, generation);
    _connectFuture = future;
    future.then((_) {
      if (identical(_connectFuture, future)) _connectFuture = null;
    }, onError: (_) {
      if (identical(_connectFuture, future)) _connectFuture = null;
    });
    return future;
  }

  Future<KingAutoSwitchResult> _connectAfter(
    Future<KingAutoSwitchResult>? previous,
    int generation,
  ) async {
    if (previous != null) {
      try { await previous; } catch (_) {}
    }
    if (!_isCurrent(generation)) {
      return const KingAutoSwitchResult(
        connected: false, engine: null, detail: 'connection cancelled',
      );
    }
    return _tryEngines(generation);
  }

  bool _isCurrent(int generation) =>
      generation == _generation && !_cancelled;

  Future<KingAutoSwitchResult> _tryEngines(int generation) async {
    for (final adapter in _adapters) {
      if (!_isCurrent(generation)) {
        return const KingAutoSwitchResult(
          connected: false, engine: null, detail: 'connection cancelled',
        );
      }
      if (!adapter.available) continue;
      _connecting = adapter;
      KingEngineConnectResult start;
      try {
        start = await adapter.connect();
      } catch (error) {
        try {
          await adapter.disconnect();
        } catch (teardown) {
          _connecting = null;
          return KingAutoSwitchResult(
            connected: false, engine: null,
            detail: 'teardown failed after startup error: $teardown',
          );
        }
        if (!_isCurrent(generation)) {
          _connecting = null;
          return const KingAutoSwitchResult(
            connected: false, engine: null, detail: 'connection cancelled',
          );
        }
        _connecting = null;
        continue;
      }

      if (!_isCurrent(generation)) {
        try {
          await adapter.disconnect();
        } catch (_) {}
        if (identical(_connecting, adapter)) _connecting = null;
        return const KingAutoSwitchResult(
          connected: false, engine: null, detail: 'connection cancelled',
        );
      }

      var traffic = start.started && start.trafficVerified;
      if (traffic) {
        try {
          traffic = await adapter.verifyTraffic();
        } catch (_) {
          traffic = false;
        }
      }
      if (traffic && _isCurrent(generation)) {
        _active = adapter;
        if (identical(_connecting, adapter)) _connecting = null;
        return KingAutoSwitchResult(
          connected: true, engine: adapter.id,
          detail: start.detail.isEmpty ? 'data-plane verified' : start.detail,
        );
      }

      try {
        await adapter.disconnect();
      } catch (error) {
        if (identical(_connecting, adapter)) _connecting = null;
        return KingAutoSwitchResult(
          connected: false, engine: null,
          detail: 'teardown failed; failover halted: $error',
        );
      }
      if (identical(_connecting, adapter)) _connecting = null;
      if (!_isCurrent(generation)) {
        return const KingAutoSwitchResult(
          connected: false, engine: null, detail: 'connection cancelled',
        );
      }
    }
    return const KingAutoSwitchResult(
      connected: false, engine: null,
      detail: 'no available engine produced verified tunnel traffic',
    );
  }

  Future<void> disconnect() async {
    _cancelled = true;
    _generation++;
    final active = _active;
    final connecting = _connecting;
    _active = null;
    // Keep _connecting until its pending start returns, so a late startup is
    // explicitly torn down a second time before a queued reconnect can begin.
    final toStop = <KingConnectionAdapter>{};
    if (active != null) toStop.add(active);
    if (connecting != null) toStop.add(connecting);
    for (final adapter in toStop) {
      try { await adapter.disconnect(); } catch (_) {}
    }
  }

  Future<KingAutoSwitchResult> recoverFromTrafficFailure() async {
    final active = _active;
    if (active == null) return connect();
    var healthy = false;
    try { healthy = await active.verifyTraffic(); } catch (_) {}
    if (healthy) {
      return KingAutoSwitchResult(
        connected: true, engine: active.id, detail: 'active traffic verified',
      );
    }
    _active = null;
    try {
      await active.disconnect();
    } catch (error) {
      return KingAutoSwitchResult(
        connected: false, engine: null,
        detail: 'recovery halted: active VPN owner teardown failed: $error',
      );
    }
    final generation = ++_generation;
    _cancelled = false;
    return _tryEngines(generation);
  }
}
