import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/main.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('king-inventory-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('appends unique identities and streams records', () async {
    final inventory = await KingDiskInventory.open(name: 'append', root: root);
    final added = await inventory.appendBatch([
      <String, Object?>{'key': 'endpoint-a', 'ip': '192.0.2.1', 'port': 443},
      <String, Object?>{'key': 'endpoint-b', 'ip': '192.0.2.2', 'port': 443},
      <String, Object?>{'key': 'endpoint-a', 'ip': '192.0.2.1', 'port': 443},
    ]);
    expect(added, 2);
    expect(await inventory.records().length, 2);
  });

  test('upserts one identity without losing other shard records', () async {
    final inventory = await KingDiskInventory.open(name: 'upsert', root: root);
    await inventory.upsertBatch([
      <String, Object?>{'key': 'endpoint-a', 'value': 'old'},
      <String, Object?>{'key': 'endpoint-b', 'value': 'keep'},
    ]);
    await inventory.upsertBatch([
      <String, Object?>{'key': 'endpoint-a', 'value': 'new'},
    ]);
    final records = await inventory.records().toList();
    expect(records, hasLength(2));
    expect(records.where((r) => r['value'] == 'old'), isEmpty);
    expect(records.where((r) => r['value'] == 'new'), hasLength(1));
    expect(records.where((r) => r['value'] == 'keep'), hasLength(1));
  });

  test('reopens after torn tail and retains later valid records', () async {
    final inventory = await KingDiskInventory.open(name: 'recover', root: root);
    await inventory.appendBatch([
      <String, Object?>{'key': 'first', 'value': 1},
    ]);
    final directory = Directory('${root.path}/king_inventory_recover');
    final shard = (await directory.list().where((e) => e is File).first) as File;
    await shard.writeAsString('{"version":1,"id":', mode: FileMode.append);
    final reopened = await KingDiskInventory.open(name: 'recover', root: root);
    expect(await reopened.records().length, 1);
    await reopened.appendBatch([
      <String, Object?>{'key': 'second', 'value': 2},
    ]);
    expect(await reopened.records().length, 2);
  });

  test('serializes concurrent writers opened as separate handles', () async {
    final first = await KingDiskInventory.open(name: 'concurrent', root: root);
    final second = await KingDiskInventory.open(name: 'concurrent', root: root);
    await Future.wait([
      first.appendBatch([<String, Object?>{'key': 'a', 'value': 1}]),
      second.appendBatch([<String, Object?>{'key': 'b', 'value': 2}]),
    ]);
    final reopened = await KingDiskInventory.open(name: 'concurrent', root: root);
    expect(await reopened.records().length, 2);
  });

  test('rejects missing and oversized record identities', () async {
    final inventory = await KingDiskInventory.open(name: 'validate', root: root);
    await expectLater(
      inventory.appendBatch([<String, Object?>{'ip': '192.0.2.1'}]),
      throwsArgumentError,
    );
    await expectLater(
      inventory.appendBatch([
        <String, Object?>{'key': List<String>.filled(4097, 'x').join()},
      ]),
      throwsArgumentError,
    );
  });
}
