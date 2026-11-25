import 'package:flutter_test/flutter_test.dart';
import '../lib/fresh_resource_store.dart';

void main() {
  group('FreshResourceStore normalization', () {
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

    test('deduplicates case-insensitively', () {
      final values = FreshResourceStore.normalizeLinks([
        'vless://id@example.com:443',
        'VLESS://id@example.com:443',
        'vmess://abc',
      ]);
      expect(values, hasLength(2));
    });

    test('retains inventories larger than the former fixed entry ceiling', () {
      final values = FreshResourceStore.normalizeLinks(
        Iterable<int>.generate(20005)
            .map((index) => 'vless://node$index@example.com:443'),
      );
      expect(values, hasLength(20005));
      expect(values.first, 'vless://node0@example.com:443');
      expect(values.last, 'vless://node20004@example.com:443');
    });

    test('rejects oversized individual links', () {
      expect(
        FreshResourceStore.normalizeLink('vless://' + ('a' * 65537)),
        isNull,
      );
    });
  });
}
