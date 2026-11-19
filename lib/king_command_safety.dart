/// Small, deterministic safety checks for the unified text/voice command parser.
/// This class never executes commands; it only detects explicit negation.
enum KingRequestedNetworkMode { domestic, global }

class KingCommandSafety {
  KingCommandSafety._();

  static const String _negation =
      r'(?:نکن|نکنید|نکنین|نده|نکنه|نزن|نزنید|نگیر|نگیرید|نشو|نشید|نشوید|نشود|نشه|نمی\s*خواهم|نمیخوام|نمی‌خوام|نباید|نداشته\s*باش|don.t|do\s+not|never)';

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('‌', '');

  /// Removes the assistant's optional wake/address prefix without granting
  /// permissions. Authorization remains enforced by the owner-only console.
  static String stripKingAddress(String raw) {
    final normalized = raw.trim().toLowerCase()
        .replaceAll('ي', 'ی')
        .replaceAll('ك', 'ک')
        .replaceAll('ۀ', 'ه')
        .replaceAll('ة', 'ه')
        .replaceAll('‌', ' ')
        .replaceAll(RegExp(r'[،,؛;.!?؟:]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized.replaceFirst(
      RegExp(r'^(?:(?:سلام|هی)\s+)?(?:کینگ|king)(?:\s+(?:جان|عزیز))?\s*'),
      '',
    ).trim();
  }

  static bool negatesConnection(String command) {
    final value = _normalize(command);
    return RegExp(
      '(?:اتصال|وصل|شروع|قطع|کانکت|متصل|connect|disconnect).{0,16}$_negation',
    ).hasMatch(value) || RegExp(
      '$_negation.{0,16}(?:اتصال|وصل|شروع|قطع|کانکت|متصل|connect|disconnect)',
    ).hasMatch(value);
  }

  /// Explicit network-mode requests are separated from automatic pilot mode.
  /// Status questions must never be interpreted as a request to connect.
  static KingRequestedNetworkMode? requestedNetworkMode(String command) {
    final value = _normalize(command).replaceAll(RegExp(r'\\s+'), ' ').trim();
    if (isStatusRequest(value) || negatesConnection(value)) return null;
    final asksToConnect = RegExp(r'(اتصال|وصل|متصل|connect)').hasMatch(value);
    if (!asksToConnect) return null;
    if (RegExp(r'(نت\\s*ملی|شبکه\\s*ملی|اینترنت\\s*داخلی|مسیر\\s*داخلی)')
        .hasMatch(value)) {
      return KingRequestedNetworkMode.domestic;
    }
    if (RegExp(r'(نت\\s*جهانی|شبکه\\s*جهانی|اینترنت\\s*جهانی|مسیر\\s*جهانی|بین\\s*الملل)')
        .hasMatch(value)) {
      return KingRequestedNetworkMode.global;
    }
    return null;
  }

  static bool isStatusRequest(String command) {
    final value = _normalize(command);
    return RegExp(r'(وضعیت|status|چه\\s*خبر|چطوره|متصل\\s*هستم|وصل\\s*هستم)')
        .hasMatch(value);
  }

  static bool negatesScan(String command) {
    final value = _normalize(command);
    return RegExp(
      '(?:اسکن|پویش|scan).{0,16}$_negation',
    ).hasMatch(value) || RegExp(
      '$_negation.{0,16}(?:اسکن|پویش|scan)',
    ).hasMatch(value);
  }
}
