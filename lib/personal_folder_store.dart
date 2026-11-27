import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Durable app-private storage for personal VPN profiles.
/// Consumers still materialize the current folder in memory; this class does
/// not claim to implement paging.
class PersonalFolderStore {
  PersonalFolderStore._();

  static const String directoryName = 'KingVPN/Personal';
  static const String fileName = 'servers.jsonl';
  static const String backupName = 'servers.jsonl.bak';
  static const String tempName = 'servers.jsonl.tmp';

  static Future<Directory> directory() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/$directoryName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _file(String name) async =>
      File('${(await directory()).path}/$name');

  static List<String> _normalize(Iterable<String> links) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in links) {
      final link = raw.trim();
      if (link.isEmpty) continue;
      if (seen.add(link.toLowerCase())) result.add(link);
    }
    return result;
  }

  /// Encode one profile per JSON line without losing Unicode/newline content.
  static String encodeSnapshot(Iterable<String> links) {
    final values = _normalize(links);
    return values.map(jsonEncode).join('\n') +
        (values.isEmpty ? '' : '\n');
  }

  /// null signals corruption; an empty valid snapshot decodes to [].
  static List<String>? decodeSnapshot(String contents) {
    try {
      final values = <String>[];
      for (final line in const LineSplitter().convert(contents)) {
        if (line.isEmpty) continue;
        final decoded = jsonDecode(line);
        if (decoded is! String) return null;
        values.add(decoded);
      }
      return _normalize(values);
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>?> _readFile(File file) async {
    if (!await file.exists()) return null;
    try {
      return decodeSnapshot(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// null means no valid snapshot; [] is a valid empty folder.
  static Future<List<String>?> readSnapshot() async {
    final primary = await _readFile(await _file(fileName));
    if (primary != null) return primary;
    return _readFile(await _file(backupName));
  }

  static Future<void> _writeSnapshotUnlocked(Iterable<String> links) async {
    final values = _normalize(links);
    final target = await _file(fileName);
    final backup = await _file(backupName);
    final temp = await _file(tempName);
    final contents = encodeSnapshot(values);

    await temp.writeAsString(contents, flush: true);
    if (await target.exists()) {
      // Never replace a known-good backup with a corrupt primary snapshot.
      final primaryIsValid = await _readFile(target) != null;
      if (primaryIsValid) {
        if (await backup.exists()) await backup.delete();
        await target.copy(backup.path);
      }
      await target.delete();
    }
    try {
      await temp.rename(target.path);
    } catch (_) {
      if (!await target.exists() && await backup.exists()) {
        await backup.copy(target.path);
      }
      rethrow;
    }
  }

  static Future<void> writeSnapshot(Iterable<String> links) =>
      _writeSnapshotUnlocked(links);

  static Future<List<String>> readOrMigrate(
    Future<List<String>> Function() readLegacy,
  ) async {
    final saved = await readSnapshot();
    if (saved != null) return saved;
    final legacy = _normalize(await readLegacy());
    await _writeSnapshotUnlocked(legacy);
    return legacy;
  }
}
