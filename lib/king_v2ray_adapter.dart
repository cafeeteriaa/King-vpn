import 'dart:async';

import 'king_fusion_engine.dart';

typedef KingV2RayStartCallback = Future<void> Function(String configuration);
typedef KingV2RayStopCallback = Future<void> Function();

/// Bridges the application's existing V2Ray plugin lifecycle into KING Fusion.
///
/// A successful adapter result means only that the plugin's start request
/// returned. The host must still observe CONNECTED, confirm the Android TUN,
/// and verify real outbound traffic before presenting the VPN as connected.
class KingV2RayAdapter implements KingFusionCancellableEngineAdapter {
  KingV2RayAdapter({
    required KingV2RayStartCallback start,
    required KingV2RayStopCallback stop,
    String id = 'king-v2ray-xray',
    this.nativeStartTimeout = const Duration(seconds: 30),
  })  : _startNative = start,
        _stopNative = stop,
        _descriptor = KingEngineDescriptor(
          id: id,
          title: 'KING VPN V2Ray / Xray',
          family: KingEngineFamily.xray,
          availability: KingEngineAvailability.integrated,
          // Transport is intentionally unspecified: opaque configs are not
          // parsed or narrowed by this lifecycle bridge.
          supportedTransports: const <String>{},
          supportsMultiHop: false,
        ) {
    if (nativeStartTimeout <= Duration.zero) {
      throw ArgumentError.value(
        nativeStartTimeout,
        'nativeStartTimeout',
        'Must be positive',
      );
    }
  }

  final KingV2RayStartCallback _startNative;
  final KingV2RayStopCallback _stopNative;
  final KingEngineDescriptor _descriptor;
  final Duration nativeStartTimeout;

  Object? _activeHandle;
  Object? _lastStoppedHandle;
  bool _starting = false;
  bool _cancelRequested = false;
  bool _cleanupRequired = false;
  bool _failedStartCleanupDone = false;
  int _generation = 0;
  Future<void>? _pendingStart;
  Future<void>? _startCancellationSignal;
  Completer<void>? _startCancellationCompleter;
  Future<void>? _stopInFlight;

  Future<void> _stopNativeSerialized() {
    final current = _stopInFlight;
    if (current != null) return current;

    final operation = Future<void>.sync(_stopNative);
    _stopInFlight = operation;
    operation.then<void>(
      (_) {
        if (identical(_stopInFlight, operation)) _stopInFlight = null;
      },
      onError: (Object _, StackTrace __) {
        if (identical(_stopInFlight, operation)) _stopInFlight = null;
      },
    );
    return operation;
  }

  @override
  KingEngineDescriptor get descriptor => _descriptor;

  @override
  bool canChainTo(KingEngineAdapter next) => false;

  @override
  Future<KingEngineStartResult> start({
    required String configuration,
    Object? upstreamHandle,
  }) async {
    if (_starting || _activeHandle != null) {
      return const KingEngineStartResult.failed('E-V2RAY-ALREADY-ACTIVE');
    }
    if (_cleanupRequired || _pendingStart != null) {
      return const KingEngineStartResult.failed(
        'E-V2RAY-CLEANUP-PENDING',
        cleanupRequired: true,
      );
    }
    if (configuration.trim().isEmpty) {
      return const KingEngineStartResult.failed('E-V2RAY-CONFIG-EMPTY');
    }

    _starting = true;
    _cancelRequested = false;
    _failedStartCleanupDone = false;
    final generation = ++_generation;
    final cancellation = Completer<void>();
    _startCancellationCompleter = cancellation;
    _startCancellationSignal = cancellation.future;
    final nativeStart = Future<void>.sync(() => _startNative(configuration));
    _pendingStart = nativeStart;
    var nativeSettled = false;
    nativeStart.then<void>(
      (_) {
        nativeSettled = true;
        if (identical(_pendingStart, nativeStart)) _pendingStart = null;
      },
      onError: (Object _, StackTrace __) {
        nativeSettled = true;
        if (identical(_pendingStart, nativeStart)) _pendingStart = null;
      },
    );

    try {
      await Future.any<void>([
        nativeStart.timeout(
          nativeStartTimeout,
          onTimeout: () => throw TimeoutException('E-V2RAY-START-TIMEOUT'),
        ),
        cancellation.future.then<void>(
          (_) => throw StateError('E-V2RAY-START-CANCELLED'),
        ),
      ]);

      if (generation != _generation || _cancelRequested) {
        _cleanupRequired = true;
        try {
          await _stopNativeSerialized();
          _cleanupRequired = false;
          _failedStartCleanupDone = true;
          return const KingEngineStartResult.failed(
            'E-V2RAY-START-CANCELLED',
          );
        } catch (_) {
          return const KingEngineStartResult.failed(
            'E-V2RAY-START-CANCELLED',
            cleanupRequired: true,
          );
        }
      }

      final handle = Object();
      _activeHandle = handle;
      _lastStoppedHandle = null;
      return KingEngineStartResult.connected(handle);
    } catch (_) {
      final cancelled = generation != _generation || _cancelRequested;
      final failureCode = cancelled
          ? 'E-V2RAY-START-CANCELLED'
          : nativeSettled
              ? 'E-V2RAY-START'
              : 'E-V2RAY-START-TIMEOUT';

      if (!nativeSettled) {
        // Keep the original platform Future, not its timeout wrapper. Fusion
        // retains this failed start as a cleanup handle and waits/retries stop.
        _cleanupRequired = true;
        return KingEngineStartResult.failed(
          failureCode,
          cleanupRequired: true,
        );
      }

      try {
        await _stopNativeSerialized();
        _cleanupRequired = false;
        _failedStartCleanupDone = true;
        return KingEngineStartResult.failed(failureCode);
      } catch (_) {
        _cleanupRequired = true;
        return KingEngineStartResult.failed(
          failureCode,
          cleanupRequired: true,
        );
      }
    } finally {
      _starting = false;
      _startCancellationCompleter = null;
      _startCancellationSignal = null;
    }
  }

  @override
  Future<void> cancelPendingStart() async {
    if (!_starting) return;
    _cancelRequested = true;
    _generation++;
    _cleanupRequired = true;
    final signal = _startCancellationCompleter;
    if (signal != null && !signal.isCompleted) signal.complete();
    // Stop immediately, then keep the unresolved start Future as a cleanup
    // dependency. stop(null) waits for it and performs a final late-start stop.
    await _stopNativeSerialized();
  }

  @override
  Future<void> stop(Object? handle) async {
    if (handle == null &&
        (_cleanupRequired || _pendingStart != null || _failedStartCleanupDone)) {
      final pending = _pendingStart;
      if (pending != null) {
        try {
          await pending;
        } catch (_) {
          // A failed start has settled; cleanup is still required below.
        }
      }
      await _stopNativeSerialized();
      _cleanupRequired = false;
      _failedStartCleanupDone = true;
      _activeHandle = null;
      return;
    }

    if (identical(handle, _lastStoppedHandle)) return;
    if (!identical(handle, _activeHandle)) {
      throw StateError('E-V2RAY-HANDLE-MISMATCH');
    }
    await _stopNativeSerialized();
    _lastStoppedHandle = handle;
    _activeHandle = null;
  }
}
