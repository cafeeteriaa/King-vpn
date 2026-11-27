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
