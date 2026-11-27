import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../lib/personal_folder_store.dart';

void main() {
  group('PersonalFolderScanEpoch', () {
    test('a newer scan and explicit cancellation invalidate stale generations', () {
      final epoch = PersonalFolderScanEpoch();
      final first = epoch.begin();
      expect(epoch.isCurrent(first), isTrue);
      final second = epoch.begin();
      expect(epoch.isCurrent(first), isFalse);
      expect(epoch.isCurrent(second), isTrue);
      epoch.cancel();
      expect(epoch.isCurrent(second), isFalse);
    });
  });

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

    test('streams the complete archive in bounded batches without losing order', () async {
      final input = List<String>.generate(
        1003,
        (i) => 'vless://node$i@example.com:443',
      );
      await PersonalFolderStore.writeSnapshot(input);
      final batches = <List<String>>[];
      await for (final batch in PersonalFolderStore.streamBatches(batchSize: 73)) {
        expect(batch.length, lessThanOrEqualTo(73));
        batches.add(batch);
      }
      expect(batches.expand((batch) => batch).toList(), input);
      expect(await PersonalFolderStore.count(), input.length);
    });

    test('streamed append and removal preserve the archive and backup', () async {
      final first = List<String>.generate(
        1200,
        (i) => 'vless://base$i@example.com:443',
      );
      await PersonalFolderStore.writeSnapshot(first);
      final added = await PersonalFolderStore.appendAll(<String>[
        first.first,
        'trojan://new-one@example.com:443',
        'ss://new-two@example.com:443',
      ]);
      expect(added, 2);
      expect(await PersonalFolderStore.count(), 1202);
      expect(await PersonalFolderStore.removeLink(first[500]), isTrue);
      expect(await PersonalFolderStore.removeLink('vless://absent@example.com:443'), isFalse);
      expect(await PersonalFolderStore.count(), 1201);
      expect(await PersonalFolderStore.contains(first[500]), isFalse);
      expect(await PersonalFolderStore.contains(first[501]), isTrue);
      expect(await PersonalFolderStore.hasValidSnapshot(), isTrue);
    });

    test('streamed mutation recovers from corrupt primary without replacing backup', () async {
      const original = <String>[
        'vless://backup-a@example.com:443',
        'trojan://backup-b@example.com:443',
      ];
      await PersonalFolderStore.writeSnapshot(original);
      await PersonalFolderStore.writeSnapshot(<String>[
        'vless://newer-primary@example.com:443',
      ]);
      final primary = File('${tempDirectory.path}/servers.jsonl');
      await primary.writeAsString('corrupt-json-line\n');

      expect(
        await PersonalFolderStore.appendAll(<String>[
          'ss://added-after-recovery@example.com:443',
        ]),
        1,
      );
      expect(await PersonalFolderStore.count(), 3);
      expect(await PersonalFolderStore.contains(original.first), isTrue);
      expect(await PersonalFolderStore.contains(
        'ss://added-after-recovery@example.com:443',
      ), isTrue);
      expect(await PersonalFolderStore.hasValidSnapshot(), isTrue);
    });

    test('checks exact membership without materializing the archive', () async {
      final input = List<String>.generate(
        900,
        (i) => 'vless://member$i@example.com:443',
      );
      await PersonalFolderStore.writeSnapshot(input);
      expect(await PersonalFolderStore.contains(input.last), isTrue);
      expect(await PersonalFolderStore.contains('vless://missing@example.com:443'), isFalse);
      expect(await PersonalFolderStore.contains('vless://member9@example.com:443-extra'), isFalse);
    });

    test('cancels exact membership scanning during the integrity preflight', () async {
      final input = List<String>.generate(
        900,
        (i) => 'vless://cancel-member$i@example.com:443',
      );
      await PersonalFolderStore.writeSnapshot(input);
      var checks = 0;
      final found = await PersonalFolderStore.contains(
        input.last,
        shouldAbort: () => ++checks > 8,
      );
      expect(found, isFalse);
      expect(checks, greaterThan(8));
    });

    test('streams a large archive with a strict batch working set', () async {
      final input = List<String>.generate(
        6000,
        (i) => 'vless://stream-node$i@example.com:443',
      );
      await PersonalFolderStore.writeSnapshot(input);
      var observed = 0;
      var largestBatch = 0;
      await for (final batch in PersonalFolderStore.streamBatches(batchSize: 37)) {
        observed += batch.length;
        if (batch.length > largestBatch) largestBatch = batch.length;
      }
      expect(observed, input.length);
      expect(largestBatch, lessThanOrEqualTo(37));
    });

    test('streams filtered archive matches and honors cancellation', () async {
      final input = <String>[
        ...List<String>.generate(200, (i) => 'vless://node$i@example.com:443'),
        'trojan://wanted-edge@example.net:443',
      ];
      await PersonalFolderStore.writeSnapshot(input);
      final found = <String>[];
      await for (final batch in PersonalFolderStore.streamBatches(
        batchSize: 7,
        query: 'WANTED-EDGE',
      )) {
        found.addAll(batch);
      }
      expect(found, <String>['trojan://wanted-edge@example.net:443']);

      var cancel = false;
      final cancelled = <String>[];
      await for (final batch in PersonalFolderStore.streamBatches(
        batchSize: 5,
        shouldAbort: () => cancel,
      )) {
        cancelled.addAll(batch);
        cancel = true;
      }
      expect(cancelled, hasLength(5));
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
