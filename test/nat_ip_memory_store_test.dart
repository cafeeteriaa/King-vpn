import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../lib/nat_ip_memory_store.dart';

void main() {
  late Directory directory;
  late JsonLinesInventoryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('king-nat-ip-store-');
    store = JsonLinesInventoryStore(File('${directory.path}/inventory.jsonl'));
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('missing inventory is an empty collection', () async {
    expect(await store.readAll(), isEmpty);
  });

  test('streams and retains the complete inventory without a fixed ceiling', () async {
    final records = List<Map<String, dynamic>>.generate(
      12000,
      (index) => <String, dynamic>{
        'ip': '2001:db8::${index.toRadixString(16)}',
        'port': 443 + (index % 1000),
        't': index,
      },
      growable: false,
    );

    await store.replaceAll(records);

    final restored = await store.readAll();
    expect(restored, hasLength(records.length));
    expect(restored.first, records.first);
    expect(restored.last, records.last);
  });

  test('replacement leaves only the newly committed complete snapshot', () async {
    await store.replaceAll([
      <String, dynamic>{'ip': '192.0.2.1', 'port': 443, 't': 1},
    ]);
    final next = [
      <String, dynamic>{'ip': '2001:db8::1', 'port': 8443, 't': 2},
      <String, dynamic>{'ip': '198.51.100.2', 'port': 2053, 't': 3},
    ];

    await store.replaceAll(next);

    expect(await store.readAll(), next);
    expect(await File('${store.file.path}.tmp').exists(), isFalse);
  });

  test('malformed records fail visibly instead of silently dropping data', () async {
    await store.file.parent.create(recursive: true);
    await store.file.writeAsString('{"ip":"192.0.2.1","port":443}\nnot-json\n');

    expect(store.readAll(), throwsFormatException);
  });
}
