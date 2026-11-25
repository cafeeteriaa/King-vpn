import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../lib/fresh_resource_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testRoot;

  setUp(() async {
    testRoot = await Directory.systemTemp.createTemp('king-vpn-resource-store-');
    FreshResourceStore.setRootDirectoryForTesting(testRoot);
  });

  tearDown(() async {
    FreshResourceStore.setRootDirectoryForTesting(null);
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
      expect(FreshResourceStore.normalizeLink('vless://one@example.com:443\nvless://two@example.com:443'), isNull);
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

    test('reads consecutive pages without loading the complete inventory', () async {
      final values = List<String>.generate(
        257,
        (index) => 'vless://page$index@example.com:443',
      );
      await FreshResourceStore.saveSnapshot(values);

      final first = await FreshResourceStore.readPage(limit: 100);
      final second = await FreshResourceStore.readPage(offset: 100, limit: 100);
      final third = await FreshResourceStore.readPage(offset: 200, limit: 100);
      final fourth = await FreshResourceStore.readPage(offset: 300, limit: 100);

      expect(first.items, values.sublist(0, 100));
      expect(first.hasMore, isTrue);
      expect(second.items, values.sublist(100, 200));
      expect(second.hasMore, isTrue);
      expect(third.items, values.sublist(200, 257));
      expect(third.hasMore, isFalse);
      expect(fourth.items, isEmpty);
      expect(fourth.hasMore, isFalse);
    });

    test('paged reads reject invalid offsets and page sizes', () async {
      await expectLater(
        FreshResourceStore.readPage(offset: -1),
        throwsArgumentError,
      );
      await expectLater(
        FreshResourceStore.readPage(limit: 0),
        throwsArgumentError,
      );
    });

    test('stream-native merge persists records without requiring an Iterable input', () async {
      final total = await FreshResourceStore.mergeStream(
        Stream<String>.fromIterable([
          'vless://stream-a@example.com:443',
          'vless://stream-b@example.com:443',
        ]),
        source: 'stream-test',
      );

      expect(total, 2);
      expect(
        await FreshResourceStore.readLinks(),
        [
          'vless://stream-a@example.com:443',
          'vless://stream-b@example.com:443',
        ],
      );
    });

    test('failed replacement preserves the previous committed snapshot', () async {
      await FreshResourceStore.saveSnapshot([
        'vless://previous@example.com:443',
      ]);

      Iterable<String> interruptedInput() sync* {
        yield 'vless://partial@example.com:443';
        throw StateError('simulated interrupted source');
      }

      await expectLater(
        FreshResourceStore.saveSnapshot(interruptedInput()),
        throwsA(isA<StateError>()),
      );
      expect(
        await FreshResourceStore.readLinks(),
        ['vless://previous@example.com:443'],
      );
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

    test('uses a sparse on-disk index for deep pages', () async {
      final values = List<String>.generate(
        777,
        (index) => 'vless://indexed$index@example.com:443',
      );
      await FreshResourceStore.saveSnapshot(values);
      final firstRead = await FreshResourceStore.readPage(offset: 600, limit: 25);
      expect(firstRead.items, values.sublist(600, 625));
      expect(firstRead.hasMore, isTrue);

      final path = await FreshResourceStore.storagePath;
      final indexFile = File('$path/configs.txt.idx');
      expect(await indexFile.exists(), isTrue);
      expect(await indexFile.length(), greaterThan(36));
    });

    test('rebuilds a truncated or corrupt offset index from the snapshot', () async {
      final values = List<String>.generate(
        300,
        (index) => 'vless://repair$index@example.com:443',
      );
      await FreshResourceStore.saveSnapshot(values);
      await FreshResourceStore.readPage(offset: 270, limit: 20);

      final path = await FreshResourceStore.storagePath;
      final indexFile = File('$path/configs.txt.idx');
      await indexFile.writeAsBytes([0, 1, 2, 3], flush: true);

      final repaired = await FreshResourceStore.readPage(offset: 270, limit: 20);
      expect(repaired.items, values.sublist(270, 290));
      expect(await indexFile.length(), greaterThan(36));
    });

    test('rebuilds the index after the snapshot changes outside the store', () async {
      await FreshResourceStore.saveSnapshot(['vless://old@example.com:443']);
      await FreshResourceStore.readPage();
      final path = await FreshResourceStore.storagePath;
      final snapshot = File('$path/configs.txt');
      await snapshot.writeAsString(
        'vless://new-a@example.com:443\\n'
        'vless://new-b@example.com:443\\n',
        flush: true,
      );

      final refreshed = await FreshResourceStore.readPage();
      expect(refreshed.items, [
        'vless://new-a@example.com:443',
        'vless://new-b@example.com:443',
      ]);
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
