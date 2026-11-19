import 'dart:math' as math;

/// Removes common credential forms from CI output before local-model context.
String redactKingAiCiEvidence(String input, {int maxChars = 12000}) {
  var safe = input
      .replaceAll(RegExp(r'gh[pousr]_[A-Za-z0-9]{20,}'), '[REDACTED_GITHUB_TOKEN]')
      .replaceAll(RegExp(r'github_pat_[A-Za-z0-9_]{20,}'), '[REDACTED_GITHUB_TOKEN]')
      .replaceAll(RegExp(r'Bearer\\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false), 'Bearer [REDACTED]')
      .replaceAll(
        RegExp(r'(api[_-]?key|access[_-]?token|client[_-]?secret|password)\\s*[:=]\\s*[^\\s,;]+', caseSensitive: false),
        '[REDACTED]',
      )
      .replaceAll(
        RegExp(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\\s\\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
        '[REDACTED_PRIVATE_KEY]',
      );
  final limit = math.max(0, maxChars).toInt();
  if (safe.length > limit) safe = safe.substring(safe.length - limit);
  return safe;
}

/// A bounded retry budget: enough room for several evidence-based repairs,
/// while preventing unbounded PR creation or resource consumption.
bool kingAiCiRepairAttemptAllowed(int attempts, {int maxAttempts = 8}) =>
    attempts >= 0 && maxAttempts > 0 && attempts < maxAttempts;

/// Exponential cooldown between repair attempts, capped at six hours.
Duration kingAiCiRepairBackoff(
  int completedAttempts, {
  Duration base = const Duration(minutes: 5),
  Duration maximum = const Duration(hours: 6),
}) {
  if (completedAttempts <= 0 || base <= Duration.zero || maximum <= Duration.zero) {
    return Duration.zero;
  }
  final exponent = completedAttempts.clamp(0, 10).toInt();
  final multiplier = 1 << exponent;
  final candidate = base * multiplier;
  return candidate > maximum ? maximum : candidate;
}
