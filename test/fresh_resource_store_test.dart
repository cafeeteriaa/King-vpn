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
          'hy2://secret@example.com:443',
          'tuic://id:password@example.com:443',
        ]),
        hasLength(7),
      );
    });

    test('rejects arbitrary text and unsupported schemes', () {
      expect(
        FreshResourceStore.normalizeLinks([
          'not a config',
          'https://example.com',
          'file:///etc/passwd',
          'ftp://example.com/config',
          '',
        ]),
        isEmpty,
      );
    });

    test('deduplicates case-insensitively without dropping unique entries', () {
      final values = FreshResourceStore.normalizeLinks([
        'vless://id@example.com:443',
        'VLESS://id@example.com:443',
        'vmess://abc',
      ]);
      expect(values, hasLength(2));
      expect(values.first, 'vless://id@example.com:443');
    });

    test('does not truncate inventories at the former 20000-entry ceiling', () {
      final values = List<String>.generate(
        20037,
        (index) => 'vless://id$index@example.com:443',
      );
      final normalized = FreshResourceStore.normalizeLinks(values);
      expect(normalized, hasLength(values.length));
      expect(normalized.last, values.last);
    });

    test('does not silently reject a valid URI above the former byte ceiling', () {
      final payload = 'vless://${'a' * 70000}@example.com:443';
      expect(FreshResourceStore.normalizeLink(payload), payload);
    });

    test('preserves distinct payloads and rejects a missing URI scheme', () {
      expect(FreshResourceStore.normalizeLink('vless:missing-separator'), isNull);
      expect(
        FreshResourceStore.normalizeLinks([
          'vless://one@example.com:443',
          'vless://two@example.com:443',
        ]),
        hasLength(2),
      );
    });
  });
}
