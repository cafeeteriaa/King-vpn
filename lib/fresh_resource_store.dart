import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent, bounded-memory store for offline VPN profiles.
///
/// The offline archive has a deliberate four-million-profile capacity.
/// Profiles are split across 256 append-only JSONL shards and read as a Stream,
/// so the configured capacity never requires loading the archive into RAM.
class FreshResourceStore {
  FreshResourceStore._();

  static const int maxEntries = 4000000;
  static const int shardCount = 256;
  static const int _batchSize = 4096;
  static const int _bloomBytesPerShard = 32768;
  static const int _bloomHashCount = 7;
  static const String directoryName = 'KingVPN/ResourcesFresh';

  /// Rejects suspiciously incomplete refreshes before they can replace a
  /// previously useful offline inventory. This is a quality gate, not a
  /// capacity limit: small stores can still refresh completely.
  static int minimumSnapshotReplacementCount(int previousCount) {
    if (previousCount <= 0) return 1;
    // Retain at least 75% of the previous useful inventory. A source
    // outage or truncated response must not replace millions of profiles
    // with a tiny but technically non-empty snapshot.
    final threeQuarters = (previousCount * 3 + 3) ~/ 4;
    return previousCount < 100
        ? previousCount
        : (threeQuarters < 100 ? 100 : threeQuarters);
  }

  static bool isSufficientSnapshotReplacement({
    required int previousCount,
    required int incomingCount,
    required int successfulSources,
    required int configuredSources,
  }) {
    if (incomingCount <= 0 || successfulSources <= 0) return false;
    final requiredSources = configuredSources > 1 ? 2 : 1;
    if (successfulSources < requiredSources) return false;
    return incomingCount >= minimumSnapshotReplacementCount(previousCount);
  }
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
  static int _activeStreams = 0;
  static Completer<void>? _streamsDrained;

  static void _streamStarted() {
    if (_activeStreams++ == 0) _streamsDrained = Completer<void>();
  }

  static void _streamFinished() {
    _activeStreams--;
    if (_activeStreams == 0) {
      final drained = _streamsDrained;
      _streamsDrained = null;
      if (drained != null && !drained.isCompleted) drained.complete();
    }
  }

