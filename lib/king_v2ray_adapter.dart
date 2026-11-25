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
        );

  final KingV2RayStartCallback _startNative;
  final KingV2RayStopCallback _stopNative;
  final KingEngineDescriptor _descriptor;

  Object? _activeHandle;
  Object? _lastStoppedHandle;
  bool _starting = false;
  bool _cancelRequested = false;
  int _generation = 0;
  Future<void>? _stopInFlight;

  Future<void> _stopNativeSerialized() {
    final current = _stopInFlight;
    if (current != null) return current;
    final operation = _stopNative();
    _stopInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_stopInFlight, operation)) _stopInFlight = null;
    });
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
    if (configuration.trim().isEmpty) {
      return const KingEngineStartResult.failed('E-V2RAY-CONFIG-EMPTY');
    }

    _starting = true;
    _cancelRequested = false;
    final generation = ++_generation;
    try {
      await _startNative(configuration);
      if (generation != _generation || _cancelRequested) {
        // A stop can race a platform start method. Stop again after that
        // method settles so a late native start cannot become an orphan.
        await _stopNativeSerialized();
        return const KingEngineStartResult.failed('E-V2RAY-START-CANCELLED');
      }
      final handle = Object();
      _activeHandle = handle;
      _lastStoppedHandle = null;
      return KingEngineStartResult.connected(handle);
    } catch (_) {
      // A platform exception may arrive after native startup partially began.
      // Best-effort cleanup is intentionally followed by the normal app
      // recovery path; the exception text/configuration never leaves adapter.
      try {
        await _stopNativeSerialized();
      } catch (_) {
        // The Fusion coordinator retains cleanup only for acquired handles.
        // The host's existing stop/recovery path remains the final fallback.
      }
      return const KingEngineStartResult.failed('E-V2RAY-START');
    } finally {
      _starting = false;
    }
  }

  @override
  Future<void> cancelPendingStart() async {
    if (!_starting) return;
    _cancelRequested = true;
    _generation++;
    await _stopNativeSerialized();
  }

  @override
  Future<void> stop(Object? handle) async {
    if (identical(handle, _lastStoppedHandle)) return;
    if (!identical(handle, _activeHandle)) {
      throw StateError('E-V2RAY-HANDLE-MISMATCH');
    }
    await _stopNativeSerialized();
    _lastStoppedHandle = handle;
    _activeHandle = null;
  }
}
