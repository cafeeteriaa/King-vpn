import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../lib/fresh_resource_store.dart';

void main() {
  group('FreshResourceStore capacity and normalization', () {
    test('declares four million persistent entries and sharded streaming', () {
      expect(FreshResourceStore.maxEntries, 4000000);
      expect(FreshResourceStore.shardCount, 256);
    });

    test('exposes bounded preview and streaming APIs', () {
      expect(FreshResourceStore.readPreview, isA<Function>());
      expect(FreshResourceStore.streamLinks, isA<Function>());
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

    test('merges disk-backed batches, deduplicates, and returns bounded previews', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-store-');
      try {
        Iterable<String> values() sync* {
          for (var i = 0; i < 1100; i++) {
            yield 'vless://$i@example.test:443';
          }
          yield 'VLESS://0@example.test:443';
          yield 'not-a-config';
        }

        expect(
          await FreshResourceStore.merge(values(), root: root),
          1100,
        );
        expect(await FreshResourceStore.count(root: root), 1100);
        expect(
          await FreshResourceStore.readPreview(limit: 7, root: root),
          hasLength(7),
        );
        expect(await FreshResourceStore.streamLinks(root: root).length, 1100);
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('migrates the legacy flat file and repairs interrupted count metadata', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-migrate-');
      try {
        final folder = Directory('${root.path}/${FreshResourceStore.directoryName}');
        await folder.create(recursive: true);
        await File('${folder.path}/configs.txt').writeAsString(
          'vless://one@example.test:443\nvmess://two@example.test:443\n',
          flush: true,
        );

        expect(await FreshResourceStore.count(root: root), 2);
        expect(
          await File('${folder.path}/configs.txt.migrated').exists(),
          isTrue,
        );
        await File('${folder.path}/metadata.json').writeAsString('{"schema":2,"count":1}');
        await File('${folder.path}/.inventory_dirty').writeAsString('1');
        expect(await FreshResourceStore.count(root: root), 2);
      } finally {
        await root.delete(recursive: true);
      }
    });
  });
}
