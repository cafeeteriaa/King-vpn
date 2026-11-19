import 'dart:math' as math;

/// Removes common credential forms from CI output before local-model context.
String redactKingAiCiEvidence(String input, {int maxChars = 12000}) {
  var safe = input
      .replaceAll(RegExp(r'gh[pousr]_[A-Za-z0-9]{20,}'), '[REDACTED_GITHUB_TOKEN]')
      .replaceAll(RegExp(r'github_pat_[A-Za-z0-9_]{20,}'), '[REDACTED_GITHUB_TOKEN]')
      .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false), 'Bearer [REDACTED]')
      .replaceAll(
        RegExp(r'(api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[:=]\s*[^\s,;]+', caseSensitive: false),
        '[REDACTED]',
      )
      .replaceAll(
        RegExp(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
        '[REDACTED_PRIVATE_KEY]',
      );
  final limit = math.max(0, maxChars).toInt();
  if (safe.length > limit) safe = safe.substring(safe.length - limit);
  return safe;
}

/// Retry policy is deliberately finite. Callers still require human review.
bool kingAiCiRepairAttemptAllowed(int attempts, {int maxAttempts = 2}) =>
    attempts >= 0 && maxAttempts > 0 && attempts < maxAttempts;
