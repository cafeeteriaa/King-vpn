import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Lossless JSONL storage for inventories that can grow beyond preferences.
///
/// Reads can be consumed as a stream. [readAll] is retained for callers that
/// need an in-memory snapshot. Writes are serialized per store instance and
/// publish a replacement only after the complete temporary snapshot is closed.
class JsonLinesInventoryStore {
  JsonLinesInventoryStore(this.file);

  final File file;
  Future<void> _writeQueue = Future<void>.value();

  /// Yields every record in file order without collecting the inventory.
  ///
  /// A malformed line is surfaced as an error; records are never silently
  /// skipped except for empty separator lines.
  Stream<Map<String, dynamic>> readRecords() async* {
    if (!await file.exists()) return;
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException('Inventory record must be a JSON object');
      }
      yield Map<String, dynamic>.from(decoded);
    }
  }

  /// Convenience snapshot API. Use [readRecords] for large inventories.
  Future<List<Map<String, dynamic>>> readAll() => readRecords().toList();

  /// Serializes replacements so concurrent callers cannot share the temp file.
  ///
  /// The temporary file is in the same directory as the destination; the final
  /// rename is atomic on Android's filesystem. No record or byte ceiling is
  /// applied. A failed encode/write leaves the previous snapshot untouched.
  Future<void> replaceAll(Iterable<Map<String, dynamic>> records) {
    final operation = _writeQueue.then((_) => _replaceAll(records));
    _writeQueue = operation.catchError((Object _) {});
    return operation;
  }

  /// Writes [prefix] first, then streams the existing snapshot and retains
  /// every record for which [removeExisting] is false.
  ///
  /// Memory use is proportional to the prefix, not the complete inventory.
  Future<void> prependAndFilter(
    Iterable<Map<String, dynamic>> prefix, {
    required bool Function(Map<String, dynamic> record) removeExisting,
  }) {
    final operation =
        _writeQueue.then((_) => _prependAndFilter(prefix, removeExisting));
    _writeQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _prependAndFilter(
    Iterable<Map<String, dynamic>> prefix,
    bool Function(Map<String, dynamic> record) removeExisting,
  ) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    try {
      final sink = temporary.openWrite(mode: FileMode.writeOnly);
      try {
        for (final record in prefix) {
          sink.writeln(jsonEncode(record));
        }
        await for (final record in readRecords()) {
          if (!removeExisting(record)) sink.writeln(jsonEncode(record));
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      await temporary.rename(file.path);
    } catch (_) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        // Preserve the original write/parse/rename error.
      }
      rethrow;
    }
  }

  Future<void> _replaceAll(Iterable<Map<String, dynamic>> records) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    try {
      final sink = temporary.openWrite(mode: FileMode.writeOnly);
      try {
        for (final record in records) {
          sink.writeln(jsonEncode(record));
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      await temporary.rename(file.path);
    } catch (_) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        // Preserve the original write/rename error.
      }
      rethrow;
    }
  }
}
