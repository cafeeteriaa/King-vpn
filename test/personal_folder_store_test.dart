import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../lib/personal_folder_store.dart';

void main() {
  group('PersonalFolderStore snapshot codec', () {
    test('round-trips Unicode and embedded line breaks without record loss', () {
      final input = <String>[
        'vless://one@example.com:443?remarks=سلام',
        'vmess://two@example.com:443?remarks=line\nbreak',
        'trojan://three@example.com:443',
      ];
      final encoded = PersonalFolderStore.encodeSnapshot(input);
      expect(PersonalFolderStore.decodeSnapshot(encoded), input);
    });

    test('deduplicates case-insensitively while preserving first occurrence', () {
      final encoded = PersonalFolderStore.encodeSnapshot(<String>[
        'vless://A@example.com:443',
        'VLESS://a@example.com:443',
        'trojan://b@example.com:443',
      ]);
      expect(PersonalFolderStore.decodeSnapshot(encoded), <String>[
        'vless://A@example.com:443',
        'trojan://b@example.com:443',
      ]);
    });

    test('distinguishes a valid empty snapshot from corrupt content', () {
      expect(PersonalFolderStore.decodeSnapshot(''), isEmpty);
      expect(PersonalFolderStore.decodeSnapshot('not-json\n'), isNull);
      expect(PersonalFolderStore.decodeSnapshot('42\n'), isNull);
    });

    test('retains inventories beyond former fixed folder limits', () {
      final input = List<String>.generate(
        6000,
        (i) => 'vless://node$i@example.com:443',
      );
      final decoded = PersonalFolderStore.decodeSnapshot(
        PersonalFolderStore.encodeSnapshot(input),
      );
      expect(decoded, hasLength(6000));
      expect(decoded, input);
    });
  });

  group('PersonalFolderStore file recovery', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('king-personal-store-');
      PersonalFolderStore.directoryProviderForTesting = () async => tempDirectory;
    });

    tearDown(() async {
      PersonalFolderStore.directoryProviderForTesting = null;
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('keeps the last valid snapshot when the primary becomes corrupt', () async {
      const first = <String>['vless://a@example.com:443'];
      const second = <String>[
        'vless://a@example.com:443',
        'trojan://b@example.com:443',
      ];
      await PersonalFolderStore.writeSnapshot(first);
      await PersonalFolderStore.writeSnapshot(second);

      final primary = File('${tempDirectory.path}/servers.jsonl');
      await primary.writeAsString('corrupt-record\n');

      expect(await PersonalFolderStore.readSnapshot(), first);

      await PersonalFolderStore.writeSnapshot(<String>[
        ...first,
        'ss://c@example.com:443',
      ]);
      expect(
        await PersonalFolderStore.readSnapshot(),
        <String>[...first, 'ss://c@example.com:443'],
      );
      final backup = File('${tempDirectory.path}/servers.jsonl.bak');
      expect(await PersonalFolderStore.decodeSnapshot(await backup.readAsString()), first);
    });

    test('streams snapshot encoding, deduplication and Unicode records to disk', () async {
      final input = <String>[
        ...List<String>.generate(
          6000,
          (i) => 'vless://node$i@example.com:443?remark=گره-$i',
        ),
        '  VLESS://NODE1@example.com:443?remark=duplicate  ',
        'vmess://unicode@example.com:443?remark=سلام\nجهان',
      ];
      await PersonalFolderStore.writeSnapshot(input);

      final page = await PersonalFolderStore.readPage(limit: 6005);
      expect(page.totalCount, 6001);
      expect(page.items.first, 'vless://node0@example.com:443?remark=گره-0');
      expect(page.items.last, 'vmess://unicode@example.com:443?remark=سلام\nجهان');

      var streamed = 0;
      await for (final batch in PersonalFolderStore.readBatches(batchSize: 97)) {
        streamed += batch.length;
      }
      expect(streamed, 6001);
    });

    test('failed staged write leaves the committed primary readable', () async {
      const stable = <String>['vless://stable@example.com:443'];
      await PersonalFolderStore.writeSnapshot(stable);
      PersonalFolderStore.directoryProviderForTesting = () async {
        throw StateError('injected directory failure');
      };
      await expectLater(
        PersonalFolderStore.writeSnapshot(<String>['vless://new@example.com:443']),
        throwsStateError,
      );
      PersonalFolderStore.directoryProviderForTesting = () async => tempDirectory;
      expect(await PersonalFolderStore.readSnapshot(), stable);
    });

    test('serializes overlapping writes and preserves the final requested snapshot', () async {
      final first = <String>['vless://first@example.com:443'];
      final second = <String>['vless://second@example.com:443'];
      final third = <String>['vless://third@example.com:443'];
      await Future.wait([
        PersonalFolderStore.writeSnapshot(first),
        PersonalFolderStore.writeSnapshot(second),
        PersonalFolderStore.writeSnapshot(third),
      ]);
      expect(await PersonalFolderStore.readSnapshot(), third);
      final backup = File('${tempDirectory.path}/servers.jsonl.bak');
      expect(await PersonalFolderStore.decodeSnapshot(await backup.readAsString()), second);
    });

    test('reads successive pages without truncating the full inventory', () async {
      final input = List<String>.generate(
        137,
        (i) => 'vless://node$i@example.com:443',
      );
      await PersonalFolderStore.writeSnapshot(input);

      final first = await PersonalFolderStore.readPage(limit: 50);
      final second = await PersonalFolderStore.readPage(offset: 50, limit: 50);
      final third = await PersonalFolderStore.readPage(offset: 100, limit: 50);

      expect(first.items, input.sublist(0, 50));
      expect(second.items, input.sublist(50, 100));
      expect(third.items, input.sublist(100));
      expect(first.totalCount, 137);
      expect(second.totalCount, 137);
      expect(third.totalCount, 137);
      expect(first.hasNext, isTrue);
      expect(second.hasPrevious, isTrue);
      expect(third.hasNext, isFalse);
    });

    test('searches the complete inventory while returning only one page', () async {
      final input = <String>[
        ...List<String>.generate(120, (i) => 'vless://node$i@example.com:443'),
        'trojan://Special-Edge.example.net:443',
      ];
      await PersonalFolderStore.writeSnapshot(input);

      final result = await PersonalFolderStore.readPage(
        offset: 0,
        limit: 10,
        query: 'SPECIAL-EDGE',
      );
      expect(result.totalCount, 1);
      expect(result.items, <String>['trojan://Special-Edge.example.net:443']);
    });

    test('paged reads recover from a corrupt primary using the backup', () async {
      const first = <String>[
        'vless://backup-one@example.com:443',
        'trojan://backup-two@example.com:443',
      ];
      await PersonalFolderStore.writeSnapshot(first);
      await PersonalFolderStore.writeSnapshot(<String>[
        'vless://new-primary@example.com:443',
      ]);
      final primary = File('${tempDirectory.path}/servers.jsonl');
      await primary.writeAsString('corrupt-line\n');

      final result = await PersonalFolderStore.readPage(limit: 1);
      expect(result.items, <String>[first.first]);
      expect(result.totalCount, 2);
    });


    test('streams large inventories in bounded batches', () async {
      final input = List<String>.generate(
        6000,
        (i) => 'vless://stream$i@example.com:443',
      );
      await PersonalFolderStore.writeSnapshot(input);
      var count = 0;
      var largestBatch = 0;
      await for (final batch in PersonalFolderStore.readBatches(batchSize: 73)) {
        count += batch.length;
        if (batch.length > largestBatch) largestBatch = batch.length;
      }
      expect(count, 6000);
      expect(largestBatch, 73);
    });

    test('appends only new profiles without losing the archive', () async {
      final original = List<String>.generate(
        2400,
        (i) => 'vless://existing$i@example.com:443',
      );
      await PersonalFolderStore.writeSnapshot(original);
      final added = await PersonalFolderStore.appendLinks(<String>[
        original[10],
        'trojan://new-one@example.com:443',
        'trojan://new-two@example.com:443',
        'TROJAN://NEW-ONE@example.com:443',
      ]);
      expect(added, <String>[
        'trojan://new-one@example.com:443',
        'trojan://new-two@example.com:443',
      ]);
      final page = await PersonalFolderStore.readPage(offset: 2399, limit: 5);
      expect(page.totalCount, 2402);
      expect(page.items, <String>[
        original.last,
        'trojan://new-one@example.com:443',
        'trojan://new-two@example.com:443',
      ]);
    });

    test('removes profiles transactionally and keeps the previous valid backup', () async {
      final original = List<String>.generate(
        300,
        (i) => 'vless://remove$i@example.com:443',
      );
      await PersonalFolderStore.writeSnapshot(original);
      await PersonalFolderStore.writeSnapshot(<String>[
        ...original,
        'trojan://keep@example.com:443',
      ]);
      final removed = await PersonalFolderStore.removeLinks(<String>[
        original[1],
        original[20],
        'vless://absent@example.com:443',
      ]);
      expect(removed, 2);
      final result = await PersonalFolderStore.readPage(limit: 500);
      expect(result.totalCount, 299);
      expect(result.items, isNot(contains(original[1])));
      expect(result.items, isNot(contains(original[20])));
      expect(result.items, contains('trojan://keep@example.com:443'));
      final backup = File('${tempDirectory.path}/servers.jsonl.bak');
      expect(await backup.exists(), isTrue);
      expect(
        PersonalFolderStore.decodeSnapshot(await backup.readAsString()),
        hasLength(301),
      );
    });

    test('membership lookup and batch reads recover from corrupt primary', () async {
      const backup = <String>[
        'vless://recover-one@example.com:443',
        'trojan://recover-two@example.com:443',
      ];
      await PersonalFolderStore.writeSnapshot(backup);
      await PersonalFolderStore.writeSnapshot(<String>[
        'vless://new-primary@example.com:443',
      ]);
      await File('${tempDirectory.path}/servers.jsonl')
          .writeAsString('broken-line\n');
      expect(
        await PersonalFolderStore.containsLink(backup.last),
        isTrue,
      );
      expect(
        await PersonalFolderStore.containsLink('vless://missing@example.com:443'),
        isFalse,
      );
      final recovered = await PersonalFolderStore.readBatches(batchSize: 1)
          .expand((batch) => batch)
          .toList();
      expect(recovered, backup);
    });

    test('migrates legacy profiles once and then prefers the file snapshot', () async {
      final migrated = await PersonalFolderStore.readOrMigrate(
        () async => <String>['vless://legacy@example.com:443'],
      );
      expect(migrated, <String>['vless://legacy@example.com:443']);

      final next = await PersonalFolderStore.readOrMigrate(
        () async => <String>['vless://stale-legacy@example.com:443'],
      );
      expect(next, migrated);
    });
  });

}