  static Future<void> _waitForStreams() async {
    if (_activeStreams == 0) return;
    final pending = _streamsDrained?.future;
    if (pending != null) await pending;
  }

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
    // Keep only profiles the currently wired Xray parser/core can consume.
    // Hysteria2/TUIC are intentionally not counted as usable offline configs
    // until their native engine adapters are actually integrated and tested.
    if (!(lower.startsWith('vless://') ||
        lower.startsWith('vmess://') ||
        lower.startsWith('trojan://') ||
        lower.startsWith('ss://'))) return null;
    return link;
  }

  static List<String> normalizeLinks(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final link = normalizeLink(value);
      if (link == null) continue;
      if (seen.add(_id(link))) result.add(link);
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

  /// Writes a same-directory temporary file and atomically renames it over the
  /// previous snapshot. Never delete the last valid metadata/cursor first: a
  /// process death between delete and rename would otherwise lose recovery state.
  static Future<void> _atomicReplace(File file, String contents) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(contents, flush: true);
    await temp.rename(file.path);
  }

  static Future<void> _writeMetadata(Directory dir, int count,
      {String source = 'online'}) async {
    final file = File('${dir.path}/$_metadataFileName');
    final now = DateTime.now().toUtc().toIso8601String();
    final previous = await _readMetadata(dir);
    final snapshot = <String, Object?>{
      'schema': 2,
      'source': source,
      'count': count,
      'shards': shardCount,
      'updatedAt': now,
    };
    final priorOnlineRefresh = previous['onlineSnapshotRefreshedAt'];
    if (priorOnlineRefresh != null) {
      snapshot['onlineSnapshotRefreshedAt'] = priorOnlineRefresh;
    }
    if (source == 'online-public-sources-48h-refresh') {
      snapshot['onlineSnapshotRefreshedAt'] = now;
    }
    await _atomicReplace(file, jsonEncode(snapshot));
  }

  /// Streams normalized, deduplicated records without loading the inventory.
  static Stream<String> streamLinks({Directory? root}) async* {
    final dir = await directory(root: root);
    _streamStarted();
    try {
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
            final id = row['id'] as String;
            final shard = file.uri.pathSegments.last.substring(0, 2);
            final link = normalizeLink(row['link'] as String);
            if (link != null && _id(link) == id && _shard(id) == shard) {
              yield link;
            }
          } catch (_) {
            // A damaged record is skipped; subsequent valid records remain readable.
          }
        }
      }
    } finally {
      _streamFinished();
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
  /// eventually consume the complete on-device inventory without loading it.
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
          if (decoded is Map && decoded['schema'] == 1) {
            final rawShardIndex = decoded['shardIndex'];
            if (rawShardIndex is int &&
                rawShardIndex >= 0 && rawShardIndex < shardCount) {
              shardIndex = rawShardIndex;
            }
            final rawOffsets = decoded['offsets'];
            if (rawOffsets is Map) {
              for (final entry in rawOffsets.entries) {
                final key = entry.key.toString();
                final value = entry.value;
                // Cursor files are recoverable state, not trusted input. Ignore
                // malformed shard names, negative offsets and non-integral values.
                if (key.length == 2 &&
                    RegExp(r'^[0-9a-f]+$').hasMatch(key) &&
                    value is int && value >= 0) {
                  offsets[key] = value;
                }
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
        // Keep an EOF cursor at exactly `length`: a later append can then be read
        // without replaying this shard from byte zero. Reset only after truncation.
        if (offset < 0 || offset > length) offset = 0;
        var consumed = false;
        var readInShard = 0;
        var addedFromShard = 0;
        await for (final line in file.openRead(offset)
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          consumed = true;
          final nextOffset = (offset + utf8.encode(line).length + 1)
              .clamp(0, length).toInt();
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
        if (!consumed) {
          // EOF is a durable position, not a request to restart the shard.
          // If the append-only inventory grows, the next call resumes here.
          offsets[shard] = offset;
        }
        stagnantVisits = addedFromShard == 0 ? stagnantVisits + 1 : 0;
        shardIndex = (shardIndex + 1) % shardCount;
        visited++;
      }

      await _atomicReplace(cursorFile, jsonEncode(<String, Object?>{
        'schema': 1,
        'shardIndex': shardIndex,
        'offsets': offsets,
      }));
      return result;
    });
    _readQueues[path] = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  /// Compatibility API. Prefer readPreview/streamLinks for large inventories.
  static Future<List<String>> readLinks({int limit = 0x7fffffffffffffff, Directory? root}) async {
    final result = <String>[];
    if (limit <= 0) return result;
    await for (final link in streamLinks(root: root)) {
      result.add(link);
      if (result.length >= limit) break;
    }
    return result;
  }

  /// Re-reads and validates every staged record without materializing the
  /// inventory. Used before destructive snapshot swaps; unlike [count], this
  /// does not trust cached metadata.
  static Future<int> verifyCount({Directory? root}) async {
    final dir = await directory(root: root);
    await _migrateLegacy(dir);
    var total = 0;
    await for (final _ in streamLinks(root: root)) {
      total++;
    }
    return total;
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
    if (!await dirty.exists() && cached is int && cached >= 0) return cached;
    var total = 0;
    await for (final _ in streamLinks(root: root)) {
      total++;
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

  static Future<int> _appendBatch(
      Directory dir, List<String> links, {int maxAdditions = maxEntries}) async {
    if (maxAdditions <= 0) return 0;
    final grouped = <String, Map<String, String>>{};
    for (final link in links) {
      final id = _id(link);
      grouped.putIfAbsent(_shard(id), () => <String, String>{})[id] = link;
    }
    var added = 0;
    for (final group in grouped.entries) {
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
          if (added >= maxAdditions) break;
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
      if (added >= maxAdditions) break;
    }
    return added;
  }

  /// Merges lazily in small batches and never grows beyond maxEntries. RAM
  /// usage is bounded by the batch and one
  /// shard's matching identities, not by the total inventory size.
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
      if (total >= maxEntries) break;
      final link = normalizeLink(value);
      if (link == null) continue;
      batch.add(link);
      if (batch.length < _batchSize) continue;
      await File('${dir.path}/$_dirtyFileName').writeAsString('1', flush: true);
      final added = await _appendBatch(
        dir, batch, maxAdditions: maxEntries - total);
      total += added;
      batch = <String>[];
      await _writeMetadata(dir, total, source: source);
      final dirty = File('${dir.path}/$_dirtyFileName');
      if (await dirty.exists()) await dirty.delete();
    }
    if (batch.isNotEmpty && total < maxEntries) {
      await File('${dir.path}/$_dirtyFileName').writeAsString('1', flush: true);
      final added = await _appendBatch(
        dir, batch, maxAdditions: maxEntries - total);
      total += added;
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
      {String source = 'online-refresh', Directory? root, int minimumEntries = 1}) async {
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
      await _waitForStreams();
      // Recover a prior interrupted swap before preparing another snapshot.
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      } else if (await target.exists() && await backup.exists()) {
        await backup.delete(recursive: true);
      }
      if (await stageRoot.exists()) await stageRoot.delete(recursive: true);
      final total = await merge(links, source: source, root: stageRoot);
      if (total <= 0) {
        throw StateError('Fresh resource refresh produced no valid profiles; previous inventory preserved.');
      }
      final verified = await verifyCount(root: stageRoot);
      if (verified != total) {
        throw StateError('Staged resource count mismatch ($verified != $total); previous inventory preserved.');
      }
      if (total < minimumEntries) {
        throw StateError(
          'Staged snapshot is incomplete ($total < $minimumEntries); previous inventory preserved.',
        );
      }
      await target.parent.create(recursive: true);
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

  static Future<int> _countValidShardRecords(Directory dir) async {
    var total = 0;
    final shards = dir.list(followLinks: false).where((entity) =>
        entity is File && RegExp(r'^[0-9a-f]{2}\.jsonl$')
            .hasMatch(entity.uri.pathSegments.last));
    await for (final entity in shards) {
      final file = entity as File;
      final shard = file.uri.pathSegments.last.substring(0, 2);
      await for (final line in file.openRead()
          .transform(utf8.decoder).transform(const LineSplitter())) {
        try {
          final row = jsonDecode(line);
          if (row is Map && row['v'] == 1 && row['id'] is String &&
              row['link'] is String && _id(row['link'] as String) == row['id'] &&
              _shard(row['id'] as String) == shard) total++;
        } catch (_) {}
      }
    }
    return total;
  }

  static Future<void> _migrateLegacyImpl(Directory dir) async {
    final marker = File('${dir.path}/.migration_v2_done');
    if (await marker.exists()) return;
    final legacy = File('${dir.path}/$_legacyFileName');
    if (await legacy.exists()) {
      var migratedCount = await _countValidShardRecords(dir);
      var batch = <String>[];
      await for (final line in legacy.openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (migratedCount >= maxEntries) break;
        final link = normalizeLink(line);
        if (link == null) continue;
        batch.add(link);
        if (batch.length >= _batchSize) {
          migratedCount += await _appendBatch(
            dir, batch, maxAdditions: maxEntries - migratedCount);
          batch = <String>[];
        }
      }
      if (batch.isNotEmpty && migratedCount < maxEntries) {
        migratedCount += await _appendBatch(
          dir, batch, maxAdditions: maxEntries - migratedCount);
      }
      // Preserve the original source for recovery; overflow remains in .migrated.
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
          }
        } catch (_) {}
      }
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
})
            .hasMatch(entity.uri.pathSegments.last));
    await for (final entity in shards) {
      final file = entity as File;
      final shard = file.uri.pathSegments.last.substring(0, 2);
      await for (final line in file.openRead()
          .transform(utf8.decoder).transform(const LineSplitter())) {
        try {
          final row = jsonDecode(line);
          if (row is Map && row['v'] == 1 && row['id'] is String &&
              row['link'] is String && _id(row['link'] as String) == row['id'] &&
              _shard(row['id'] as String) == shard) total++;
        } catch (_) {}
      }
    }
    return total;
  }

  static Future<void> _migrateLegacyImpl(Directory dir) async {
    final marker = File('${dir.path}/.migration_v2_done');
    if (await marker.exists()) return;
    final legacy = File('${dir.path}/$_legacyFileName');
    if (await legacy.exists()) {
      var migratedCount = await _countValidShardRecords(dir);
      var batch = <String>[];
      await for (final line in legacy.openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (migratedCount >= maxEntries) break;
        final link = normalizeLink(line);
        if (link == null) continue;
        batch.add(link);
        if (batch.length >= _batchSize) {
          migratedCount += await _appendBatch(
            dir, batch, maxAdditions: maxEntries - migratedCount);
          batch = <String>[];
        }
      }
      if (batch.isNotEmpty && migratedCount < maxEntries) {
        migratedCount += await _appendBatch(
          dir, batch, maxAdditions: maxEntries - migratedCount);
      }
      // Keep the original legacy file as .migrated for recovery/audit; any
      // records beyond capacity are retained there, not silently discarded.
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
          }
        } catch (_) {}
      }
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