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

    test('allows no more than two repair iterations by default', () {
      expect(kingAiCiRepairAttemptAllowed(0), isTrue);
      expect(kingAiCiRepairAttemptAllowed(1), isTrue);
      expect(kingAiCiRepairAttemptAllowed(2), isFalse);
      expect(kingAiCiRepairAttemptAllowed(-1), isFalse);
    });

    test('supports an explicitly smaller retry budget', () {
      expect(kingAiCiRepairAttemptAllowed(0, maxAttempts: 1), isTrue);
      expect(kingAiCiRepairAttemptAllowed(1, maxAttempts: 1), isFalse);
    });
  });
}
