import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/fresh_resource_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory testRoot;

  setUp(() async {
    testRoot = await Directory.systemTemp.createTemp('king-vpn-resource-store-');
    pathChannel.setMockMethodCallHandler((call) async {
      if (call.method == 'getApplicationSupportPath') return testRoot.path;
      return null;
    });
  });

  tearDown(() async {
    pathChannel.setMockMethodCallHandler(null);
    if (await testRoot.exists()) await testRoot.delete(recursive: true);
  });

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

  group('FreshResourceStore persistence', () {
    test('saves and reads every entry beyond the previous inventory ceiling', () async {
      final values = List<String>.generate(
        20037,
        (index) => 'vless://persist$index@example.com:443',
      );
      final saved = await FreshResourceStore.saveSnapshot(values, source: 'test');
      final restored = await FreshResourceStore.readLinks();
      final metadata = await FreshResourceStore.metadata();

      expect(saved, values.length);
      expect(restored, hasLength(values.length));
      expect(restored.last, values.last);
      expect(metadata['count'], values.length);
      expect(metadata['schema'], 2);
      expect(metadata['source'], 'test');
    });

    test('serializes concurrent merges without losing either source', () async {
      await FreshResourceStore.saveSnapshot(['vless://base@example.com:443']);
      await Future.wait([
        FreshResourceStore.merge(['vless://source-a@example.com:443'], source: 'a'),
        FreshResourceStore.merge(['vless://source-b@example.com:443'], source: 'b'),
      ]);

      final restored = await FreshResourceStore.readLinks();
      expect(restored, containsAll([
        'vless://base@example.com:443',
        'vless://source-a@example.com:443',
        'vless://source-b@example.com:443',
      ]));
      expect(restored, hasLength(3));
    });

    test('reads legacy schema 1 metadata without inventing schema 2 fields', () async {
      final path = await FreshResourceStore.storagePath;
      final metadataFile = File('$path/metadata.json');
      await metadataFile.writeAsString(
        '{"schema":1,"source":"legacy","count":1,"updatedAt":"2026-01-01T00:00:00Z"}',
      );

      final metadata = await FreshResourceStore.metadata();
      expect(metadata['schema'], 1);
      expect(metadata['source'], 'legacy');
      expect(metadata.containsKey('bytes'), isFalse);
    });
  });
}
