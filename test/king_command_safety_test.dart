import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/king_command_safety.dart';

void main() {
  group('KingCommandSafety', () {
    test('strips Persian and English wake prefixes only at the beginning', () {
      expect(KingCommandSafety.stripKingAddress('کینگ وصل شو'), 'وصل شو');
      expect(KingCommandSafety.stripKingAddress('سلام کینگ جان وضعیت اتصال'), 'وضعیت اتصال');
      expect(KingCommandSafety.stripKingAddress('King, connect now'), 'connect now');
      expect(KingCommandSafety.stripKingAddress('سلام وضعیت اتصال'), 'سلام وضعیت اتصال');
      expect(KingCommandSafety.stripKingAddress('کینگ'), '');
    });

    test('negative connect commands are blocked', () {
      expect(KingCommandSafety.negatesConnection('کینگ اتصال نکن'), isTrue);
      expect(KingCommandSafety.negatesConnection('لطفاً اتصال را شروع نکنید'), isTrue);
      expect(KingCommandSafety.negatesConnection('کینگ متصل نشوید'), isTrue);
      expect(KingCommandSafety.negatesConnection('کانکت نکن'), isTrue);
      expect(KingCommandSafety.negatesConnection('اتصال نگیر'), isTrue);
      expect(KingCommandSafety.negatesConnection('کینگ اتصال نزن'), isTrue);
      expect(KingCommandSafety.negatesConnection('نمیخوام قطع اتصال کنی'), isTrue);
      expect(KingCommandSafety.negatesConnection("I don't want you to disconnect"), isTrue);
      expect(KingCommandSafety.negatesConnection('وصل نزن'), isTrue);
      expect(KingCommandSafety.negatesConnection('نمیخوام وصل بشی'), isTrue);
      expect(KingCommandSafety.negatesConnection('نمی‌خوام اتصال برقرار کنی'), isTrue);
      expect(KingCommandSafety.negatesConnection('اتصال را شروع نکن'), isTrue);
      expect(KingCommandSafety.negatesConnection('کینگ وصل نشو'), isTrue);
      expect(KingCommandSafety.negatesConnection('اتصال نداشته باش'), isTrue);
      expect(KingCommandSafety.negatesConnection('قطع نکن'), isTrue);
      expect(KingCommandSafety.negatesConnection("don't disconnect"), isTrue);
      expect(KingCommandSafety.negatesConnection('do not connect'), isTrue);
      expect(KingCommandSafety.negatesConnection('کینگ وصل شو'), isFalse);
      expect(KingCommandSafety.negatesConnection('اتصال خلبان را شروع کن'), isFalse);
    });

    test('connect intent recognises متصل and rejects status/negated commands', () {
      expect(KingCommandSafety.isConnectIntent('به نت ملی متصل شو'), isTrue);
      expect(KingCommandSafety.isConnectIntent('کینگ متصل شو'), isTrue);
      expect(KingCommandSafety.isConnectIntent('کینگ نت جهانی وصل شو'), isTrue);
      expect(KingCommandSafety.isConnectIntent('وضعیت اتصال نت ملی'), isFalse);
      expect(KingCommandSafety.isConnectIntent('کینگ نت ملی وصل نشو'), isFalse);
      expect(KingCommandSafety.isConnectIntent('لطفاً اتصال را شروع نکن'), isFalse);
    });

    test('explicit domestic and global network requests are distinguished', () {
      expect(KingCommandSafety.requestedNetworkMode('کینگ نت ملی وصل شو'),
          KingRequestedNetworkMode.domestic);
      expect(KingCommandSafety.requestedNetworkMode('به اینترنت جهانی وصل شو'),
          KingRequestedNetworkMode.global);
      expect(KingCommandSafety.requestedNetworkMode('شبکه ملی اتصال برقرار کن'),
          KingRequestedNetworkMode.domestic);
      expect(KingCommandSafety.requestedNetworkMode('اینترنت ملی وصل شو'),
          KingRequestedNetworkMode.domestic);
      expect(KingCommandSafety.requestedNetworkMode('کینگ نت ملی وصل نشو'), isNull);
      expect(KingCommandSafety.requestedNetworkMode('وضعیت اتصال نت ملی'), isNull);
    });

    test('connection status questions are not connect commands', () {
      expect(KingCommandSafety.isStatusRequest('کینگ وضعیت اتصال'), isTrue);
      expect(KingCommandSafety.isStatusRequest('connection status'), isTrue);
      expect(KingCommandSafety.isStatusRequest('کینگ وصل شو'), isFalse);
    });

    test('negative scan commands are blocked', () {
      expect(KingCommandSafety.negatesScan('اسکن DNS نکن'), isTrue);
      expect(KingCommandSafety.negatesScan('اسکن DNS نکنید'), isTrue);
      expect(KingCommandSafety.negatesScan('لطفاً اسکن را انجام ندهید'), isTrue);
      expect(KingCommandSafety.negatesScan('اسکن DNS نزن'), isTrue);
      expect(KingCommandSafety.negatesScan('نمیخوام اسکن IP انجام بدی'), isTrue);
      expect(KingCommandSafety.negatesScan('نمی‌خوام اسکن DNS انجام بدی'), isTrue);
      expect(KingCommandSafety.negatesScan('اسکن را انجام نده'), isTrue);
      expect(KingCommandSafety.negatesScan("don't scan"), isTrue);
      expect(KingCommandSafety.negatesScan('اسکن خلبان را شروع کن'), isFalse);
      expect(KingCommandSafety.negatesScan('پویش DNS را آغاز کن'), isFalse);
    });
  });
}
