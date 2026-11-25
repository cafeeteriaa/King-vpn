import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

/// A bounded presentation page over the complete on-disk inventory.
class FreshResourcePage {
  const FreshResourcePage({
    required this.items,
    required this.offset,
    required this.hasMore,
  });

  final List<String> items;
  final int offset;
  final bool hasMore;
}

/// Persistent, app-private store for freshly downloaded public VPN profiles.
///
/// This is a durable inventory, not a reachability claim. It deliberately has
/// no application-defined entry-count or per-link byte ceiling: storage and
/// operating-system failures are surfaced to the caller rather than silently
/// converted into a shorter inventory. Callers that display a subset should
/// paginate at the presentation boundary and must not truncate this store.
class FreshResourceStore {
  FreshResourceStore._();

  static const String directoryName = 'KingVPN/ResourcesFresh';
  static const String _configFileName = 'configs.txt';
  static const String _metadataFileName = 'metadata.json';
  static const int _metadataSchema = 2;
  static Directory? _rootDirectoryForTesting;

  /// Overrides the platform directory only in tests; pass null to restore it.
  @visibleForTesting
  static void setRootDirectoryForTesting(Directory? directory) {
    _rootDirectoryForTesting = directory;
  }

  // All operations in this Dart isolate share one serialized lane. Static
  // state is isolate-local; callers in other isolates/processes need an OS-level
  // file lock before sharing this directory. A failed operation never poisons
  // the queue for later calls in this isolate.
  static Future<void> _writeTail = Future<void>.value();

  static Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _writeTail = _writeTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  static Future<Directory> directory() async {
    final root = _rootDirectoryForTesting ?? await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/$directoryName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _configFile() async =>
      File('${(await directory()).path}/$_configFileName');

  static Future<File> _metadataFile() async =>
      File('${(await directory()).path}/$_metadataFileName');

  static Future<String> get storagePath async => (await directory()).path;

  /// Accept importable V2Ray URI schemes and preserve the original payload.
  ///
  /// No fixed payload-size ceiling is imposed here. Structural validation and
  /// the downstream protocol parser remain responsible for interpreting data.
  static String? normalizeLink(String value) {
    final link = value.trim().replaceAll('\r', '');
    if (link.isEmpty || link.contains('\n')) return null;
    final separator = link.indexOf('://');
    if (separator <= 0) return null;
    final scheme = link.substring(0, separator).toLowerCase();
    const supported = <String>{
      'vless',
      'vmess',
      'trojan',
      'ss',
      'hysteria2',
      'hy2',
      'tuic',
    };
    if (!supported.contains(scheme)) return null;
    return link;
  }

  /// Normalize and deduplicate the complete iterable.
  ///
  /// This method intentionally does not stop at a fixed number of results.
  /// It is a convenience for callers with in-memory inputs; large imports
  /// should be streamed/chunked by their source adapter before reaching it.
  static List<String> normalizeLinks(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final link = normalizeLink(value);
      if (link == null) continue;
      final key = link.toLowerCase();
      if (seen.add(key)) result.add(link);
    }
    return result;
  }

  static Future<List<String>> _readLinksUnlocked() async {
    final file = await _configFile();
    if (!await file.exists()) return <String>[];
    final result = <String>[];
    final seen = <String>{};
    // Read line-by-line rather than readAsLines so the file is not duplicated
    // as both one giant String and a List<String> during recovery.
    await for (final line in file.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      final link = normalizeLink(line);
      if (link != null && seen.add(link.toLowerCase())) result.add(link);
    }
    return result;
  }

