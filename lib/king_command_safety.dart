/// Small, deterministic safety checks for the unified text/voice command parser.
/// This class never executes commands; it only detects explicit negation.
class KingCommandSafety {
  KingCommandSafety._();

  static const String _negation =
      r'(?:نکن|نده|نکنه|نشو|نشود|نشه|نمی\s*خواهم|نمیخوام|نمی‌خوام|نباید|نداشته\s*باش|don.t|do\s+not|never)';

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('‌', '');

  static bool negatesConnection(String command) {
    final value = _normalize(command);
    return RegExp(
      '(?:اتصال|وصل|شروع|قطع|connect|disconnect).{0,16}$_negation',
    ).hasMatch(value) || RegExp(
      '$_negation.{0,16}(?:اتصال|وصل|شروع|connect)',
    ).hasMatch(value);
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
