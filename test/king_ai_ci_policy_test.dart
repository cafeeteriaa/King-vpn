import 'package:flutter_test/flutter_test.dart';
import '../lib/king_ai_ci_policy.dart';

void main() {
  group('King AI CI repair policy', () {
    test('redacts GitHub tokens, bearer credentials and key assignments', () {
      const raw = 'ghp_123456789012345678901234567890 '
          'github_pat_abcdefghijklmnopqrstuvwxyz012345 '
          'Bearer abc.def.ghi api_key=super-secret password:letmein';
      final safe = redactKingAiCiEvidence(raw);
      expect(safe, isNot(contains('ghp_')));
      expect(safe, isNot(contains('github_pat_')));
      expect(safe, isNot(contains('abc.def.ghi')));
      expect(safe, isNot(contains('super-secret')));
      expect(safe, isNot(contains('letmein')));
      expect(safe, contains('[REDACTED]'));
    });

    test('redacts common provider tokens, basic auth and all PEM private-key labels', () {
      const raw = 'sk-123456789012345678901234 xoxb-123456789012 '
          'AKIA1234567890ABCDEF AIza1234567890123456789012345678901234 '
          'Basic dXNlcjpwYXNzd29yZA== '
          '-----BEGIN PRIVATE KEY-----\nsecret-material\n-----END PRIVATE KEY-----';
      final safe = redactKingAiCiEvidence(raw);
      expect(safe, isNot(contains('sk-123456')));
      expect(safe, isNot(contains('xoxb-')));
      expect(safe, isNot(contains('AKIA1234567890ABCDEF')));
      expect(safe, isNot(contains('AIza')));
      expect(safe, isNot(contains('dXNlcjpwYXNzd29yZA==')));
      expect(safe, isNot(contains('secret-material')));
      expect(safe, contains('[REDACTED_PRIVATE_KEY]'));
      expect(
        redactKingAiCiEvidence('https://user:secret@example.com/path'),
        isNot(contains('user:secret')),
      );
    });

    test('bounds evidence to the requested tail window', () {
      final safe = redactKingAiCiEvidence('0123456789', maxChars: 4);
      expect(safe, '6789');
      expect(redactKingAiCiEvidence('abc', maxChars: 0), isEmpty);
    });

    test('allows a finite eight-attempt repair budget by default', () {
      expect(kingAiCiRepairAttemptAllowed(0), isTrue);
      expect(kingAiCiRepairAttemptAllowed(7), isTrue);
      expect(kingAiCiRepairAttemptAllowed(8), isFalse);
      expect(kingAiCiRepairAttemptAllowed(-1), isFalse);
    });

    test('uses exponential cooldown capped at six hours', () {
      expect(kingAiCiRepairBackoff(0), Duration.zero);
      expect(kingAiCiRepairBackoff(1), const Duration(minutes: 10));
      expect(kingAiCiRepairBackoff(2), const Duration(minutes: 20));
      expect(kingAiCiRepairBackoff(3), const Duration(minutes: 40));
      expect(kingAiCiRepairBackoff(10), const Duration(hours: 6));
    });

    test('supports an explicitly smaller retry budget', () {
      expect(kingAiCiRepairAttemptAllowed(0, maxAttempts: 1), isTrue);
      expect(kingAiCiRepairAttemptAllowed(1, maxAttempts: 1), isFalse);
    });

    test('backs off exponentially and respects the maximum delay', () {
      expect(kingAiCiRepairBackoff(0), Duration.zero);
      expect(kingAiCiRepairBackoff(1), const Duration(minutes: 10));
      expect(kingAiCiRepairBackoff(2), const Duration(minutes: 20));
      expect(kingAiCiRepairBackoff(20), const Duration(hours: 6));
      expect(kingAiCiRepairBackoff(-1), Duration.zero);
    });
  });
}
