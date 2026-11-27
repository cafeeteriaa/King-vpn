import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../lib/fresh_resource_store.dart';

void main() {
  group('FreshResourceStore capacity and normalization', () {
    test('declares four million persistent entries and sharded streaming', () {
      expect(FreshResourceStore.maxEntries, 4000000);
      expect(FreshResourceStore.shardCount, 256);
    });

    test('exposes bounded preview, resumable batch and streaming APIs', () {
      expect(FreshResourceStore.readPreview, isA<Function>());
      expect(FreshResourceStore.readBatch, isA<Function>());
      expect(FreshResourceStore.streamLinks, isA<Function>());
    });

    test('accepts supported VPN URI schemes', () {
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


    test('preserves case-sensitive credentials while normalizing scheme case', () {
      final values = FreshResourceStore.normalizeLinks([
        'trojan://Secret@node.example:443',
        'trojan://secret@node.example:443',
        'TROJAN://Secret@node.example:443',
      ]);
      expect(values, hasLength(2));
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


    test('stores distinct case-sensitive credentials as separate offline profiles', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-case-');
      try {
        final total = await FreshResourceStore.merge(
          <String>[
            'trojan://Secret@node.example:443',
            'trojan://secret@node.example:443',
            'TROJAN://Secret@node.example:443',
          ],
          root: root,
        );
        expect(total, 2);
        final stored = await FreshResourceStore.readLinks(limit: 10, root: root);
        expect(stored, hasLength(2));
        expect(stored.toSet(), hasLength(2));
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('deduplicates case-insensitively and rejects oversized links', () {
      final values = FreshResourceStore.normalizeLinks([
        'vless://id@example.com:443',
        'VLESS://id@example.com:443',
        'vmess://abc',
      ]);
      expect(values, hasLength(2));
      expect(
        FreshResourceStore.normalizeLink('vless://' + ('a' * 65537)),
        isNull,
      );
    });


    test('optional four-million profile disk soak', () async {
      const runSoak = bool.fromEnvironment('KING_RUN_4M_SOAK', defaultValue: false);
      if (!runSoak) return;
      final root = await Directory.systemTemp.createTemp('king-offline-4m-soak-');
      final watch = Stopwatch()..start();
      try {
        Iterable<String> profiles() sync* {
          for (var i = 0; i < FreshResourceStore.maxEntries; i++) {
            final suffix = i.toRadixString(16).padLeft(12, '0');
            yield 'vless://00000000-0000-4000-8000-$suffix@n$i.example:443?encryption=none&security=tls&type=tcp';
          }
        }

        final total = await FreshResourceStore.merge(
          profiles(),
          source: 'four-million-soak',
          root: root,
        );
        expect(total, FreshResourceStore.maxEntries);
        expect(await FreshResourceStore.count(root: root), FreshResourceStore.maxEntries);
        final first = await FreshResourceStore.readBatch(limit: 300, root: root);
        final second = await FreshResourceStore.readBatch(limit: 300, root: root);
        expect(first, hasLength(300));
        expect(second, hasLength(300));
        expect(first.toSet().intersection(second.toSet()), isEmpty);

        var bytes = 0;
        await for (final entity in (await FreshResourceStore.directory(root: root)).list()) {
          if (entity is File && entity.path.endsWith('.jsonl')) {
            bytes += await entity.length();
          }
        }
        watch.stop();
        // ignore: avoid_print
        print('KING_4M_SOAK entries=$total bytes=$bytes elapsedMs=${watch.elapsedMilliseconds}');
      } finally {
        watch.stop();
        await root.delete(recursive: true);
      }
    }, timeout: const Timeout(Duration(minutes: 60)));

    test('merges disk batches, deduplicates and advances persistent cursors', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-store-');
      try {
        Iterable<String> values() sync* {
          for (var i = 0; i < 1100; i++) {
            yield 'vless://$i@example.test:443';
          }
          yield 'VLESS://0@example.test:443';
          yield 'not-a-config';
        }

        expect(await FreshResourceStore.merge(values(), root: root), 1100);
        expect(await FreshResourceStore.count(root: root), 1100);
        expect(
          await FreshResourceStore.readPreview(limit: 7, root: root),
          hasLength(7),
        );
        final firstBatch = await FreshResourceStore.readBatch(limit: 20, root: root);
        final secondBatch = await FreshResourceStore.readBatch(limit: 20, root: root);
        expect(firstBatch, hasLength(20));
        expect(secondBatch, hasLength(20));
        expect(firstBatch.toSet().intersection(secondBatch.toSet()), isEmpty);
        expect(await FreshResourceStore.streamLinks(root: root).length, 1100);
      } finally {
        await root.delete(recursive: true);
      }
    });


    test('fills the final capacity slot even when earlier batch entries are duplicates', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-capacity-edge-');
      try {
        const existing = 'vless://already-stored@example.test:443';
        await FreshResourceStore.merge(<String>[existing], root: root);
        final folder = Directory(root.path + '/' + FreshResourceStore.directoryName);
        await File(folder.path + '/metadata.json').writeAsString(
          '{"schema":2,"count":3999999,"capacity":4000000}',
          flush: true,
        );
        Iterable<String> incoming() sync* {
          yield existing;
          for (var i = 0; i < 4095; i++) {
            yield 'vless://new-$i@example.test:443';
          }
        }

        expect(await FreshResourceStore.merge(incoming(), root: root), 4000000);
        final stored = await FreshResourceStore.readLinks(limit: 10, root: root);
        expect(stored, hasLength(2));
        expect(stored, contains(existing));
        expect(stored.any((link) => link.contains('new-')), isTrue);
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('small offline inventories never repeat records inside one batch', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-small-');
      try {
        await FreshResourceStore.merge(
          <String>[
            'vless://small-one@example.test:443',
            'vless://small-two@example.test:443',
          ],
          root: root,
        );
        final batch = await FreshResourceStore.readBatch(limit: 300, root: root);
        expect(batch, hasLength(2));
        expect(batch.toSet(), hasLength(2));
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('clear removes all shards, cursor and legacy inventory', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-clear-');
      try {
        await FreshResourceStore.merge(
          <String>[
            'vless://clear-one@example.test:443',
            'vless://clear-two@example.test:443',
          ],
          root: root,
        );
        await FreshResourceStore.clear(root: root);
        expect(await FreshResourceStore.count(root: root), 0);
        final folder = Directory(root.path + '/' + FreshResourceStore.directoryName);
        expect(await File(folder.path + '/.inventory_dirty').exists(), isFalse);
        expect(await FreshResourceStore.readBatch(limit: 10, root: root), isEmpty);
        final shards = await folder.list(followLinks: false)
            .where((entity) => entity is File &&
                RegExp(r'^[0-9a-f]{2}\.jsonl$').hasMatch(entity.uri.pathSegments.last))
            .toList();
        expect(shards, isEmpty);
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('migrates the legacy flat file and repairs interrupted count metadata', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-migrate-');
      try {
        final folder = Directory(root.path + '/' + FreshResourceStore.directoryName);
        await folder.create(recursive: true);
        await File(folder.path + '/configs.txt').writeAsString(
          'vless://one@example.test:443\nvmess://two@example.test:443\n',
          flush: true,
        );

        expect(await FreshResourceStore.count(root: root), 2);
        expect(await File(folder.path + '/configs.txt.migrated').exists(), isTrue);
        await File(folder.path + '/metadata.json')
            .writeAsString('{"schema":2,"count":1}');
        await File(folder.path + '/.inventory_dirty').writeAsString('1');
        expect(await FreshResourceStore.count(root: root), 2);
      } finally {
        await root.delete(recursive: true);
      }
    });
  });
}
