import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../lib/fresh_resource_store.dart';

void main() {
  group('FreshResourceStore normalization', () {
    test('offline cache capacity is four million with a separate 500 MiB disk budget', () {
      expect(FreshResourceStore.maxEntries, 4000000);
      expect(FreshResourceStore.maxStorageBytes, 500 * 1024 * 1024);
    });

    test('cursor returns bounded pages and tracks completion', () async {
      final cursor = FreshResourceCursor(StreamIterator<String>(
        Stream<String>.fromIterable([
          'vless://one@example.org:443',
          'invalid',
          'vmess://two',
          'trojan://three@example.org:443',
        ]),
      ));
      expect(await cursor.nextPage(limit: 2), [
        'vless://one@example.org:443',
        'vmess://two',
      ]);
      expect(cursor.isDone, isFalse);
      expect(await cursor.nextPage(limit: 2), [
        'trojan://three@example.org:443',
      ]);
      expect(cursor.isDone, isTrue);
      await cursor.close();
    });

    test('accepts supported V2Ray URI schemes', () {
      expect(
        FreshResourceStore.normalizeLinks([
          'vless://id@example.com:443',
          'vmess://eyJ2IjoiMiJ9',
          'trojan://secret@example.com:443',
          'ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388',
          'hysteria2://secret@example.com:443',
          'tuic://id:password@example.com:443',
        ]),
        hasLength(6),
      );
    });

    test('rejects arbitrary text and unsafe schemes', () {
      expect(
        FreshResourceStore.normalizeLinks([
          'not a config',
          'https://example.com',
          'file:///etc/passwd',
          '',
        ]),
        isEmpty,
      );
    });

    test('deduplicates case-insensitively and enforces input bounds', () {
      final values = FreshResourceStore.normalizeLinks([
        'vless://id@example.com:443',
        'VLESS://id@example.com:443',
        'vmess://abc',
      ]);
      expect(values, hasLength(2));
    });

    test('rejects oversized individual links', () {
      expect(
        FreshResourceStore.normalizeLink('vless://' + ('a' * 65537)),
        isNull,
      );
    });
  });
}
