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

  /// Questions belong to the conversational model, not the action dispatcher.
  /// This conservative gate intentionally prefers asking/clarifying over connecting.
  static bool isQuestionRequest(String command) {
    final value = _normalize(command);
    return value.contains('?') || value.contains('؟') ||
        RegExp(
          // Persian question words must be token-bounded: matching "کی" as a
          // substring incorrectly classified the assistant name "کینگ" as a
          // question and blocked every imperative command addressed to King.
          r'(?:^|\s)(?:چرا|چطور|چگونه|چطوره|چیست|چیه|چی|چه|آیا|مگر|کدام|کجا|کی|چند|میتونی|میتوانی|میشه|می‌شود)(?:\s|$)|'
          r'\b(?:can\s+you|could\s+you|would\s+you|is|are|am|do|does|did|can|could|would|should|will|has|have|had|what|why|how|when|where|which|who)\b',
        ).hasMatch(value);
  }

  /// Canonical connection-intent parser shared by voice and text commands.
  /// Only imperative/action phrasing is executable; questions and negations
  /// always fall through to King's conversational model.
  static bool isConnectIntent(String command) {
    final value = _normalize(command).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (isStatusRequest(value) || isQuestionRequest(value) ||
        negatesConnection(value)) return false;
    return RegExp(
      r'(?:وصل|متصل|کانکت)\s*(?:شو|بشو|کن|کنید|بشید)(?:\s|$)|'
      r'اتصال\s*(?:را|رو)?\s*(?:برقرار\s*)?(?:کن|کنید|بده|بدید)(?:\s|$)|'
      r'اتصال.{0,24}(?:شروع|برقرار)\s*(?:کن|کنید)(?:\s|$)|'
      r'(?:شروع|برقرار)\s*(?:کن|کنید)(?:\s|$).{0,24}(?:اتصال|وصل|خلبان)|'
      r'\b(?:connect|start\s+(?:vpn|connection))\b',
    ).hasMatch(value);
  }

  /// Explicit network-mode requests are separated from automatic pilot mode.
  /// Status questions must never be interpreted as a request to connect.
  static KingRequestedNetworkMode? requestedNetworkMode(String command) {
    final value = _normalize(command).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (!isConnectIntent(value)) return null;
    if (RegExp(r'(نت\s*ملی|شبکه\s*ملی|اینترنت\s*ملی|اینترنت\s*داخلی|مسیر\s*داخلی)')
        .hasMatch(value)) {
      return KingRequestedNetworkMode.domestic;
    }
    if (RegExp(r'(نت\s*جهانی|شبکه\s*جهانی|اینترنت\s*جهانی|مسیر\s*جهانی|بین\s*الملل)')
        .hasMatch(value)) {
      return KingRequestedNetworkMode.global;
    }
    return null;
  }

  /// Disconnect actions are also restricted to explicit imperative wording.
  /// A question such as "چرا اتصال قطع می‌شود؟" must never disconnect the VPN.
  static bool isDisconnectIntent(String command) {
    final value = _normalize(command).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (isStatusRequest(value) || isQuestionRequest(value) ||
        negatesConnection(value)) return false;
    return RegExp(
      r'^(?:قطع\s*اتصال|اتصال\s*(?:را|رو)?\s*قطع\s*(?:کن|کنید)|'
      r'قطع\s*(?:کن|کنید)|disconnect(?:\s+now)?|خاموش\s*کردن\s*اتصال)$',
    ).hasMatch(value);
  }

  static bool isStatusRequest(String command) {
    final value = _normalize(command).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value == 'status' || value == 'وضعیت') return true;

    final explicitStatus = RegExp(
      r'(وضعیت|status|متصل\s*هستم|وصل\s*هستم)',
    ).hasMatch(value);
    final networkContext = RegExp(
      r'(اتصال|connection|vpn|وی.?پی.?ان|خلبان|نت\s*ملی|نت\s*جهانی|'
      r'شبکه\s*ملی|شبکه\s*جهانی|اینترنت\s*من|شبکه\s*من|'
      r'سرور\s*(?:vpn|وی.?پی.?ان))',
    ).hasMatch(value);
    if (explicitStatus && networkContext) return true;
    if (RegExp(r'(?:متصل|وصل)\s*هستم').hasMatch(value)) return true;

    // Informal status phrases are meaningful only when they clearly refer
    // to King's VPN/pilot, not ordinary topics such as weather or world news.
    final informalStatus = RegExp(r'(چه\s*خبر|چطوره)').hasMatch(value);
    final pilotContext = RegExp(
      r'(اتصال|connection|vpn|وی.?پی.?ان|خلبان|نت\s*ملی|نت\s*جهانی)',
    ).hasMatch(value);
    return informalStatus && pilotContext;
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
