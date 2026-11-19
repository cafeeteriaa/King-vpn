import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/king_command_safety.dart';

void main() {
  group('KingCommandSafety', () {
    test('negative connect commands are blocked', () {
      expect(KingCommandSafety.negatesConnection('کینگ اتصال نکن'), isTrue);
      expect(KingCommandSafety.negatesConnection('نمیخوام وصل بشی'), isTrue);
      expect(KingCommandSafety.negatesConnection('نمی‌خوام اتصال برقرار کنی'), isTrue);
      expect(KingCommandSafety.negatesConnection('اتصال را شروع نکن'), isTrue);
      expect(KingCommandSafety.negatesConnection('کینگ وصل نشو'), isTrue);
      expect(KingCommandSafety.negatesConnection('اتصال نداشته باش'), isTrue);
      expect(KingCommandSafety.negatesConnection('کینگ وصل شو'), isFalse);
      expect(KingCommandSafety.negatesConnection('اتصال خلبان را شروع کن'), isFalse);
    });

    test('negative scan commands are blocked', () {
      expect(KingCommandSafety.negatesScan('اسکن DNS نکن'), isTrue);
      expect(KingCommandSafety.negatesScan('نمیخوام اسکن IP انجام بدی'), isTrue);
      expect(KingCommandSafety.negatesScan('نمی‌خوام اسکن DNS انجام بدی'), isTrue);
      expect(KingCommandSafety.negatesScan('اسکن را انجام نده'), isTrue);
      expect(KingCommandSafety.negatesScan('اسکن خلبان را شروع کن'), isFalse);
      expect(KingCommandSafety.negatesScan('پویش DNS را آغاز کن'), isFalse);
    });
  });
}
