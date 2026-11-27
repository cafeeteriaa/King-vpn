import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  static const int _batchSize = 4096;
  static const int _bloomBytesPerShard = 32768;
  static const int _bloomHashCount = 7;
  static const String directoryName = 'KingVPN/ResourcesFresh';
  static const String _legacyFileName = 'configs.txt';
  static const String _metadataFileName = 'metadata.json';
  static const String _dirtyFileName = '.inventory_dirty';
  static const String _cursorFileName = 'offline_cursor.json';
  static final Map<String, Future<void>> _mergeQueues = <String, Future<void>>{};
  static final Map<String, Future<void>> _readQueues = <String, Future<void>>{};
  static final Map<String, Uint8List> _shardBlooms = <String, Uint8List>{};
  static final Set<String> _shardTailChecked = <String>{};
  static final Map<String, Future<void>> _migrationFutures = <String, Future<void>>{};
  static Future<void> _replacementQueue = Future<void>.value();

  static Future<Directory> directory({Directory? root}) async {
    // Default-root readers/writers wait while a staged refresh swaps the store.
    if (root == null) await _replacementQueue;
    final base = root ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$directoryName');
    if (root == null) {
      final backup = Directory('${dir.path}.backup');
      if (!await dir.exists() && await backup.exists()) {
        await backup.rename(dir.path);
      } else if (await dir.exists() && await backup.exists()) {
        await backup.delete(recursive: true);
      }
      final stageRoot = Directory('${base.path}/.kingvpn-resource-stage');
      if (await stageRoot.exists()) await stageRoot.delete(recursive: true);
    }
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
      if (seen.add(_id(link))) result.add(link);
      if (result.length >= maxEntries) break;
    }
    return result;
  }

  static String _id(String link) {
    final separator = link.indexOf('://');
    final canonical = separator > 0
        ? '${link.substring(0, separator).toLowerCase()}${link.substring(separator)}'
        : link;
    return sha256.convert(utf8.encode(canonical)).toString();
  }

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
    final now = DateTime.now().toUtc().toIso8601String();
    final snapshot = <String, Object?>{
      'schema': 2,
      'source': source,
      'count': count.clamp(0, maxEntries),
      'capacity': maxEntries,
      'shards': shardCount,
      'updatedAt': now,
    };
    if (source == 'online-public-sources' ||
        source == 'online-public-sources-48h-refresh') {
      snapshot['onlineRefreshedAt'] = now;
    }
    await temp.writeAsString(jsonEncode(snapshot), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  /// Streams normalized, deduplicated records without loading the inventory.
  static Stream<String> streamLinks({Directory? root}) async* {
    final dir = await directory(root: root);
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

  static Future<List<String>> readPreview({int limit = 100, Directory? root}) async {
    final result = <String>[];
    if (limit <= 0) return result;
    final dir = await directory(root: root);
    await _migrateLegacy(dir);
    final path = dir.path;
    final previous = _readQueues[path] ?? Future<void>.value();
    final operation = previous.then((_) async {
      await for (final link in streamLinks(root: root)) {
        result.add(link);
        if (result.length >= limit) break;
      }
    });
    _readQueues[path] = operation.then<void>((_) {}, onError: (Object _) {});
    await operation;
    return result;
  }

  /// Returns the next bounded offline batch and persists per-shard byte offsets.
  /// The cursor rotates through every shard, so repeated offline searches can
  /// eventually consume the full four-million-entry inventory without loading it.
  static Future<List<String>> readBatch({int limit = 300, Directory? root}) async {
    if (limit <= 0) return <String>[];
    final dir = await directory(root: root);
    await _migrateLegacy(dir);
    final path = dir.path;
    final previous = _readQueues[path] ?? Future<void>.value();
    final operation = previous.then((_) async {
      final cursorFile = File('${dir.path}/$_cursorFileName');
      var shardIndex = 0;
      final offsets = <String, int>{};
      try {
        if (await cursorFile.exists()) {
          final decoded = jsonDecode(await cursorFile.readAsString());
          if (decoded is Map) {
            shardIndex = ((decoded['shardIndex'] as num?)?.toInt() ?? 0) % shardCount;
            final rawOffsets = decoded['offsets'];
            if (rawOffsets is Map) {
              for (final entry in rawOffsets.entries) {
                final value = entry.value;
                if (value is num && value >= 0) offsets[entry.key.toString()] = value.toInt();
              }
            }
          }
        }
      } catch (_) {
        shardIndex = 0;
        offsets.clear();
      }

      final result = <String>[];
      final emitted = <String>{};
      var visited = 0;
      var stagnantVisits = 0;
      while (result.length < limit && visited < shardCount * 8 &&
          stagnantVisits < shardCount) {
        final shard = shardIndex.toRadixString(16).padLeft(2, '0');
        final file = await _shardFile(dir, shard);
        if (!await file.exists()) {
          offsets[shard] = 0;
          shardIndex = (shardIndex + 1) % shardCount;
          visited++;
          continue;
        }
        final length = await file.length();
        var offset = offsets[shard] ?? 0;
        if (offset < 0 || offset >= length) offset = 0;
        var consumed = false;
        var readInShard = 0;
        var addedFromShard = 0;
        await for (final line in file.openRead(offset)
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          consumed = true;
          final nextOffset = offset + utf8.encode(line).length + 1;
          offset = nextOffset;
          offsets[shard] = nextOffset;
          try {
            final row = jsonDecode(line);
            if (row is Map && row['v'] == 1 &&
                row['id'] is String && row['link'] is String) {
              final link = normalizeLink(row['link'] as String);
              if (link != null && _id(link) == row['id'] && emitted.add(row['id'] as String)) {
                result.add(link);
                addedFromShard++;
              }
            }
          } catch (_) {}
          readInShard++;
          if (readInShard >= 32 || result.length >= limit) break;
        }
        if (!consumed || (offsets[shard] ?? 0) >= length) {
          offsets[shard] = 0;
        }
        stagnantVisits = addedFromShard == 0 ? stagnantVisits + 1 : 0;
        shardIndex = (shardIndex + 1) % shardCount;
        visited++;
      }

      final temp = File('${cursorFile.path}.tmp');
      await temp.writeAsString(jsonEncode(<String, Object?>{
        'schema': 1,
        'shardIndex': shardIndex,
        'offsets': offsets,
      }), flush: true);
      if (await cursorFile.exists()) await cursorFile.delete();
      await temp.rename(cursorFile.path);
      return result;
    });
    _readQueues[path] = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  /// Compatibility API. Prefer readPreview/streamLinks for large inventories.
  static Future<List<String>> readLinks({int limit = maxEntries, Directory? root}) async {
    final result = <String>[];
    if (limit <= 0) return result;
    await for (final link in streamLinks(root: root)) {
      result.add(link);
      if (result.length >= limit) break;
    }
    return result;
  }

  static Future<int> count({Directory? root}) async {
    final dir = await directory(root: root);
    await _migrateLegacy(dir);
    final path = dir.path;
    final previous = _mergeQueues[path] ?? Future<void>.value();
    final operation = previous.then((_) => _countUnlocked(dir, root: root));
    _mergeQueues[path] = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  /// Called only after the per-directory write queue has drained, or by the
  /// merge operation that currently owns it.
  static Future<int> _countUnlocked(Directory dir, {Directory? root}) async {
    final metadata = await _readMetadata(dir);
    final dirty = File('${dir.path}/$_dirtyFileName');
    final cached = metadata['count'];
    if (!await dirty.exists() && cached is int && cached >= 0 && cached <= maxEntries) return cached;
    var total = 0;
    await for (final _ in streamLinks(root: root)) {
      total++;
      if (total >= maxEntries) break;
    }
    await _writeMetadata(dir, total, source: 'recount');
    if (await dirty.exists()) await dirty.delete();
    return total;
  }

  static void _bloomAdd(Uint8List bits, String id) {
    final h1 = int.parse(id.substring(0, 8), radix: 16);
    final h2 = int.parse(id.substring(8, 16), radix: 16) | 1;
    final bitCount = bits.length * 8;
    for (var i = 0; i < _bloomHashCount; i++) {
      final bit = (h1 + i * h2 + i * i) % bitCount;
      bits[bit >> 3] |= 1 << (bit & 7);
    }
  }

  static bool _bloomMayContain(Uint8List bits, String id) {
    final h1 = int.parse(id.substring(0, 8), radix: 16);
    final h2 = int.parse(id.substring(8, 16), radix: 16) | 1;
    final bitCount = bits.length * 8;
    for (var i = 0; i < _bloomHashCount; i++) {
      final bit = (h1 + i * h2 + i * i) % bitCount;
      if ((bits[bit >> 3] & (1 << (bit & 7))) == 0) return false;
    }
    return true;
  }

  /// A small in-memory Bloom filter avoids rescanning large shards for every
  /// 512-item batch. Positive matches are always confirmed against the shard,
  /// so false positives can never discard a valid profile.
  static Future<Uint8List> _loadShardBloom(Directory dir, String shard) async {
    final cacheKey = '${dir.path}/$shard';
    final cached = _shardBlooms[cacheKey];
    if (cached != null) return cached;
    final bits = Uint8List(_bloomBytesPerShard);
    final file = await _shardFile(dir, shard);
    if (await file.exists()) {
      await for (final line in file.openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        try {
          final row = jsonDecode(line);
          if (row is Map && row['id'] is String &&
              row['link'] is String &&
              _id(row['link'] as String) == row['id']) {
            _bloomAdd(bits, row['id'] as String);
          }
        } catch (_) {}
      }
    }
    _shardBlooms[cacheKey] = bits;
    return bits;
  }

  static Future<int> _appendBatch(Directory dir, List<String> links,
      {int maxAdds = maxEntries}) async {
    if (maxAdds <= 0) return 0;
    final grouped = <String, Map<String, String>>{};
    for (final link in links) {
      final id = _id(link);
      grouped.putIfAbsent(_shard(id), () => <String, String>{})[id] = link;
    }
    var added = 0;
    groupLoop: for (final group in grouped.entries) {
      final file = await _shardFile(dir, group.key);
      final bloom = await _loadShardBloom(dir, group.key);
      final wanted = <String>{
        for (final id in group.value.keys)
          if (_bloomMayContain(bloom, id)) id,
      };
      final existing = <String>{};
      if (wanted.isNotEmpty) {
        await for (final line in file.openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          try {
            final row = jsonDecode(line);
            if (row is Map && row['id'] is String &&
                row['link'] is String && wanted.contains(row['id']) &&
                _id(row['link'] as String) == row['id']) {
              existing.add(row['id'] as String);
            }
          } catch (_) {}
        }
      }
      var needsSeparator = false;
      final tailKey = '${dir.path}/${group.key}';
      if (!_shardTailChecked.contains(tailKey) && await file.exists()) {
        final length = await file.length();
        if (length > 0) {
          final tail = await file.openRead(length - 1, length).fold<List<int>>(
            <int>[], (bytes, chunk) => bytes..addAll(chunk));
          needsSeparator = tail.isNotEmpty && tail.last != 10;
        }
      }
      final sink = file.openWrite(mode: FileMode.append);
      try {
        if (needsSeparator) sink.write('\n');
        for (final entry in group.value.entries) {
          if (added >= maxAdds) break groupLoop;
          if (!existing.add(entry.key)) continue;
          sink.writeln(jsonEncode(<String, Object?>{
            'v': 1, 'id': entry.key, 'link': entry.value,
          }));
          _bloomAdd(bloom, entry.key);
          added++;
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      _shardTailChecked.add(tailKey);
    }
    return added;
  }

  /// Merges lazily in small batches. RAM usage is bounded by the batch and one
  /// shard's matching identities, not by the total four-million-record store.
  static Future<int> merge(Iterable<String> links,
      {String source = 'online', Directory? root}) async {
    final dir = await directory(root: root);
    await _migrateLegacy(dir);
    final path = dir.path;
    final previous = _mergeQueues[path] ?? Future<void>.value();
    final operation = previous.then((_) async {
    var total = await _countUnlocked(dir, root: root);
    var batch = <String>[];
    for (final value in links) {
      final link = normalizeLink(value);
      if (link == null) continue;
      batch.add(link);
      if (batch.length < _batchSize) continue;
      final remaining = maxEntries - total;
      if (remaining <= 0) break;
      await File('${dir.path}/$_dirtyFileName').writeAsString('1', flush: true);
      final added = await _appendBatch(dir, batch, maxAdds: remaining);
      total = (total + added).clamp(0, maxEntries).toInt();
      batch = <String>[];
      await _writeMetadata(dir, total, source: source);
      final dirty = File('${dir.path}/$_dirtyFileName');
      if (await dirty.exists()) await dirty.delete();
      if (total >= maxEntries) break;
    }
    if (batch.isNotEmpty && total < maxEntries) {
      final remaining = maxEntries - total;
      await File('${dir.path}/$_dirtyFileName').writeAsString('1', flush: true);
      final added = await _appendBatch(dir, batch, maxAdds: remaining);
      total = (total + added).clamp(0, maxEntries).toInt();
      await _writeMetadata(dir, total, source: source);
      final dirty = File('${dir.path}/$_dirtyFileName');
      if (await dirty.exists()) await dirty.delete();
    }
    return total;
    });
    _mergeQueues[path] = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  /// Replaces the complete inventory only after a staged snapshot has been
  /// fully written and counted. The current inventory remains intact on any
  /// download, validation, write, or process failure before the directory swap.
  static Future<int> replaceSnapshot(Iterable<String> links,
      {String source = 'online-refresh', Directory? root}) async {
    final base = root ?? await getApplicationSupportDirectory();
    final target = Directory('${base.path}/$directoryName');
    final stageRoot = Directory('${base.path}/.kingvpn-resource-stage');
    final staged = Directory('${stageRoot.path}/$directoryName');
    final backup = Directory('${target.path}.backup');
    final previous = _replacementQueue;
    final operation = previous.then((_) async {
      final targetPath = target.path;
      await Future.wait<void>(<Future<void>>[
        _mergeQueues[targetPath] ?? Future<void>.value(),
        _readQueues[targetPath] ?? Future<void>.value(),
      ]);
      if (await stageRoot.exists()) await stageRoot.delete(recursive: true);
      if (await backup.exists()) await backup.delete(recursive: true);
      final total = await merge(links, source: source, root: stageRoot);
      if (total <= 0 || total > maxEntries) {
        throw StateError('Fresh resource refresh produced no valid profiles; previous inventory preserved.');
      }
      final verified = await count(root: stageRoot);
      if (verified != total) {
        throw StateError('Staged resource count mismatch ($verified != $total); previous inventory preserved.');
      }
      if (await target.exists()) await target.rename(backup.path);
      try {
        await staged.rename(target.path);
      } catch (_) {
        if (!await target.exists() && await backup.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }
      if (await backup.exists()) await backup.delete(recursive: true);
      if (await stageRoot.exists()) await stageRoot.delete(recursive: true);
      _shardBlooms.clear();
      _shardTailChecked.clear();
      _mergeQueues.remove(targetPath);
      _readQueues.remove(targetPath);
      return total;
    });
    _replacementQueue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  /// Compatibility API; now uses the crash-recoverable staged replacement.
  static Future<int> saveSnapshot(Iterable<String> links,
      {String source = 'online', Directory? root}) =>
      replaceSnapshot(links, source: source, root: root);

  static Future<void> _migrateLegacy(Directory dir) async {
    final marker = File('${dir.path}/.migration_v2_done');
    if (await marker.exists()) return;
    final existing = _migrationFutures[dir.path];
    if (existing != null) {
      await existing;
      return;
    }
    final previous = _mergeQueues[dir.path] ?? Future<void>.value();
    final task = previous.then((_) async {
      if (await marker.exists()) return;
      await _migrateLegacyImpl(dir);
    });
    final queued = task.then<void>((_) {}, onError: (Object _) {});
    _mergeQueues[dir.path] = queued;
    _migrationFutures[dir.path] = task;
    await task.whenComplete(() {
      if (identical(_migrationFutures[dir.path], task)) {
        _migrationFutures.remove(dir.path);
      }
    });
  }

  static Future<void> _migrateLegacyImpl(Directory dir) async {
    final marker = File('${dir.path}/.migration_v2_done');
    if (await marker.exists()) return;
    final legacy = File('${dir.path}/$_legacyFileName');
    if (await legacy.exists()) {
      var batch = <String>[];
      var migrated = 0;
      await for (final line in legacy.openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final link = normalizeLink(line);
        if (link == null) continue;
        batch.add(link);
        if (batch.length >= _batchSize) {
          final remaining = maxEntries - migrated;
          if (remaining <= 0) break;
          migrated += await _appendBatch(dir, batch, maxAdds: remaining);
          batch = <String>[];
        }
      }
      if (batch.isNotEmpty && migrated < maxEntries) {
        final remaining = maxEntries - migrated;
        await _appendBatch(dir, batch, maxAdds: remaining);
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
              row['link'] is String &&
              _id(row['link'] as String) == row['id']) {
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

  static Future<Map<String, Object?>> metadata({Directory? root}) async {
    final dir = await directory(root: root);
    await _migrateLegacy(dir);
    final value = await _readMetadata(dir);
    return <String, Object?>{
      ...value,
      'count': await count(root: root),
      'capacity': maxEntries,
    };
  }

  static Future<void> clear({Directory? root}) async {
    final dir = await directory(root: root);
    final path = dir.path;
    final pendingWrite = _mergeQueues[path] ?? Future<void>.value();
    final pendingRead = _readQueues[path] ?? Future<void>.value();
    final operation = Future.wait<void>(<Future<void>>[
      pendingWrite,
      pendingRead,
    ]).then((_) async {
      await File('${dir.path}/.migration_v2_done').writeAsString('v2', flush: true);
      await File('${dir.path}/$_dirtyFileName').writeAsString('1', flush: true);
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File &&
            (RegExp(r'^[0-9a-f]{2}\.jsonl$').hasMatch(entity.uri.pathSegments.last) ||
             entity.uri.pathSegments.last == _metadataFileName ||
             entity.uri.pathSegments.last == _cursorFileName ||
             entity.uri.pathSegments.last == _legacyFileName ||
             entity.uri.pathSegments.last == '${_legacyFileName}.migrated')) {
          await entity.delete();
        }
      }
      _shardBlooms.removeWhere((key, _) => key.startsWith('${dir.path}/'));
      _shardTailChecked.removeWhere((key) => key.startsWith('${dir.path}/'));
      await _writeMetadata(dir, 0, source: 'cleared');
      final dirty = File('${dir.path}/$_dirtyFileName');
      if (await dirty.exists()) await dirty.delete();
      await File('${dir.path}/.migration_v2_done').writeAsString('v2', flush: true);
    });
    final queued = operation.then<void>((_) {}, onError: (Object _) {});
    _mergeQueues[path] = queued;
    _readQueues[path] = queued;
    await operation;
  }
}
