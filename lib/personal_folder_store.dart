import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A bounded view over the complete on-disk inventory.
/// totalCount is the number of matches, not a maximum inventory size.
class PersonalFolderPage {
  const PersonalFolderPage({
    required this.items,
    required this.offset,
    required this.totalCount,
    required this.query,
  });

  final List<String> items;
  final int offset;
  final int totalCount;
  final String query;

  bool get hasPrevious => offset > 0;
  bool get hasNext => offset + items.length < totalCount;
}

/// Durable app-private storage for personal VPN profiles.
/// Consumers still materialize the current folder in memory; this class does
/// not claim to implement paging.
class PersonalFolderStore {
  PersonalFolderStore._();

  static const String directoryName = 'KingVPN/Personal';
  static const String fileName = 'servers.jsonl';
  static const String backupName = 'servers.jsonl.bak';
  static const String tempName = 'servers.jsonl.tmp';
  static const String backupTempName = 'servers.jsonl.bak.tmp';

  /// Injectable only for filesystem tests; production leaves this unset.
  static Future<Directory> Function()? directoryProviderForTesting;

  static Future<void> _mutationQueue = Future<void>.value();

  static Future<T> _serializeMutation<T>(Future<T> Function() action) {
    final operation = _mutationQueue.then<T>((_) => action());
    _mutationQueue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return operation;
  }

  static Future<Directory> directory() async {
    final override = directoryProviderForTesting;
    if (override != null) {
      final dir = await override();
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
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

  /// Replaces a destination using a same-directory rename. Android/Linux
  /// rename atomically replaces an existing destination; no delete-before-
  /// rename window is introduced.
  static Future<void> _replaceByRename(File source, File destination) async {
    await source.rename(destination.path);
  }


  static Future<PersonalFolderPage?> _scanPage(
    File file, {
    required int offset,
    required int limit,
    required String query,
  }) async {
    if (!await file.exists()) return null;
    final needle = query.trim().toLowerCase();
    final selected = <String>[];
    var matches = 0;
    try {
      await for (final line in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isEmpty) continue;
        final decoded = jsonDecode(line);
        if (decoded is! String) return null;
        final value = decoded.trim();
        if (value.isEmpty) continue;
        if (needle.isNotEmpty && !value.toLowerCase().contains(needle)) {
          continue;
        }
        if (matches >= offset && selected.length < limit) {
          selected.add(value);
        }
        matches++;
      }
      return PersonalFolderPage(
        items: selected,
        offset: offset,
        totalCount: matches,
        query: needle,
      );
    } catch (_) {
      return null;
    }
  }

  /// Reads only the requested page into memory while streaming the full file
  /// to calculate the exact filtered count. If the primary is corrupt, retries
  /// the backup. The page size is a presentation batch, never an inventory cap.
  static Future<PersonalFolderPage> readPage({
    int offset = 0,
    int limit = 50,
    String query = '',
  }) async {
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    final primary = await _scanPage(
      await _file(fileName),
      offset: offset,
      limit: limit,
      query: query,
    );
    if (primary != null) return primary;
    final backup = await _scanPage(
      await _file(backupName),
      offset: offset,
      limit: limit,
      query: query,
    );
    return backup ??
        PersonalFolderPage(
          items: const <String>[],
          offset: offset,
          totalCount: 0,
          query: query.trim().toLowerCase(),
        );
  }

  static Future<void> _writeSnapshotUnlocked(Iterable<String> links) async {
    final values = _normalize(links);
    final target = await _file(fileName);
    final backup = await _file(backupName);
    final temp = await _file(tempName);
    final backupTemp = await _file(backupTempName);
    final contents = encodeSnapshot(values);

    // Stage and flush the new primary before touching either committed file.
    await temp.writeAsString(contents, flush: true);

    // Rotate only a validated primary. Stage the backup separately and rename
    // it over the old backup, so interruption cannot destroy the last good copy.
    if (await target.exists() && await _readFile(target) != null) {
      await backupTemp.writeAsBytes(await target.readAsBytes(), flush: true);
      await _replaceByRename(backupTemp, backup);
    }

    // On Android/Linux this is a single filesystem rename/replace operation.
    // If it fails, the previous primary remains in place and backup is intact.
    await _replaceByRename(temp, target);
  }

  static Future<void> writeSnapshot(Iterable<String> links) {
    final snapshot = List<String>.of(links);
    return _serializeMutation(() => _writeSnapshotUnlocked(snapshot));
  }

  static Future<List<String>> readOrMigrate(
    Future<List<String>> Function() readLegacy,
  ) {
    return _serializeMutation(() async {
      final saved = await readSnapshot();
      if (saved != null) return saved;
      final legacy = _normalize(await readLegacy());
      await _writeSnapshotUnlocked(legacy);
      return legacy;
    });
  }
}
