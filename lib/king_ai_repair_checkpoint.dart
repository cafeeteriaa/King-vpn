import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Durable owner-repair progress in the app-private support directory.
class KingAiRepairCheckpointStore {
  KingAiRepairCheckpointStore(this.directory);

  final Directory directory;
  static const int schemaVersion = 1;

  static String deterministicId(String task, Map<String, String> sourceFiles) {
    final taskHash = sha256.convert(utf8.encode(task.trim())).toString();
    final snapshotHash = sourceSnapshotHash(sourceFiles);
    return sha256.convert(utf8.encode('$taskHash:$snapshotHash'))
        .toString().substring(0, 32);
  }

  static String sourceSnapshotHash(Map<String, String> sourceFiles) {
    final entries = sourceFiles.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final canonical = entries.map((entry) => [
      entry.key, sha256.convert(utf8.encode(entry.value)).toString(),
    ]).toList();
    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }

  Future<File> _file(String id) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Invalid checkpoint identifier');
    }
    await directory.create(recursive: true);
    return File(directory.path + Platform.pathSeparator + id + '.json');
  }

  Future<void> save({
    required String id,
    required String task,
    required Map<String, String> sourceFiles,
    required int completedBatches,
    required Map<String, String> changes,
    required Map<String, List<Object?>> pendingOperations,
    required List<String> summaries,
  }) async {
    if (completedBatches < 0) {
      throw ArgumentError.value(completedBatches, 'completedBatches');
    }
    final payload = <String, Object?>{
      'schemaVersion': schemaVersion,
      'id': id,
      'taskHash': sha256.convert(utf8.encode(task.trim())).toString(),
      'sourceSnapshotHash': sourceSnapshotHash(sourceFiles),
      'completedBatches': completedBatches,
      'changes': changes,
      'pendingOperations': pendingOperations,
      'summaries': summaries,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    final payloadJson = jsonEncode(payload);
    final envelope = jsonEncode({
      'payload': payload,
      'checksum': sha256.convert(utf8.encode(payloadJson)).toString(),
    });
    final target = await _file(id);
    final temporary = File(target.path + '.tmp');
    final handle = await temporary.open(mode: FileMode.write);
    try {
      await handle.writeString(envelope);
      await handle.flush();
    } finally {
      await handle.close();
    }
    await temporary.rename(target.path);
  }

  Future<Map<String, Object?>?> load({
    required String id,
    required String task,
    required Map<String, String> sourceFiles,
  }) async {
    final file = await _file(id);
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map || decoded['payload'] is! Map ||
        decoded['checksum'] is! String) {
      throw const FormatException('Repair checkpoint envelope is malformed.');
    }
    final payload = Map<String, Object?>.from(decoded['payload'] as Map);
    final checksum = sha256.convert(utf8.encode(jsonEncode(payload))).toString();
    if (checksum != decoded['checksum']) {
      throw const FormatException('Repair checkpoint checksum mismatch.');
    }
    final expectedTaskHash =
        sha256.convert(utf8.encode(task.trim())).toString();
    final expectedSnapshotHash = sourceSnapshotHash(sourceFiles);
    if (payload['schemaVersion'] != schemaVersion || payload['id'] != id ||
        payload['taskHash'] != expectedTaskHash ||
        payload['sourceSnapshotHash'] != expectedSnapshotHash) {
      throw const FormatException(
        'Repair checkpoint is stale: task or source snapshot changed.',
      );
    }
    if (payload['completedBatches'] is! int || payload['changes'] is! Map ||
        payload['pendingOperations'] is! Map || payload['summaries'] is! List) {
      throw const FormatException('Repair checkpoint payload is malformed.');
    }
    return payload;
  }

  Future<List<String>> listIds() async {
    if (!await directory.exists()) return const [];
    final ids = <String>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.json')) {
        final name = entity.uri.pathSegments.last;
        final id = name.substring(0, name.length - 5);
        if (RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) ids.add(id);
      }
    }
    ids.sort();
    return ids;
  }

  Future<void> delete(String id) async {
    final file = await _file(id);
    if (await file.exists()) await file.delete();
    final temporary = File(file.path + '.tmp');
    if (await temporary.exists()) await temporary.delete();
  }
}
