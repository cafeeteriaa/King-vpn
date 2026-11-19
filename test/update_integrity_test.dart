import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/update_integrity.dart';

void main() {
  group('verifySha256Bytes', () {
    final hello = 'hello'.codeUnits;
    const helloSha256 = '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

    test('accepts the correct SHA-256 digest', () {
      expect(verifySha256Bytes(hello, helloSha256), isTrue);
      expect(verifySha256Bytes(hello, helloSha256.toUpperCase()), isTrue);
    });

    test('rejects a mismatch and malformed or missing digest', () {
      expect(verifySha256Bytes(hello, '0' * 64), isFalse);
      expect(verifySha256Bytes(hello, ''), isFalse);
      expect(verifySha256Bytes(hello, 'not-a-hash'), isFalse);
      expect(verifySha256Bytes(hello, 'a' * 63), isFalse);
    });
  });
}
