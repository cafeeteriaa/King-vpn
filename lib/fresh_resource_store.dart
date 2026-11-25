import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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

  // All mutations and snapshots share one serialized lane. The tail itself
  // never remains failed, so one failed write cannot poison later operations.
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
    final root = await getApplicationSupportDirectory();
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
    if (link.isEmpty) return null;
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

  /// Read the full inventory. I/O and decoding errors are deliberately visible
  /// so callers can distinguish an empty inventory from a failed read.
  static Future<List<String>> readLinks() =>
      _serialized<List<String>>(_readLinksUnlocked);

  static Future<void> _replaceFile(File target, List<int> bytes) async {
    final temp = File(
      '${target.path}.tmp-${pid}-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      // On Android/Linux rename within the same directory is an atomic replace.
      // If the platform rejects replacement, retain the old target and surface
      // the failure instead of deleting the only known-good snapshot.
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) {
        try {
          await temp.delete();
        } on FileSystemException {
          // Preserve the original operation's error.
        }
      }
    }
  }

  static Future<int> _saveSnapshotUnlocked(
    Iterable<String> links, {
    required String source,
  }) async {
    final normalized = normalizeLinks(links);
    final file = await _configFile();
    final payload = normalized.isEmpty
        ? ''
        : '${normalized.join('\n')}\n';
    await _replaceFile(file, utf8.encode(payload));

    final metadata = await _metadataFile();
    final metadataPayload = <String, Object>{
      'schema': _metadataSchema,
      'source': source,
      'count': normalized.length,
      'bytes': utf8.encode(payload).length,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _replaceFile(metadata, utf8.encode(jsonEncode(metadataPayload)));
    return normalized.length;
  }

  /// Replace the complete snapshot without a silent count/size truncation.
  static Future<int> saveSnapshot(
    Iterable<String> links, {
    String source = 'online',
  }) =>
      _serialized<int>(() => _saveSnapshotUnlocked(links, source: source));

  /// Merge is one serialized read-modify-write transaction. Concurrent source
  /// completions therefore cannot overwrite one another's additions.
  static Future<int> merge(
    Iterable<String> links, {
    String source = 'online',
  }) =>
      _serialized<int>(() async {
        final old = await _readLinksUnlocked();
        return _saveSnapshotUnlocked(<String>[...old, ...links], source: source);
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
