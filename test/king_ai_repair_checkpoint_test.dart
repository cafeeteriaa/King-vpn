import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/king_ai_repair_checkpoint.dart';

void main() {
  late Directory directory;
  late KingAiRepairCheckpointStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('king-ai-checkpoint-');
    store = KingAiRepairCheckpointStore(directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('persists and restores completed batches and pending patches', () async {
    final sources = {'lib/a.dart': 'final value = 1;'};
    final id = KingAiRepairCheckpointStore.deterministicId('change value', sources);
    await store.save(
      id: id, task: 'change value', sourceFiles: sources,
      completedBatches: 2,
      changes: {'lib/b.dart': 'class B {}'},
      pendingOperations: {'lib/a.dart': <Object?>[{'find': '1', 'replace': '2'}]},
      summaries: ['first', 'second'],
    );
    final restored = await store.load(
      id: id, task: 'change value', sourceFiles: sources,
    );
    expect(restored?['completedBatches'], 2);
    expect((restored?['changes'] as Map)['lib/b.dart'], 'class B {}');
    expect(await store.listIds(), [id]);
  });

  test('rejects resume when task or source snapshot changed', () async {
    final sources = {'lib/a.dart': 'final value = 1;'};
    final id = KingAiRepairCheckpointStore.deterministicId('change value', sources);
    await store.save(
      id: id, task: 'change value', sourceFiles: sources,
      completedBatches: 1, changes: const {}, pendingOperations: const {},
      summaries: const [],
    );
    await expectLater(
      store.load(
        id: id, task: 'change value',
        sourceFiles: {'lib/a.dart': 'final value = 2;'},
      ),
      throwsFormatException,
    );
  });
}
