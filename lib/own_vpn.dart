import 'package:flutter/services.dart';

// KINGVPN: اتصال VPN با سرویس خود برنامه (کانال king/vpn)
// پیش‌فرض خاموش است. وقتی kOwnVpnService = true باشد، حالت VPN از سرویس خودمان استفاده می‌کند
// و سرویس پلاگین کنار گذاشته می‌شود. تا زمانی که روی گوشی تست نشده، false بماند.
const bool kOwnVpnService = false;

const MethodChannel _kingVpnChannel = MethodChannel('king/vpn');

Future<bool> ownVpnStart({
  required String config,
  required String remark,
  String addr = '',
  String port = '',
}) async {
  try {
    final ok = await _kingVpnChannel.invokeMethod<bool>('start', {
      'config': config,
      'remark': remark,
      'addr': addr,
      'port': port,
    });
    return ok ?? false;
  } catch (e) {
    return false;
  }
}

Future<void> ownVpnStop() async {
  try {
    await _kingVpnChannel.invokeMethod<bool>('stop');
  } catch (_) {}
}
