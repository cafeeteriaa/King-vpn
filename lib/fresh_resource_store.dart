import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persistent app-private cache for public VPN profiles.
/// Reads and merges are streamed so the four-million-entry ceiling does not
/// imply a four-million-object in-memory list.
class FreshResourceStore {
  FreshResourceStore._();

  static const int maxEntries = 4_000_000;
  static const int maxStorageBytes = 500 * 1024 * 1024;
  static const int defaultPageSize = 300;
  static const String directoryName = 'KingVPN/ResourcesFresh';
  static const String _configFileName = 'configs.txt';
  static const String _metadataFileName = 'metadata.json';

  static Future<Directory> directory() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/$directoryName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _configFile() async =>
      File('${(await directory()).path}/$_configFileName');

  static Future<String> get storagePath async => (await directory()).path;

  static String? normalizeLink(String value) {
    final link = value.trim().replaceAll('\r', '');
    if (link.isEmpty || link.length > 65536) return null;
    final lower = link.toLowerCase();
    if (!(lower.startsWith('vless://') ||
        lower.startsWith('vmess://') ||
        lower.startsWith('trojan://') ||
        lower.startsWith('ss://') ||
        lower.startsWith('hysteria2://') ||
        lower.startsWith('hy2://') ||
        lower.startsWith('tuic://'))) {
      return null;
    }
    return link;
  }

  static List<String> normalizeLinks(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    var bytes = 0;
    for (final value in values) {
      final link = normalizeLink(value);
      if (link == null || !seen.add(link.toLowerCase())) continue;
      final size = utf8.encode(link).length + 1;
      if (result.length >= maxEntries || bytes + size > maxStorageBytes) break;
      result.add(link);
      bytes += size;
    }
    return result;
  }

  /// Opens a sequential cursor. Keep it between page reads to avoid rescanning
  /// the start of the file for each batch.
  static Future<FreshResourceCursor?> openCursor() async {
    final file = await _configFile();
    if (!await file.exists()) return null;
    final stream = file.openRead().transform(utf8.decoder).transform(const LineSplitter());
    return FreshResourceCursor(StreamIterator<String>(stream));
  }

  /// Compatibility API for small consumers. Production offline scanning uses
  /// openCursor() and bounded pages instead.
  static Future<List<String>> readLinks() async {
    final cursor = await openCursor();
    if (cursor == null) return <String>[];
    final values = <String>[];
    try {
      while (!cursor.isDone) {
        values.addAll(await cursor.nextPage());
      }
    } finally {
      await cursor.close();
    }
    return values;
  }

  static Future<int> saveSnapshot(
    Iterable<String> links, {
    String source = 'online',
  }) async {
    final normalized = normalizeLinks(links);
    final file = await _configFile();
    final temp = File('${file.path}.tmp');
    final sink = temp.openWrite();
    var count = 0;
    var bytes = 0;
    try {
      for (final link in normalized) {
        sink.writeln(link);
        count++;
        bytes += utf8.encode(link).length + 1;
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    await temp.rename(file.path);
    await _writeMetadata(source: source, count: count, bytes: bytes);
    return count;
  }

  /// Streaming merge: RAM use scales with the incoming batch, not the
  /// existing offline file. Existing entries win on case-insensitive duplicates.
  static Future<int> merge(
    Iterable<String> links, {
    String source = 'online',
  }) async {
    final incoming = <String, String>{};
    for (final raw in links) {
      final link = normalizeLink(raw);
      if (link != null) incoming.putIfAbsent(link.toLowerCase(), () => link);
    }

    final file = await _configFile();
    final temp = File('${file.path}.tmp');
    final sink = temp.openWrite();
    var count = 0;
    var bytes = 0;

    void writeLink(String link) {
      sink.writeln(link);
      count++;
      bytes += utf8.encode(link).length + 1;
    }

    try {
      if (await file.exists()) {
        await for (final raw in file.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
          final link = normalizeLink(raw);
          if (link == null) continue;
          incoming.remove(link.toLowerCase());
          final size = utf8.encode(link).length + 1;
          if (count >= maxEntries || bytes + size > maxStorageBytes) break;
          writeLink(link);
        }
      }
      for (final link in incoming.values) {
        final size = utf8.encode(link).length + 1;
        if (count >= maxEntries || bytes + size > maxStorageBytes) break;
        writeLink(link);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    // Android/Linux rename replaces the destination atomically; on failure the
    // previous cache remains untouched.
    await temp.rename(file.path);
    await _writeMetadata(source: source, count: count, bytes: bytes);
    return count;
  }

  static Future<void> _writeMetadata({
    required String source,
    required int count,
    required int bytes,
  }) async {
    final metadata = File('${(await directory()).path}/$_metadataFileName');
    await metadata.writeAsString(jsonEncode(<String, Object>{
      'schema': 2,
      'source': source,
      'count': count,
      'bytes': bytes,
      'maxEntries': maxEntries,
      'maxStorageBytes': maxStorageBytes,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }), flush: true);
  }

  static Future<Map<String, Object?>> metadata() async {
    try {
      final file = File('${(await directory()).path}/$_metadataFileName');
      if (!await file.exists()) return <String, Object?>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {}
    return <String, Object?>{};
  }

  static Future<void> clear() async {
    final file = await _configFile();
    if (await file.exists()) await file.delete();
    final temp = File('${file.path}.tmp');
    if (await temp.exists()) await temp.delete();
    final metadata = File('${(await directory()).path}/$_metadataFileName');
    if (await metadata.exists()) await metadata.delete();
  }
}

class FreshResourceCursor {
  FreshResourceCursor(this._lines);

  final StreamIterator<String> _lines;
  bool isDone = false;
  bool _closed = false;
  int position = 0;

  Future<List<String>> nextPage({
    int limit = FreshResourceStore.defaultPageSize,
  }) async {
    if (_closed || isDone || limit <= 0) return <String>[];
    final page = <String>[];
    while (page.length < limit && await _lines.moveNext()) {
      position++;
      final link = FreshResourceStore.normalizeLink(_lines.current);
      if (link != null) page.add(link);
    }
    if (page.length < limit) isDone = true;
    return page;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _lines.cancel();
  }
}
