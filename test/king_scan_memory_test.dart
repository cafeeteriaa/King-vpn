import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/main.dart';

void main() {
  group('KING durable scanner journal', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('king-scan-journal-');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('persists and restores the latest completed phase and cursor', () async {
      final first = await KingScanJournal.open(jobId: 'national-test', root: root);
      await first.commit(
        phase: 'ip',
        phaseCompleted: false,
        cursor: <String, Object?>{'rangeIndex': 7, 'rangeOffsets': <String, int>{'10.0.0.0/24': 128}},
        counters: <String, int>{'batches': 4, 'discovered': 12},
      );
      await first.commit(
        phase: 'ip',
        phaseCompleted: true,
        cursor: <String, Object?>{
          'rangeIndex': 8,
          'rangeOffsets': <String, int>{'10.0.0.0/24': 128},
        },
        counters: <String, int>{'batches': 5, 'discovered': 14},
      );

      final reopened = await KingScanJournal.open(jobId: 'national-test', root: root);
      expect(reopened.sequence, 2);
      expect(reopened.latestCheckpoint?['phase'], 'ip');
      expect(reopened.latestCheckpoint?['phaseCompleted'], isTrue);
      expect((reopened.latestCheckpoint?['cursor'] as Map)['rangeIndex'], 8);
      final offsets = (reopened.latestCheckpoint?['cursor'] as Map)['rangeOffsets'] as Map;
      expect(offsets.keys.single, hasLength(64));
      expect(offsets.keys.single, isNot('10.0.0.0/24'));
    });

    test('serializes concurrent checkpoint commits in sequence order', () async {
      final journal = await KingScanJournal.open(jobId: 'concurrent', root: root);
      await Future.wait([
        for (var i = 0; i < 40; i++)
          journal.commit(
            phase: 'ip',
            phaseCompleted: false,
            cursor: <String, Object?>{'batch': i},
          ),
      ]);
      expect(journal.sequence, 40);
      final sequences = await journal.records()
          .map((record) => record['sequence'] as int)
          .toList();
      expect(sequences, List<int>.generate(40, (i) => i + 1));
    });

    test('ignores a torn final record and appends a clean next record', () async {
      final journal = await KingScanJournal.open(jobId: 'torn-tail', root: root);
      await journal.commit(phase: 'dns', phaseCompleted: true);
      final file = Directory(root.path)
          .listSync()
          .whereType<File>()
          .single;
      await file.writeAsString('{"version":1,"job":', mode: FileMode.append);

      final recovered = await KingScanJournal.open(jobId: 'torn-tail', root: root);
      expect(recovered.sequence, 1);
      await recovered.commit(phase: 'domain', phaseCompleted: true);
      final reopened = await KingScanJournal.open(jobId: 'torn-tail', root: root);
      expect(reopened.sequence, 2);
      expect(reopened.latestCheckpoint?['phase'], 'domain');
    });

    test('rejects unrecognized cursor fields and negative offsets', () async {
      final journal = await KingScanJournal.open(jobId: 'cursor-validation', root: root);
      await expectLater(
        journal.commit(
          phase: 'ip',
          phaseCompleted: false,
          cursor: <String, Object?>{'rawEndpoint': '192.0.2.1'},
        ),
        throwsArgumentError,
      );
      await expectLater(
        journal.commit(
          phase: 'ip',
          phaseCompleted: false,
          cursor: <String, Object?>{
            'rangeOffsets': <String, int>{'10.0.0.0/24': -1},
          },
        ),
        throwsArgumentError,
      );
      expect(journal.sequence, 0);
    });

    test('preserves empty candidate and variant sentinel cursors', () async {
      final journal = await KingScanJournal.open(jobId: 'empty-sentinel', root: root);
      await journal.commit(
        phase: 'sni',
        phaseCompleted: false,
        cursor: <String, Object?>{'candidateIndex': -1, 'variantIndex': -1},
      );
      expect(journal.latestCheckpoint?['cursor'], containsPair('candidateIndex', -1));
      expect(journal.latestCheckpoint?['cursor'], containsPair('variantIndex', -1));
    });

    test('accepts only opaque hashed target identity for resumable phases', () async {
      final journal = await KingScanJournal.open(jobId: 'opaque-resume', root: root);
      await journal.commit(
        phase: 'sni',
        phaseCompleted: false,
        cursor: <String, Object?>{
          'serverIndex': 2,
          'serverKeyHash': List<String>.filled(64, 'a').join(),
          'candidateIndex': 9,
        },
      );
      expect(journal.latestCheckpoint?['cursor'], containsPair(
        'serverKeyHash', List<String>.filled(64, 'a').join(),
      ));
      await expectLater(
        journal.commit(
          phase: 'config',
          phaseCompleted: false,
          cursor: <String, Object?>{'serverKeyHash': 'example.com'},
        ),
        throwsArgumentError,
      );
    });

    test('does not store raw endpoints or credentials', () async {
      final journal = await KingScanJournal.open(jobId: 'privacy', root: root);
      await journal.commit(
        phase: 'sni',
        phaseCompleted: true,
        cursor: <String, Object?>{
          'targetIndex': 3,
          'candidateIndex': 2,
          'rangeOffsets': <String, int>{
            '192.0.2.1/32': 4,
            'vless://user:password@example.invalid:443': 8,
          },
        },
        counters: <String, int>{'handshakes': 1},
      );
      final content = await Directory(root.path)
          .listSync()
          .whereType<File>()
          .single
          .readAsString();
      expect(content, isNot(contains('vless://')));
      expect(content, isNot(contains('password')));
      expect(content, isNot(contains('192.0.2.1')));
      expect(content, isNot(contains('192.0.2.1/32')));
      expect(content, isNot(contains('example.invalid')));
      expect(content, isNot(contains('user:password')));
    });
  });
}
