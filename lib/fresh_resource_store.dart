import 'dart:async';
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

  static Future<void> _writeTail = Future<void>.value();
  static const String directoryName = 'KingVPN/ResourcesFresh';
  static const String _configFileName = 'configs.txt';
  static const String _metadataFileName = 'metadata.json';

  /// Serialize mutations so overlapping refreshes cannot overwrite one another.
  static Future<T> _serializeWrite<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final previous = _writeTail;
    _writeTail = completer.future.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    previous.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
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

  /// Accept only known importable V2Ray URI schemes; reject arbitrary text.
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
    return normalizeLinks(await file.readAsLines());
  }

  static Future<List<String>> readLinks() async {
    try {
      return await _readLinksUnlocked();
    } catch (_) {
      return <String>[];
    }
  }

  /// Replaces the snapshot atomically, so an interrupted write keeps the
  /// previous usable resource file intact.
  static Future<int> _saveSnapshotUnlocked(
    Iterable<String> links, {
    required String source,
  }) async {
    final normalized = normalizeLinks(links);
    final dir = await directory();
    final file = File('${dir.path}/$_configFileName');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      normalized.join('\n') + (normalized.isEmpty ? '' : '\n'),
      flush: true,
    );
    // Rename the completed temp file over the previous snapshot. Do not
    // delete the old file first: a failed rename must leave it readable.
    await temp.rename(file.path);
    final metadata = File('${dir.path}/$_metadataFileName');
    final metadataTemp = File('${metadata.path}.tmp');
    await metadataTemp.writeAsString(jsonEncode(<String, Object>{
      'schema': 1,
      'source': source,
      'count': normalized.length,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }), flush: true);
    await metadataTemp.rename(metadata.path);
    return normalized.length;
  }

  static Future<int> saveSnapshot(
    Iterable<String> links, {
    String source = 'online',
  }) => _serializeWrite(
        () => _saveSnapshotUnlocked(links, source: source),
      );

  /// Merges newly discovered links with the existing offline cache under the
  /// same write lock, preventing two concurrent refreshes from losing updates.
  static Future<int> merge(
    Iterable<String> links, {
    String source = 'online',
  }) => _serializeWrite(() async {
        // A read failure must abort the merge, never masquerade as an empty
        // cache and overwrite previously stored resources.
        final old = await _readLinksUnlocked();
        return _saveSnapshotUnlocked(<String>[...old, ...links], source: source);
      });

  static Future<Map<String, Object?>> metadata() async {
    try {
      final file = File('${(await directory()).path}/$_metadataFileName');
      if (!await file.exists()) return <String, Object?>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {}
    return <String, Object?>{};
  }

  static Future<void> clear() => _serializeWrite(() async {
        final dir = await directory();
        final file = File('${dir.path}/$_configFileName');
        final metadata = File('${dir.path}/$_metadataFileName');
        if (await file.exists()) await file.delete();
        if (await metadata.exists()) await metadata.delete();
      });
}
