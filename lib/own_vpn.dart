import 'dart:async';

import 'errjournal.dart';
import 'package:flutter/services.dart';

// KINGVPN: اتصال VPN با سرویس خود برنامه (کانال king/vpn)
// پیش‌فرض خاموش است. وقتی kOwnVpnService = true باشد، حالت VPN از سرویس خودمان استفاده می‌کند
// و سرویس پلاگین کنار گذاشته می‌شود. تا زمانی که روی گوشی تست نشده، false بماند.
const bool kOwnVpnService = false;

const MethodChannel _kingVpnChannel = MethodChannel('king/vpn');

// جدید: the native service reports the real outcome of a start through the 'status' call:
// 'CONNECTED', 'FAILED' or 'STOPPED'. The plugin's status events are not used for this path.
Completer<String>? _startWaiter;
bool _handlerSet = false;
// FIX #83: each start gets an id. The native service echoes it in every status message,
// so a late CONNECTED/FAILED from an earlier attempt cannot complete the current waiter.
// Id 0 (service restart/resume) and -1 (stop) never complete a waiter (مشکل ۹).
int _ownAttemptSeq = 0;
int _ownAttemptCurrent = 0;

void _ensureStatusHandler() {
  if (_handlerSet) return;
  _handlerSet = true;
  _kingVpnChannel.setMethodCallHandler((call) async {
    if (call.method != 'status') return null;
    final args = call.arguments;
    final state = args is Map ? '${args['state'] ?? ''}' : '';
    final err = args is Map ? '${args['error'] ?? ''}' : '';
    final attemptRaw = args is Map ? args['attempt'] : null;
    final attempt = attemptRaw is int ? attemptRaw : 0;
    // مشکل ۹: فقط شناسه‌ی همین تلاش؛ شناسه‌ی ۰ یا STOP (-1) هیچ waiterی را کامل نمی‌کند.
    if (attempt != _ownAttemptCurrent) {
      return null;
    }
    if (state != 'CONNECTED') {
      errJournalAdd(StateError('king/vpn status $state: $err'), kind: 'OWNVPN');
    }
    final w = _startWaiter;
    if (w != null && !w.isCompleted) w.complete(state);
    return null;
  });
}

/// Returns true only when the native service reports CONNECTED.
/// Returns false on FAILED, STOPPED, a platform error, or after 190 s without an answer.
Future<bool> ownVpnStart({
  required String config,
  required String remark,
  String addr = '',
  String port = '',
  String backups = '', // KINGFAILOVER: JSON list of backup servers
  bool national = false, // NATPROBE: national mode skips the international health probe
}) async {
  _ensureStatusHandler();

  // There is one native VPN service and one status stream. A second start must
  // explicitly supersede the first waiter instead of orphaning it for 190 seconds.
  final previousWaiter = _startWaiter;
  if (previousWaiter != null && !previousWaiter.isCompleted) {
    previousWaiter.complete('SUPERSEDED');
  }

  final waiter = Completer<String>();
  final attemptId = ++_ownAttemptSeq;
  _ownAttemptCurrent = attemptId;
  _startWaiter = waiter;
  try {
    final ok = await _kingVpnChannel.invokeMethod<bool>('start', {
      'config': config,
      'remark': remark,
      'addr': addr,
      'port': port,
      'backups': backups,
      'national': national,
      'attempt': attemptId,
    });
    if (ok != true) {
      errJournalAdd(StateError('king/vpn start returned ${ok ?? 'null'}'), kind: 'OWNVPN');
      return false;
    }
    // جدید: wait for the real result. 190 s covers up to 9 servers at the native 20 s cap.
    final state = await waiter.future
        .timeout(const Duration(seconds: 190), onTimeout: () => 'TIMEOUT');
    if (state == 'CONNECTED') return true;
    errJournalAdd(StateError('king/vpn start ended with $state'), kind: 'OWNVPN');
    // A stale start must never stop a newer attempt after its own timeout fires.
    if (state == 'TIMEOUT' && _ownAttemptCurrent == attemptId) {
      await ownVpnStop();
    }
    return false;
  } catch (e, st) {
    errJournalAdd(e, kind: 'OWNVPN', st: st);
    return false;
  } finally {
    if (identical(_startWaiter, waiter)) _startWaiter = null;
  }
}

Future<void> ownVpnStop() async {
  // Invalidate the active attempt before completing its waiter. Late CONNECTED
  // callbacks from that attempt must not be accepted after a user stop.
  _ownAttemptCurrent = ++_ownAttemptSeq;
  final w = _startWaiter;
  if (w != null && !w.isCompleted) w.complete('STOPPED');
  try {
    await _kingVpnChannel.invokeMethod<bool>('stop');
  } catch (e, st) {
    errJournalAdd(e, kind: 'OWNVPN', st: st); // جدید: was SILENT-LIB, now carries the stack
  }
}
