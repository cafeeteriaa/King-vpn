import 'dart:convert';
import 'dart:io';

/// Durable, lossless JSONL storage for inventories that can grow beyond the
/// practical size of a preferences value. Records are streamed on read/write;
/// no record-count or byte-count truncation is applied.
class JsonLinesInventoryStore {
  JsonLinesInventoryStore(this.file);

  final File file;

  Future<List<Map<String, dynamic>>> readAll() async {
    if (!await file.exists()) return <Map<String, dynamic>>[];
    final records = <Map<String, dynamic>>[];
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException('Inventory record must be a JSON object');
      }
      records.add(Map<String, dynamic>.from(decoded));
    }
    return records;
  }

  /// Replaces the snapshot through a same-directory temporary file. The old
  /// snapshot remains intact if encoding or writing the new one fails.
  Future<void> replaceAll(Iterable<Map<String, dynamic>> records) async {
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
