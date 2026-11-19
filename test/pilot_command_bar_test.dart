import 'package:flutter_test/flutter_test.dart';
import '../lib/king_command_safety.dart';

void main() {
  group('King command safety', () {
    test('strips the King wake name without granting privileges', () {
      expect(KingCommandSafety.stripKingAddress('سلام کینگ وصل شو'), 'وصل شو');
      expect(KingCommandSafety.stripKingAddress('King جان وضعیت اتصال'), 'وضعیت اتصال');
    });

    test('does not turn a negated connect command into an active connect', () {
      expect(KingCommandSafety.negatesConnection('به من وصل نشو'), isTrue);
      expect(KingCommandSafety.negatesConnection('اتصال برقرار کن'), isFalse);
      expect(KingCommandSafety.negatesConnection('قطع اتصال نکن'), isTrue);
    });

    test('recognizes negated scanner commands', () {
      expect(KingCommandSafety.negatesScan('اسکن نکن'), isTrue);
      expect(KingCommandSafety.negatesScan('خلبان را اسکن کن'), isFalse);
    });
  });
}
