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
/// The store exposes bounded page and batch readers plus transactional
/// streaming mutations. Legacy consumers may still materialize the inventory;
/// callers must use readBatches when they need bounded-memory traversal.
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

  /// Copies backups incrementally; readAsBytes would reintroduce O(fileSize)
  /// memory use in the very transaction path this store is designed to bound.
  static Future<void> _copyFileStreaming(File source, File destination) async {
    final sink = destination.openWrite(mode: FileMode.writeOnly);
    try {
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      rethrow;
    }
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

  /// Writes a complete snapshot without constructing a second normalized
  /// inventory or one giant encoded String. The caller-owned input is frozen
  /// once by writeSnapshot; this method keeps only the deduplication keys and
  /// the active output buffer while encoding records incrementally.
  static Future<void> _writeSnapshotUnlocked(Iterable<String> links) async {
    final target = await _file(fileName);
    final backup = await _file(backupName);
    final temp = await _file(tempName);
    final backupTemp = await _file(backupTempName);
    final seen = <String>{};
    final sink = temp.openWrite(mode: FileMode.writeOnly);

    try {
      for (final raw in links) {
        final value = raw.trim();
        if (value.isEmpty || !seen.add(value.toLowerCase())) continue;
        sink.writeln(jsonEncode(value));
      }
      await sink.flush();
      await sink.close();

      // Rotate only a validated primary. Stage the backup separately and rename
      // it over the old backup, so interruption cannot destroy the last good copy.
      if (await _isValidSnapshot(target)) {
        await _copyFileStreaming(target, backupTemp);
        await _replaceByRename(backupTemp, backup);
      }

      // On Android/Linux this is a single filesystem rename/replace operation.
      // If it fails, the previous primary remains in place and backup is intact.
      await _replaceByRename(temp, target);
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      if (await temp.exists()) await temp.delete();
      if (await backupTemp.exists()) await backupTemp.delete();
      rethrow;
    }
  }

  static Future<void> writeSnapshot(Iterable<String> links) {
    final snapshot = List<String>.of(links);
    return _serializeMutation(() => _writeSnapshotUnlocked(snapshot));
  }


  /// Streams a validated snapshot in bounded batches. Validation is a separate
  /// pass so a corrupt primary never yields a partial prefix before backup
  /// recovery begins. Memory use is O(batchSize), not O(inventory size).
  static Stream<List<String>> readBatches({int batchSize = 128}) async* {
    if (batchSize <= 0) throw ArgumentError.value(batchSize, 'batchSize');
    final primary = await _file(fileName);
    final backup = await _file(backupName);
    File? selected;
    if (await _isValidSnapshot(primary)) {
      selected = primary;
    } else if (await _isValidSnapshot(backup)) {
      selected = backup;
    }
    if (selected == null) return;

    var batch = <String>[];
    await for (final value in _streamSnapshot(selected)) {
      batch.add(value);
      if (batch.length == batchSize) {
        yield List<String>.unmodifiable(batch);
        batch = <String>[];
      }
    }
    if (batch.isNotEmpty) yield List<String>.unmodifiable(batch);
  }

  static Future<bool> _isValidSnapshot(File file) async {
    if (!await file.exists()) return false;
    try {
      await for (final _ in _streamSnapshot(file)) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  static Stream<String> _streamSnapshot(File file) async* {
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is! String) {
        throw const FormatException('Personal-folder record is not a string');
      }
      final value = decoded.trim();
      if (value.isNotEmpty) yield value;
    }
  }

  /// Checks membership without loading the complete inventory into memory.
  static Future<bool> containsLink(String link) async {
    final needle = link.trim().toLowerCase();
    if (needle.isEmpty) return false;
    await for (final batch in readBatches()) {
      if (batch.any((value) => value.toLowerCase() == needle)) return true;
    }
    return false;
  }

  /// Appends new unique profiles by streaming the old snapshot into a staged
  /// replacement. This deliberately trades sequential disk I/O for bounded
  /// RAM while retaining atomic commit and backup recovery semantics.
  /// Returns precisely the links committed by this transaction.
  static Future<List<String>> appendLinks(Iterable<String> links) {
    final input = _normalize(links);
    if (input.isEmpty) return Future<List<String>>.value(const <String>[]);
    return _serializeMutation(() => _rewriteUnlocked(
      additions: input,
      removals: const <String>{},
    ));
  }

  /// Removes matching profiles with the same streaming/atomic transaction.
  static Future<int> removeLinks(Iterable<String> links) async {
    final keys = links.map((v) => v.trim().toLowerCase())
        .where((v) => v.isNotEmpty).toSet();
    if (keys.isEmpty) return 0;
    return _serializeMutation(() async {
      final before = await _countMatching(keys);
      if (before == 0) return 0;
      await _rewriteUnlocked(
        additions: const <String>[],
        removals: keys,
      );
      return before;
    });
  }

  static Future<int> _countMatching(Set<String> keys) async {
    var count = 0;
    await for (final batch in readBatches()) {
      for (final value in batch) {
        if (keys.contains(value.toLowerCase())) count++;
      }
    }
    return count;
  }

  static Future<List<String>> _rewriteUnlocked({
    required List<String> additions,
    required Set<String> removals,
  }) async {
    final target = await _file(fileName);
    final backup = await _file(backupName);
    final temp = await _file(tempName);
    final backupTemp = await _file(backupTempName);

    final primaryValid = await _isValidSnapshot(target);
    final backupValid = await _isValidSnapshot(backup);
    File? source;
    if (primaryValid) {
      source = target;
    } else if (backupValid) {
      source = backup;
    } else if (await target.exists() || await backup.exists()) {
      throw const FormatException(
        'Both personal-folder primary and backup are invalid',
      );
    }

    // Only the incoming batch is held in memory. Existing inventory records
    // are copied one line at a time and are never materialized as a List.
    final pending = <String, String>{
      for (final value in additions) value.toLowerCase(): value,
    };
    final sink = temp.openWrite(mode: FileMode.writeOnly);
    try {
      if (source != null) {
        await for (final value in _streamSnapshot(source)) {
          final key = value.toLowerCase();
          if (removals.contains(key)) continue;
          pending.remove(key);
          sink.writeln(jsonEncode(value));
        }
      }
      for (final value in pending.values) {
        sink.writeln(jsonEncode(value));
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await temp.exists()) await temp.delete();
      rethrow;
    }

    // Preserve a validated primary before replacing it. If recovering from
    // backup, never overwrite the only valid backup with a corrupt primary.
    if (primaryValid) {
      await _copyFileStreaming(target, backupTemp);
      await _replaceByRename(backupTemp, backup);
    }
    await _replaceByRename(temp, target);
    return List<String>.unmodifiable(
      additions.where((value) => pending.containsKey(value.toLowerCase())),
    );
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
