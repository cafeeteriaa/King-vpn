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

    test('retains every distinct entry beyond the former 20000-entry ceiling', () {
      final links = List<String>.generate(
        20005,
        (index) => 'vless://id$index@example.com:443',
      );

      final normalized = FreshResourceStore.normalizeLinks(links);

      expect(normalized, hasLength(20005));
      expect(normalized.first, 'vless://id0@example.com:443');
      expect(normalized.last, 'vless://id20004@example.com:443');
    });

    test('accepts supported links longer than the former 65536-character ceiling', () {
      final longLink =
          'vless://id@example.com:443?metadata=' + ('x' * 65537);

      expect(longLink.length, greaterThan(65536));
      expect(FreshResourceStore.normalizeLink(longLink), longLink);
    });
  });
}
