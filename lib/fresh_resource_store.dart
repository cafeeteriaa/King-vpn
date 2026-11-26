import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persistent, app-private store for freshly downloaded public VPN profiles.
///
/// The store is deliberately separate from the personal-server folder and
/// from the national-network IP inventory. It is a reusable cache of config
/// links, not a claim that a cached endpoint is currently reachable.
class FreshResourceStore {
  FreshResourceStore._();

  static const String directoryName = 'KingVPN/ResourcesFresh';
  static const String _configFileName = 'configs.txt';
  static const String _metadataFileName = 'metadata.json';

  // Serialize all mutations so concurrent imports and clears cannot overwrite
  // one another or race on the same temporary file.
  static Future<void> _mutationQueue = Future<void>.value();

  static Future<T> _serializeMutation<T>(
    Future<T> Function() action,
  ) {
    final operation = _mutationQueue.then<T>((_) => action());
    _mutationQueue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return operation;
  }

  static Future<Directory> directory() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/$directoryName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _configFile() async =>
      File('${(await directory()).path}/$_configFileName');

  static Future<String> get storagePath async => (await directory()).path;

  /// Accept supported importable V2Ray URI schemes without an arbitrary
  /// per-link size ceiling. Unsupported schemes remain rejected.
  static String? normalizeLink(String value) {
    final link = value.trim().replaceAll('\\r', '');
    if (link.isEmpty) return null;
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

  /// Deduplicates supported links while retaining every distinct entry.
  /// Available device storage is the natural persistence boundary.
  static List<String> normalizeLinks(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final link = normalizeLink(value);
      if (link == null) continue;
      if (seen.add(link.toLowerCase())) result.add(link);
    }
    return result;
  }

  static Future<List<String>> _readLinksUnlocked() async {
    final file = await _configFile();
    if (!await file.exists()) return <String>[];
    return normalizeLinks(await file.readAsLines());
  }

  static Future<List<String>> readLinks() async {
    try {
      // Readers see the previous or next complete snapshot, never a partially
      // written file, because writers replace the file using same-dir rename.
      return await _readLinksUnlocked();
    } catch (_) {
      return <String>[];
    }
  }

  static Future<void> _writeAtomically(File target, String contents) async {
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(contents, flush: true);
    // On Android, same-directory rename atomically replaces the destination.
    // If rename fails, the previous file remains intact.
    await temp.rename(target.path);
  }

  static Future<int> _saveSnapshotUnlocked(
    Iterable<String> links, {
    required String source,
  }) async {
    final normalized = normalizeLinks(links);
    final file = await _configFile();
    await _writeAtomically(
      file,
      normalized.join('\\n') + (normalized.isEmpty ? '' : '\\n'),
    );

    final metadata = File('${(await directory()).path}/$_metadataFileName');
    final metadataJson = jsonEncode(<String, Object>{
      'schema': 1,
      'source': source,
      'count': normalized.length,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _writeAtomically(metadata, metadataJson);
    return normalized.length;
  }

  static Future<int> saveSnapshot(
    Iterable<String> links, {
    String source = 'online',
  }) {
    return _serializeMutation(
      () => _saveSnapshotUnlocked(links, source: source),
    );
  }

  /// The complete read/merge/write operation is serialized as one transaction,
  /// preventing simultaneous imports from losing each other's additions.
  static Future<int> merge(
    Iterable<String> links, {
    String source = 'online',
  }) {
    return _serializeMutation(() async {
      final old = await _readLinksUnlocked();
      return _saveSnapshotUnlocked(<String>[...old, ...links], source: source);
    });
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

  /// Clears only this cache; personal servers and national IP data are separate.
  static Future<void> clear() {
    return _serializeMutation(() async {
      final file = await _configFile();
      if (await file.exists()) await file.delete();
      final metadata =
          File('${(await directory()).path}/$_metadataFileName');
      if (await metadata.exists()) await metadata.delete();
    });
  }
}
