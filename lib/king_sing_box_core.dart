import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sing_box/sing_box.dart';

class KingSingBoxCore {
  KingSingBoxCore._();
  static final KingSingBoxCore instance = KingSingBoxCore._();
  static const MethodChannel _owner = MethodChannel('king/vpn_engine_owner');
  final SingBox _engine = SingBox.instance;
  StreamSubscription<SingBoxConnectionState>? _stateSub;
  Future<void>? _initializing;
  bool _owns = false;
  bool _connectedOnce = false;

  SingBoxConnectionStatus get status => _engine.status;
  SingBoxConnectionState get state => _engine.state;

  Future<void> initialize() {
    if (_engine.isInitialized) return Future<void>.value();
    return _initializing ??= _initialize().whenComplete(() => _initializing = null);
  }

  Future<void> _initialize() async {
    await _engine.initialize(const SingBoxOptions(
      android: SingBoxAndroidOptions(
        notificationChannelId: 'king_libbox_vpn',
        notificationChannelName: 'KING VPN',
        notificationTitle: 'KING VPN',
        notificationContent: 'هستهٔ مستقل شبکه فعال است',
        showTrafficInNotification: true,
        showStopAction: true,
        stopActionTitle: 'قطع اتصال',
        sessionName: 'KING VPN',
      ),
      logMaxLines: 5000,
    ));
    _stateSub ??= _engine.watchConnectionState().listen(_onState);
    if (_engine.status.isActive) {
      await _acquire();
      _connectedOnce = _engine.status == SingBoxConnectionStatus.connected;
    }
  }

  Future<void> _acquire() async {
    if (_owns) return;
    final ok = await _owner.invokeMethod<bool>('acquire', {
      'engine': 'libbox',
      'timeoutMs': 30000,
    });
    if (ok != true) throw StateError('موتور فعال قبلی هنوز تونل را آزاد نکرده است');
    _owns = true;
  }

  Future<void> connect(String input) async {
    final config = input.trim();
    if (config.isEmpty) throw const FormatException('لینک یا پیکربندی خالی است');
    await initialize();
    if (!await _engine.hasVpnPermission() && !await _engine.requestVpnPermission()) {
      throw StateError('اجازهٔ VPN از طرف Android داده نشد');
    }
    try {
      if (!await _engine.hasNotificationPermission()) {
        await _engine.requestNotificationPermission();
      }
    } catch (_) {}
    await _acquire();
    _connectedOnce = false;
    try {
      await _engine.connect(
        config,
        requestPermission: false,
        waitUntilConnected: true,
        timeout: const Duration(seconds: 60),
      );
      if (_engine.status != SingBoxConnectionStatus.connected) {
        throw StateError('libbox اتصال را تأیید نکرد');
      }
      _connectedOnce = true;
    } catch (_) {
      if (_engine.status == SingBoxConnectionStatus.disconnected) {
        await _release();
      } else {
        _connectedOnce = true;
      }
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await initialize();
    if (!_owns) {
      if (await _owner.invokeMethod<String>('owner') != 'libbox') return;
      _owns = true;
    }
    await _engine.disconnect();
    await _engine.waitForStatus(
      SingBoxConnectionStatus.disconnected,
      timeout: const Duration(seconds: 30),
    );
    await _release();
  }

  void _onState(SingBoxConnectionState state) {
    if (_owns && _connectedOnce && state.status == SingBoxConnectionStatus.disconnected) {
      unawaited(_release().catchError((Object e, StackTrace st) {
        debugPrint('libbox owner release: $e');
      }));
    }
  }

  Future<void> _release() async {
    if (!_owns) return;
    await _owner.invokeMethod<void>('release', {'engine': 'libbox'});
    _owns = false;
    _connectedOnce = false;
  }

  Stream<SingBoxConnectionState> watchState() => _engine.watchConnectionState();
  Stream<SingBoxConnectionStats> watchStats() => _engine.watchConnectionStats();
  Future<String> version() async { await initialize(); return _engine.getSingBoxVersion(); }
}