  /// Read one window without materializing the complete inventory.
  ///
  /// The file is scanned sequentially, so memory use is proportional to the
  /// requested page rather than the total number of stored records. A future
  /// disk index can accelerate deep offsets without changing this API.
  static Future<FreshResourcePage> readPage({
    int offset = 0,
    int limit = 100,
  }) {
    if (offset < 0) {
      return Future<FreshResourcePage>.error(
        ArgumentError.value(offset, 'offset', 'Must be zero or greater'),
      );
    }
    if (limit < 1) {
      return Future<FreshResourcePage>.error(
        ArgumentError.value(limit, 'limit', 'Must be greater than zero'),
      );
    }
    return _serialized<FreshResourcePage>(() async {
      final file = await _configFile();
      if (!await file.exists()) {
        return FreshResourcePage(
          items: const <String>[],
          offset: offset,
          hasMore: false,
        );
      }
      final items = <String>[];
      var validIndex = 0;
      var hasMore = false;
      await for (final line in file
          .openRead()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())) {
        final link = normalizeLink(line);
        if (link == null) continue;
        if (validIndex < offset) {
          validIndex++;
          continue;
        }
        if (items.length == limit) {
          hasMore = true;
          break;
        }
        items.add(link);
        validIndex++;
      }
      return FreshResourcePage(
        items: List<String>.unmodifiable(items),
        offset: offset,
        hasMore: hasMore,
      );
    });
  }

  /// Read the full inventory. I/O and decoding errors are deliberately visible
  /// so callers can distinguish an empty inventory from a failed read.
  static Future<List<String>> readLinks() =>
      _serialized<List<String>>(_readLinksUnlocked);

  static Future<Map<String, int>> _writeSnapshotFile(
    File target,
    Stream<String> input,
  ) async {
    final temp = File(
      '${target.path}.tmp-${pid}-${DateTime.now().microsecondsSinceEpoch}',
    );
    IOSink? sink;
    final seen = <String>{};
    var count = 0;
    var byteCount = 0;
    try {
      sink = temp.openWrite();
      final output = sink;
      // Stream source records directly to the temporary file. Only the
      // deduplication keys remain resident; payload strings are not assembled
      // into a second full-size snapshot in memory.
      await for (final value in input) {
        final link = normalizeLink(value);
        if (link == null || !seen.add(link.toLowerCase())) continue;
        final line = '$link\n';
        output.write(line);
        byteCount += utf8.encode(line).length;
        count++;
      }
      await output.flush();
      await output.close();
      sink = null;
      // Same-directory rename is atomic on Android/Linux. Never delete the
      // current snapshot first: a failed replacement must leave it intact.
      await temp.rename(target.path);
      return <String, int>{'count': count, 'bytes': byteCount};
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {
        // Keep the original write/rename error.
      }
      rethrow;
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } on FileSystemException {
        // Best-effort cleanup must not mask the write/rename failure.
      }
    }
  }

  static Future<int> _saveSnapshotUnlocked(
    Stream<String> links, {
    required String source,
  }) async {
    final file = await _configFile();
    final written = await _writeSnapshotFile(file, links);

    final metadata = await _metadataFile();
    final metadataPayload = <String, Object>{
      'schema': _metadataSchema,
      'source': source,
      'count': written['count']!,
      'bytes': written['bytes']!,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _replaceMetadata(metadata, utf8.encode(jsonEncode(metadataPayload)));
    return written['count']!;
  }

  static Future<void> _replaceMetadata(File target, List<int> bytes) async {
    final temp = File(
      '${target.path}.tmp-${pid}-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target.path);
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } on FileSystemException {
        // Best-effort cleanup must not mask the metadata write/rename failure.
      }
    }
  }

  /// Replace the complete snapshot without a silent count/size truncation.
  static Future<int> saveSnapshot(
    Iterable<String> links, {
    String source = 'online',
  }) =>
      saveSnapshotStream(Stream<String>.fromIterable(links), source: source);

  /// Stream-based replacement entry point for large/network-backed imports.
  /// The caller retains ownership of the stream until this Future completes.
  static Future<int> saveSnapshotStream(
    Stream<String> links, {
    String source = 'online',
  }) =>
      _serialized<int>(() => _saveSnapshotUnlocked(links, source: source));

  /// Merge is one serialized streaming read-modify-write transaction.
  /// Existing entries are copied from disk before new entries; concurrent
  /// source completions cannot overwrite one another's additions.
  static Future<int> merge(
    Iterable<String> links, {
    String source = 'online',
  }) =>
      mergeStream(Stream<String>.fromIterable(links), source: source);

  /// Stream-based merge avoids requiring the source adapter to materialize
  /// every discovered profile in a second in-memory collection.
  static Future<int> mergeStream(
    Stream<String> links, {
    String source = 'online',
  }) =>
      _serialized<int>(() async {
        final current = await _configFile();
        Stream<String> merged() async* {
          if (await current.exists()) {
            await for (final line in current
                .openRead()
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
              yield line;
            }
          }
          yield* links;
        }

        return _saveSnapshotUnlocked(merged(), source: source);
      });

  static Future<Map<String, Object?>> metadata() =>
      _serialized<Map<String, Object?>>(() async {
        final file = await _metadataFile();
        if (!await file.exists()) return <String, Object?>{};
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) {
          throw const FormatException('Resource metadata must be a JSON object');
        }
        final result = Map<String, Object?>.from(decoded);
        // Schema 1 snapshots remain readable; fields added in schema 2 are
        // optional for old installations and are not fabricated on read.
        return result;
      });

  static Future<void> clear() => _serialized<void>(() async {
        final file = await _configFile();
        final metadata = await _metadataFile();
        if (await file.exists()) await file.delete();
        if (await metadata.exists()) await metadata.delete();
      });
}
