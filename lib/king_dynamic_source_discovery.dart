import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Runtime discovery of additional public Xray/V2Ray subscription feeds.
///
/// The curated feeds remain the fast path. This service expands the inventory
/// from public GitHub repositories without trusting repository metadata as a
/// server configuration: every returned feed is still parsed by Server.parse
/// and every server must pass the existing real-core/data-plane verification.
class KingDynamicSourceDiscovery {
  KingDynamicSourceDiscovery._();

  static const _cacheKey = 'king_dynamic_sources_v2';
  static const _updatedKey = 'king_dynamic_sources_updated_v2';
  static const _ttl = Duration(hours: 12);
  static const _maxRepos = 24;
  static const _maxFiles = 48;
  static const _maxFileBytes = 1500000;
  static const _api = 'https://api.github.com';
  static bool _refreshing = false;

  static bool isCandidatePath(String path, {int? size}) {
    final p = path.toLowerCase();
    if (size != null && (size <= 0 || size > _maxFileBytes)) return false;
    if (p.startsWith('.') || RegExp(r'(^|/)(\.github|docs)(/|$)').hasMatch(p)) {
      return false;
    }
    if (RegExp(r'(^|/)(readme|license|changelog|contributing)(\.|$)').hasMatch(p)) {
      return false;
    }
    if (!RegExp(r'\.(txt|yaml|yml|json|conf|sub)$').hasMatch(p)) return false;
    final name = p.split('/').last;
    return RegExp(r'(sub|config|proxy|v2ray|xray|node|server|all|mix)')
        .hasMatch(name);
  }

  static String? normalizeFeedUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'raw.githubusercontent.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length < 4) {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.any((s) => s == '.' || s == '..' || s.isEmpty)) return null;
    return uri.toString();
  }

  static Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/king_dynamic_sources_v2.json');
  }

  static Future<Map<String, dynamic>> _readCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return <String, dynamic>{};
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Returns cached feeds immediately; callers can schedule refresh separately.
  static Future<List<String>> cachedFeeds() async {
    final decoded = await _readCache();
    final feeds = decoded['feeds'];
    if (feeds is! List) return const <String>[];
    return feeds
        .whereType<String>()
        .map(normalizeFeedUrl)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
  }

  static Future<void> refresh({bool Function()? shouldStop}) async {
    if (_refreshing || (shouldStop?.call() ?? false)) return;
    _refreshing = true;
    final client = http.Client();
    try {
      final oldCache = await _readCache();
      final last = oldCache['updatedAt'] is num ? (oldCache['updatedAt'] as num).toInt() : 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < _ttl.inMilliseconds) return;

      final searchUri = Uri.parse(
        '$_api/search/repositories?q=v2ray+subscription+config&sort=updated&order=desc&per_page=$_maxRepos',
      );
      final search = await client
          .get(searchUri, headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (search.statusCode != 200 || (shouldStop?.call() ?? false)) return;
      final searchJson = jsonDecode(search.body);
      final items = searchJson is Map ? searchJson['items'] : null;
      if (items is! List) return;

      final repos = <({String fullName, String branch})>[];
      for (final item in items) {
        if (item is! Map) continue;
        final fullName = item['full_name'];
        final branch = item['default_branch'];
        if (fullName is! String ||
            branch is! String ||
            !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(fullName) ||
            !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(branch)) {
          continue;
        }
        repos.add((fullName: fullName, branch: branch));
      }

      final found = <String>{};
      var nextRepo = 0;
      Future<void> worker() async {
        while (nextRepo < repos.length &&
            found.length < _maxFiles &&
            !(shouldStop?.call() ?? false)) {
          final repo = repos[nextRepo++];
          try {
            final treeUri = Uri.parse(
              '$_api/repos/${repo.fullName}/git/trees/${Uri.encodeComponent(repo.branch)}?recursive=1',
            );
            final response = await client
                .get(treeUri, headers: _headers)
                .timeout(const Duration(seconds: 5));
            if (response.statusCode != 200) continue;
            final treeJson = jsonDecode(response.body);
            final entries = treeJson is Map ? treeJson['tree'] : null;
            if (entries is! List) continue;
            final candidates = <({String path, int size})>[];
            for (final entry in entries) {
              if (entry is! Map || entry['type'] != 'blob') continue;
              final path = entry['path'];
              final size = entry['size'];
              if (path is String &&
                  size is num &&
                  isCandidatePath(path, size: size.toInt())) {
                candidates.add((path: path, size: size.toInt()));
              }
            }
            candidates.sort((a, b) {
              final scoreA = _pathScore(a.path);
              final scoreB = _pathScore(b.path);
              return scoreB.compareTo(scoreA);
            });
            for (final candidate in candidates.take(2)) {
              final encodedPath = candidate.path
                  .split('/')
                  .map(Uri.encodeComponent)
                  .join('/');
              final url = normalizeFeedUrl(
                'https://raw.githubusercontent.com/${repo.fullName}/${Uri.encodeComponent(repo.branch)}/$encodedPath',
              );
              if (url != null) found.add(url);
              if (found.length >= _maxFiles) break;
            }
          } catch (_) {
            // One unavailable or malformed repository must not abort discovery.
          }
        }
      }

      await Future.wait(List.generate(4, (_) => worker()));
      if (shouldStop?.call() ?? false) return;
      if (found.isNotEmpty) {
        final previous = await cachedFeeds();
        final merged = <String>{...found, ...previous}.take(_maxFiles).toList();
        final file = await _cacheFile();
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(
          jsonEncode(<String, dynamic>{'updatedAt': now, 'feeds': merged}),
          flush: true,
        );
        await temp.rename(file.path);
      }
    } catch (_) {
      // Preserve the last known-good source inventory on all discovery errors.
    } finally {
      client.close();
      _refreshing = false;
    }
  }

  static const Map<String, String> _headers = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'KING-VPN-Dynamic-Source-Discovery',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  static int _pathScore(String path) {
    final p = path.toLowerCase();
    var score = 0;
    if (p.contains('all') || p.contains('mix')) score += 5;
    if (p.contains('sub')) score += 4;
    if (p.contains('vless') || p.contains('vmess') || p.contains('trojan')) {
      score += 3;
    }
    if (p.contains('config') || p.contains('proxy')) score += 2;
    return score;
  }
}
