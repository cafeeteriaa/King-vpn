import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../lib/fresh_resource_store.dart';

const int fourMillionSoakEntries = 4000000;

void main() {
  group('FreshResourceStore unbounded inventory and normalization', () {
    test('enforces the four-million offline archive capacity', () {
      expect(FreshResourceStore.maxEntries, fourMillionSoakEntries);
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
        ]),
        hasLength(4),
      );
    });


    test('48-hour refresh quality gate preserves a large inventory on partial source responses', () {
      expect(FreshResourceStore.minimumSnapshotReplacementCount(4000000), 3000000);
      expect(FreshResourceStore.minimumSnapshotReplacementCount(20), 20);
      expect(FreshResourceStore.minimumSnapshotReplacementCount(0), 1);
      expect(
        FreshResourceStore.isSufficientSnapshotReplacement(
          previousCount: 4000000,
          incomingCount: 2999999,
          successfulSources: 2,
          configuredSources: 3,
        ),
        isFalse,
      );
      expect(
        FreshResourceStore.isSufficientSnapshotReplacement(
          previousCount: 4000000,
          incomingCount: 3000000,
          successfulSources: 2,
          configuredSources: 3,
        ),
        isTrue,
      );
      expect(
        FreshResourceStore.isSufficientSnapshotReplacement(
          previousCount: 20,
          incomingCount: 19,
          successfulSources: 1,
          configuredSources: 1,
        ),
        isFalse,
      );
      expect(
        FreshResourceStore.isSufficientSnapshotReplacement(
          previousCount: 20,
          incomingCount: 20,
          successfulSources: 1,
          configuredSources: 1,
        ),
        isTrue,
      );
      expect(
        FreshResourceStore.isSufficientSnapshotReplacement(
          previousCount: 0,
          incomingCount: 1,
          successfulSources: 1,
          configuredSources: 1,
        ),
        isTrue,
      );
      expect(
        FreshResourceStore.isSufficientSnapshotReplacement(
          previousCount: 1000,
          incomingCount: 1000,
          successfulSources: 1,
          configuredSources: 2,
        ),
        isFalse,
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

    test('does not count protocols without an active native engine as usable offline configs', () {
      expect(FreshResourceStore.normalizeLink('hysteria2://secret@example.com:443'), isNull);
      expect(FreshResourceStore.normalizeLink('hy2://secret@example.com:443'), isNull);
      expect(FreshResourceStore.normalizeLink('tuic://id:password@example.com:443'), isNull);
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

    test('normalizes URI scheme case and rejects oversized links', () {
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
          for (var i = 0; i < fourMillionSoakEntries; i++) {
            final suffix = i.toRadixString(16).padLeft(12, '0');
            yield 'vless://00000000-0000-4000-8000-$suffix@n$i.example:443?encryption=none&security=tls&type=tcp';
          }
        }

        final total = await FreshResourceStore.merge(
          profiles(),
          source: 'four-million-soak',
          root: root,
        );
        expect(total, fourMillionSoakEntries);
        expect(await FreshResourceStore.count(root: root), fourMillionSoakEntries);
        expect(await FreshResourceStore.verifyCount(root: root), fourMillionSoakEntries);
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


    test('persistent cursor exhausts shards without replay and resumes after append', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-cursor-eof-');
      try {
        final initial = <String>[
          for (var i = 0; i < 80; i++) 'vless://cursor-$i@example.test:443',
        ];
        expect(await FreshResourceStore.merge(initial, root: root), 80);

        final firstPass = await FreshResourceStore.readBatch(limit: 300, root: root);
        expect(firstPass, hasLength(80));
        expect(firstPass.toSet(), hasLength(80));

        // All shards are exhausted. The next batch must not rewind to byte zero.
        expect(await FreshResourceStore.readBatch(limit: 300, root: root), isEmpty);

        const appended = <String>[
          'vless://cursor-appended-1@example.test:443',
          'vless://cursor-appended-2@example.test:443',
        ];
        expect(await FreshResourceStore.merge(appended, root: root), 82);
        final afterAppend = await FreshResourceStore.readBatch(limit: 300, root: root);
        expect(afterAppend.toSet(), appended.toSet());
        expect(await FreshResourceStore.readBatch(limit: 300, root: root), isEmpty);
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('does not append beyond the four-million archive capacity', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-capacity-');
      try {
        const existing = 'vless://already-stored@example.test:443';
        await FreshResourceStore.merge(<String>[existing], root: root);
        final folder = Directory(root.path + '/' + FreshResourceStore.directoryName);
        await File(folder.path + '/metadata.json').writeAsString(
          '{"schema":2,"count":4000000}', flush: true,
        );
        final total = await FreshResourceStore.merge(
          <String>[
            existing,
            'vless://must-not-be-added@example.test:443',
          ],
          root: root,
        );
        expect(total, FreshResourceStore.maxEntries);
        final stored = await FreshResourceStore.streamLinks(root: root).toList();
        expect(stored, <String>[existing]);
      } finally {
        await root.delete(recursive: true);
      }
    });



    test('recovers from a malformed or negative persistent cursor without losing profiles', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-cursor-corrupt-');
      try {
        const links = <String>[
          'vless://cursor-safe-one@example.test:443',
          'vless://cursor-safe-two@example.test:443',
          'vless://cursor-safe-three@example.test:443',
        ];
        await FreshResourceStore.merge(links, root: root);
        final folder = Directory('${root.path}/${FreshResourceStore.directoryName}');
        await File('${folder.path}/offline_cursor.json').writeAsString(
          '{"schema":1,"shardIndex":-1,"offsets":{"-1":999999,"zz":12,"00":-5}}',
          flush: true,
        );

        final recovered = await FreshResourceStore.readBatch(limit: 300, root: root);
        expect(recovered.toSet(), links.toSet());
        expect(recovered, hasLength(3));
        final cursor = jsonDecode(
          await File('${folder.path}/offline_cursor.json').readAsString(),
        ) as Map<String, Object?>;
        expect(cursor['shardIndex'], inInclusiveRange(0, 255));
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

    test('staged refresh replaces the old inventory only after validation', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-replace-');
      try {
        await FreshResourceStore.merge(
          <String>['vless://old@example.test:443'], root: root);
        final total = await FreshResourceStore.replaceSnapshot(
          <String>['vless://new@example.test:443', 'vmess://new-two'],
          source: 'test-48h-refresh', root: root);
        expect(total, 2);
        final links = await FreshResourceStore.streamLinks(root: root).toList();
        expect(links, contains('vless://new@example.test:443'));
        expect(links, contains('vmess://new-two'));
        expect(links, isNot(contains('vless://old@example.test:443')));
      } finally {
        await root.delete(recursive: true);
        final stage = Directory('${root.path}/.kingvpn-resource-stage');
        if (await stage.exists()) await stage.delete(recursive: true);
      }
    });

    test('staged refresh creates the parent path for a first-time inventory', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-replace-first-');
      try {
        final total = await FreshResourceStore.replaceSnapshot(
          <String>['vless://first@example.test:443'],
          source: 'online-public-sources-48h-refresh', root: root);
        expect(total, 1);
        expect(await FreshResourceStore.count(root: root), 1);
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('manual imports do not reset the successful online snapshot clock', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-refresh-clock-');
      try {
        await FreshResourceStore.replaceSnapshot(
          <String>['vless://online@example.test:443'],
          source: 'online-public-sources-48h-refresh', root: root);
        final before = (await FreshResourceStore.metadata(root: root))['onlineSnapshotRefreshedAt'];
        await FreshResourceStore.merge(
          <String>['vless://manual@example.test:443'],
          source: 'manual-import', root: root);
        final after = (await FreshResourceStore.metadata(root: root))['onlineSnapshotRefreshedAt'];
        expect(before, isNotNull);
        expect(after, before);
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('interrupted directory swap recovers backup before a failed refresh', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-replace-recover-');
      try {
        const oldLink = 'vless://recovered@example.test:443';
        await FreshResourceStore.merge(<String>[oldLink], root: root);
        final target = Directory('${root.path}/${FreshResourceStore.directoryName}');
        await target.rename('${target.path}.backup');
        await expectLater(
          FreshResourceStore.replaceSnapshot(<String>['invalid'], root: root),
          throwsA(isA<StateError>()),
        );
        expect(await FreshResourceStore.streamLinks(root: root).toList(), <String>[oldLink]);
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('failed or empty staged refresh preserves the previous inventory', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-replace-fail-');
      try {
        const oldLink = 'vless://keep-me@example.test:443';
        await FreshResourceStore.merge(<String>[oldLink], root: root);
        await expectLater(
          FreshResourceStore.replaceSnapshot(<String>['not-a-config'], root: root),
          throwsA(isA<StateError>()),
        );
        expect(await FreshResourceStore.streamLinks(root: root).toList(), <String>[oldLink]);
      } finally {
        await root.delete(recursive: true);
        final stage = Directory('${root.path}/.kingvpn-resource-stage');
        if (await stage.exists()) await stage.delete(recursive: true);
      }
    });

    test('undersized staged replacement never deletes the previous inventory', () async {
      final root = await Directory.systemTemp.createTemp('king-offline-replace-small-');
      try {
        const oldLinks = <String>[
          'vless://old-one@example.test:443',
          'vless://old-two@example.test:443',
        ];
        await FreshResourceStore.merge(oldLinks, root: root);
        await expectLater(
          FreshResourceStore.replaceSnapshot(
            <String>['vless://only-one@example.test:443'],
            minimumEntries: 2,
            root: root,
          ),
          throwsA(isA<StateError>()),
        );
        expect(
          (await FreshResourceStore.streamLinks(root: root).toList()).toSet(),
          oldLinks.toSet(),
        );
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
