import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/update_integrity.dart';

void main() {
  group('isAllowedUpdateDownloadUri', () {
    test('accepts official HTTPS GitHub release hosts', () {
      for (final value in [
        'https://github.com/owner/repo/releases/download/v1/app.apk',
        'https://release-assets.githubusercontent.com/assets/app.apk',
        'https://objects.githubusercontent.com/assets/app.apk',
      ]) {
        expect(isAllowedUpdateDownloadUri(Uri.parse(value)), isTrue,
            reason: value);
      }
    });

    test('rejects HTTP, lookalike hosts, credentials and nonstandard ports', () {
      for (final value in [
        'http://github.com/owner/repo/app.apk',
        'https://github.com.evil.example/app.apk',
        'https://release-assets.githubusercontent.com.evil.example/app.apk',
        'https://user:pass@github.com/owner/repo/app.apk',
        'https://github.com:8443/owner/repo/app.apk',
        'https://example.com/app.apk',
      ]) {
        expect(isAllowedUpdateDownloadUri(Uri.parse(value)), isFalse,
            reason: value);
      }
    });
  });

  group('resolveAllowedUpdateRedirect', () {
    test('accepts HTTPS release hosts and safe relative redirects', () {
      final current = Uri.parse('https://github.com/owner/repo/releases/download/v1/app.apk');
      expect(
        resolveAllowedUpdateRedirect(current, 'https://release-assets.githubusercontent.com/assets/app.apk')?.host,
        'release-assets.githubusercontent.com',
      );
      expect(
        resolveAllowedUpdateRedirect(current, '/owner/repo/releases/download/v2/app.apk')?.host,
        'github.com',
      );
    });

    test('rejects untrusted, downgraded, missing and malformed redirects', () {
      final current = Uri.parse('https://github.com/owner/repo/app.apk');
      for (final location in [
        'https://github.com.evil.example/app.apk',
        'http://github.com/owner/repo/app.apk',
        'https://evil.example/app.apk',
        '',
      ]) {
        expect(resolveAllowedUpdateRedirect(current, location), isNull,
            reason: location);
      }
      expect(resolveAllowedUpdateRedirect(current, null), isNull);
      expect(resolveAllowedUpdateRedirect(current, 'http://[invalid'), isNull);
    });
  });

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
