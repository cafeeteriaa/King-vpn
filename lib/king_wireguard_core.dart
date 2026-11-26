import 'package:flutter/services.dart';

/// Dart bridge to the independent native WireGuard userspace engine.
/// The supplied value must be a native WireGuard [Interface]/[Peer] profile.
class KingWireGuardCore {
  static const MethodChannel _channel = MethodChannel('king/wireguard');

  Future<Map<String, Object?>> connect(String config) async {
    if (!config.contains('[Interface]') || !config.contains('[Peer]')) {
      throw const FormatException(
          'WireGuard profile must contain [Interface] and [Peer] sections');
    }
    final result = await _channel.invokeMapMethod<String, Object?>(
      'connect',
      <String, Object?>{'config': config},
    );
    if (result == null || result['connected'] != true) {
      throw StateError('WireGuard engine did not confirm connection');
    }
    return result;
  }

  Future<void> disconnect() async {
    await _channel.invokeMethod<bool>('disconnect');
  }

  Future<String> status() async {
    final result = await _channel.invokeMapMethod<String, Object?>('status');
    return result?['state']?.toString() ?? 'UNKNOWN';
  }
}
