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

    test('bounds evidence to the requested tail window', () {
      final safe = redactKingAiCiEvidence('0123456789', maxChars: 4);
      expect(safe, '6789');
      expect(redactKingAiCiEvidence('abc', maxChars: 0), isEmpty);
    });

    test('allows up to eight bounded repair iterations by default', () {
      for (var attempt = 0; attempt < 8; attempt++) {
        expect(kingAiCiRepairAttemptAllowed(attempt), isTrue);
      }
      expect(kingAiCiRepairAttemptAllowed(8), isFalse);
      expect(kingAiCiRepairAttemptAllowed(-1), isFalse);
    });

    test('supports a smaller explicitly configured retry budget', () {
      expect(kingAiCiRepairAttemptAllowed(0, maxAttempts: 1), isTrue);
      expect(kingAiCiRepairAttemptAllowed(1, maxAttempts: 1), isFalse);
    });

    test('backs off exponentially and respects the maximum delay', () {
      expect(kingAiCiRepairBackoff(0), Duration.zero);
      expect(kingAiCiRepairBackoff(1), const Duration(minutes: 10));
      expect(kingAiCiRepairBackoff(2), const Duration(minutes: 20));
      expect(kingAiCiRepairBackoff(3), const Duration(minutes: 40));
      expect(kingAiCiRepairBackoff(10), const Duration(hours: 6));
      expect(kingAiCiRepairBackoff(20), const Duration(hours: 6));
      expect(kingAiCiRepairBackoff(-1), Duration.zero);
    });
  });
}
