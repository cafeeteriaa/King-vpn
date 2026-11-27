import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent, bounded-memory store for offline VPN profiles.
///
/// Four million is a storage capacity, not an in-memory List capacity.
/// Profiles are split across 256 append-only JSONL shards and read as a Stream.
class FreshResourceStore {
  FreshResourceStore._();

  static const int maxEntries = 4000000;
  static const int shardCount = 256;
  static const int _batchSize = 512;
  static const String directoryName = 'KingVPN/ResourcesFresh';
  static const String _legacyFileName = 'configs.txt';
  static const String _metadataFileName = 'metadata.json';
  static const String _dirtyFileName = '.inventory_dirty';
  static final Map<String, Future<void>> _mergeQueues = <String, Future<void>>{};

  static Future<Directory> directory() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/$directoryName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

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
        lower.startsWith('tuic://'))) return null;
    return link;
  }

  static List<String> normalizeLinks(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final link = normalizeLink(value);
      if (link == null) continue;
      if (seen.add(link.toLowerCase())) result.add(link);
      if (result.length >= maxEntries) break;
    }
    return result;
  }

  static String _id(String link) =>
      sha256.convert(utf8.encode(link.toLowerCase())).toString();

  static String _shard(String id) => id.substring(0, 2);

  static Future<File> _shardFile(Directory dir, String shard) async =>
      File('${dir.path}/$shard.jsonl');


  static Future<Map<String, Object?>> _readMetadata(Directory dir) async {
    final file = File('${dir.path}/$_metadataFileName');
    try {
      if (!await file.exists()) return <String, Object?>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {}
    return <String, Object?>{};
  }

  static Future<void> _writeMetadata(Directory dir, int count,
      {String source = 'online'}) async {
    final file = File('${dir.path}/$_metadataFileName');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(<String, Object?>{
      'schema': 2,
      'source': source,
      'count': count.clamp(0, maxEntries),
      'capacity': maxEntries,
      'shards': shardCount,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  /// Streams normalized, deduplicated records without loading the inventory.
  static Stream<String> streamLinks() async* {
    final dir = await directory();
    await _migrateLegacy(dir);
    final shards = dir.list(followLinks: false)
        .where((entity) => entity is File &&
            RegExp(r'^[0-9a-f]{2}\.jsonl$').hasMatch(entity.uri.pathSegments.last));
    await for (final entity in shards) {
      final file = entity as File;
      await for (final line in file.openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isEmpty) continue;
        try {
          final row = jsonDecode(line);
          if (row is! Map || row['v'] != 1 ||
              row['id'] is! String || row['link'] is! String) continue;
          final link = normalizeLink(row['link'] as String);
          if (link != null && _id(link) == row['id']) yield link;
        } catch (_) {
          // A damaged record is skipped; subsequent valid records remain readable.
        }
      }
    }
  }

  static Future<List<String>> readPreview({int limit = 100}) async {
    final result = <String>[];
    if (limit <= 0) return result;
    await for (final link in streamLinks()) {
      result.add(link);
      if (result.length >= limit) break;
    }
    return result;
  }

  /// Compatibility API. Prefer readPreview/streamLinks for large inventories.
  static Future<List<String>> readLinks({int limit = maxEntries}) async {
    final result = <String>[];
    if (limit <= 0) return result;
    await for (final link in streamLinks()) {
      result.add(link);
      if (result.length >= limit) break;
    }
    return result;
  }

  static Future<int> count() async {
    final dir = await directory();
    await _migrateLegacy(dir);
    final metadata = await _readMetadata(dir);
    final dirty = File('${dir.path}/$_dirtyFileName');
    final cached = metadata['count'];
    if (!await dirty.exists() && cached is int && cached >= 0 && cached <= maxEntries) return cached;
    var total = 0;
    await for (final _ in streamLinks()) {
      total++;
      if (total >= maxEntries) break;
    }
    await _writeMetadata(dir, total, source: 'recount');
    if (await dirty.exists()) await dirty.delete();
    return total;
  }

  static Future<int> _appendBatch(Directory dir, List<String> links) async {
    final grouped = <String, Map<String, String>>{};
    for (final link in links) {
      final id = _id(link);
      grouped.putIfAbsent(_shard(id), () => <String, String>{})[id] = link;
    }
    var added = 0;
    for (final group in grouped.entries) {
      final file = await _shardFile(dir, group.key);
      final existing = <String>{};
      if (await file.exists()) {
        await for (final line in file.openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          try {
            final row = jsonDecode(line);
            if (row is Map && row['id'] is String &&
                group.value.containsKey(row['id'])) {
              existing.add(row['id'] as String);
            }
          } catch (_) {}
        }
      }
      var needsSeparator = false;
      if (await file.exists()) {
        final length = await file.length();
        if (length > 0) {
          final tail = await file.openRead(length - 1, length).fold<List<int>>(
            <int>[], (bytes, chunk) => bytes..addAll(chunk));
          needsSeparator = tail.isNotEmpty && tail.last != 10;
        }
      }
      final sink = file.openWrite(mode: FileMode.append);
      try {
        if (needsSeparator) sink.write('\\n');
        for (final entry in group.value.entries) {
          if (!existing.add(entry.key)) continue;
          sink.writeln(jsonEncode(<String, Object?>{
            'v': 1, 'id': entry.key, 'link': entry.value,
          }));
          added++;
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    }
    return added;
  }

  /// Merges lazily in small batches. RAM usage is bounded by the batch and one
  /// shard's matching identities, not by the total four-million-record store.
  static Future<int> merge(Iterable<String> links,
      {String source = 'online'}) async {
    final dir = await directory();
    await _migrateLegacy(dir);
    final path = dir.path;
    final previous = _mergeQueues[path] ?? Future<void>.value();
    final operation = previous.then((_) async {
    var total = await count();
    var batch = <String>[];
    await for (final value in Stream<String>.fromIterable(links)) {
      final link = normalizeLink(value);
      if (link == null) continue;
      batch.add(link);
      if (batch.length < _batchSize) continue;
      final remaining = maxEntries - total;
      if (remaining <= 0) break;
      if (batch.length > remaining) batch = batch.take(remaining).toList();
      await File('${dir.path}/$_dirtyFileName').writeAsString('1', flush: true);
      final added = await _appendBatch(dir, batch);
      total = (total + added).clamp(0, maxEntries).toInt();
      batch = <String>[];
      await _writeMetadata(dir, total, source: source);
      final dirty = File('${dir.path}/$_dirtyFileName');
      if (await dirty.exists()) await dirty.delete();
      if (total >= maxEntries) break;
    }
    if (batch.isNotEmpty && total < maxEntries) {
      final remaining = maxEntries - total;
      if (batch.length > remaining) batch = batch.take(remaining).toList();
      await File('${dir.path}/$_dirtyFileName').writeAsString('1', flush: true);
      final added = await _appendBatch(dir, batch, source: source);
      total = (total + added).clamp(0, maxEntries);
      await _writeMetadata(dir, total, source: source);
      final dirty = File('${dir.path}/$_dirtyFileName');
      if (await dirty.exists()) await dirty.delete();
    }
    return total;
    });
    _mergeQueues[path] = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  static Future<int> saveSnapshot(Iterable<String> links,
      {String source = 'online'}) async {
    await clear();
    return merge(links, source: source);
  }

  static Future<void> _migrateLegacy(Directory dir) async {
    final marker = File('${dir.path}/.migration_v2_done');
    if (await marker.exists()) return;
    final legacy = File('${dir.path}/$_legacyFileName');
    if (await legacy.exists()) {
      var batch = <String>[];
      await for (final line in legacy.openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final link = normalizeLink(line);
        if (link == null) continue;
        batch.add(link);
        if (batch.length >= _batchSize) {
          await _appendBatch(dir, batch, source: 'legacy-migration');
          batch = <String>[];
        }
      }
      if (batch.isNotEmpty) {
        await _appendBatch(dir, batch, source: 'legacy-migration');
      }
      await legacy.rename('${legacy.path}.migrated');
    }
    var total = 0;
    final shards = dir.list(followLinks: false)
        .where((entity) => entity is File &&
            RegExp(r'^[0-9a-f]{2}\.jsonl$').hasMatch(entity.uri.pathSegments.last));
    await for (final entity in shards) {
      await for (final line in (entity as File).openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        try {
          final row = jsonDecode(line);
          if (row is Map && row['v'] == 1 && row['id'] is String &&
              row['link'] is String && _id(row['link'] as String) == row['id']) {
            total++;
            if (total >= maxEntries) break;
          }
        } catch (_) {}
      }
      if (total >= maxEntries) break;
    }
    await _writeMetadata(dir, total, source: 'migration');
    await marker.writeAsString('v2', flush: true);
  }

  static Future<Map<String, Object?>> metadata() async {
    final dir = await directory();
    await _migrateLegacy(dir);
    final value = await _readMetadata(dir);
    return <String, Object?>{
      ...value,
      'count': value['count'] is int ? value['count'] : await count(),
      'capacity': maxEntries,
    };
  }

  static Future<void> clear() async {
    final dir = await directory();
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File &&
          (RegExp(r'^[0-9a-f]{2}\.jsonl$').hasMatch(entity.uri.pathSegments.last) ||
           entity.uri.pathSegments.last == _metadataFileName ||
           entity.uri.pathSegments.last == _dirtyFileName ||
           entity.uri.pathSegments.last == '.migration_v2_done' ||
           entity.uri.pathSegments.last == '$_legacyFileName.migrated')) {
        await entity.delete();
      }
    }
    await _writeMetadata(dir, 0, source: 'cleared');
    await File('${dir.path}/.migration_v2_done').writeAsString('v2', flush: true);
  }
}
