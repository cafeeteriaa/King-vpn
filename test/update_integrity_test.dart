import 'dart:io';

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
      expect(verifySha256Bytes(hello, List.filled(64, '0').join()), isFalse);
      expect(verifySha256Bytes(hello, ''), isFalse);
      expect(verifySha256Bytes(hello, 'not-a-hash'), isFalse);
      expect(verifySha256Bytes(hello, List.filled(63, 'a').join()), isFalse);
    });
  });

  group('verifySha256File', () {
    test('streams file bytes and rejects missing or invalid digests', () async {
      final directory = await Directory.systemTemp.createTemp('king-update-test-');
      try {
        final file = File('${directory.path}/test.apk');
        await file.writeAsBytes('hello'.codeUnits, flush: true);
        const digest = '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';
        expect(await verifySha256File(file, digest), isTrue);
        expect(await verifySha256File(file, ''), isFalse);
        expect(await verifySha256File(file, List.filled(64, '0').join()), isFalse);
        expect(await verifySha256File(File('${directory.path}/missing.apk'), digest), isFalse);
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });
}
