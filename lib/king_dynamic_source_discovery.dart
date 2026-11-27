import 'dart:convert';

import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:path_provider/path_provider.dart';

/// Runtime discovery of additional public Xray/V2Ray subscription feeds.
///
/// The curated feeds remain the fast path. This service expands the inventory
/// from public GitHub repositories without trusting repository metadata as a
/// server configuration: every returned feed is still parsed by Server.parse
/// and every server must pass the existing real-core/data-plane verification.
class KingDynamicSourceDiscovery {
  KingDynamicSourceDiscovery._();

  static const _ttl = Duration(hours: 12);
  static const _retryDelay = Duration(minutes: 15);
  static const _pageSize = 100;
  static const _maxTreeResponseChars = 8 * 1024 * 1024;
  static const _maxFileBytes = 1500000;
  static const _cycleBudget = Duration(minutes: 2);
  static const _api = 'https://api.github.com';
  static const _searchQueries = <String>[
    'v2ray subscription config',
    'xray subscription config',
    'vless vmess trojan config',
    'shadowsocks subscription proxy',
    'vpn proxy nodes subscription',
  ];
  static bool _refreshing = false;

  static bool isCandidatePath(String path, {int? size}) {
    final p = path.toLowerCase();
    final segments = p.split('/');
    if (segments.any((segment) =>
        segment.isEmpty || segment == '.' || segment == '..' ||
        segment.startsWith('.'))) return false;
    if (size != null && (size <= 0 || size > _maxFileBytes)) return false;
    if (RegExp(r'(^|/)docs(/|$)').hasMatch(p)) return false;
    if (RegExp(r'(^|/)(readme|license|changelog|contributing)(\.|$)').hasMatch(p)) {
      return false;
    }
    if (!RegExp(r'\.(txt|yaml|yml|json|conf|sub)$').hasMatch(p)) return false;
    final name = p.split('/').last;
    return RegExp(r'(sub|config|proxy|v2ray|xray|node|server|all|mix)')
        .hasMatch(name);
  }

  static bool isSafeGitRef(String ref) {
    final segments = ref.split('/');
    return segments.isNotEmpty && segments.every((segment) =>
        segment.isNotEmpty &&
        segment != '.' &&
        segment != '..' &&
        RegExp(r'^[A-Za-z0-9_.-]+
    const prefix = 'https://raw.githubusercontent.com/';
    if (!value.startsWith(prefix)) return null;
    final rawPath = value.substring(prefix.length).split(RegExp(r'[?#]')).first;
    try {
      final segments = rawPath.split('/').map(Uri.decodeComponent).toList();
      if (segments.length < 4 || segments.any((s) =>
          s.isEmpty || s == '.' || s == '..' || s.contains('/') || s.contains(String.fromCharCode(92)))) {
        return null;
      }
    } catch (_) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' ||
        uri.host != 'raw.githubusercontent.com' || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment || uri.pathSegments.length < 4) {
      return null;
    }
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
      final lastAttempt = oldCache['lastAttemptAt'] is num
          ? (oldCache['lastAttemptAt'] as num).toInt()
          : 0;
      if (now - last < _ttl.inMilliseconds ||
          now - lastAttempt < _retryDelay.inMilliseconds) return;

      final stopwatch = Stopwatch()..start();
      var page = oldCache['nextPage'] is num
          ? (oldCache['nextPage'] as num).toInt()
          : 1;
      var queryIndex = oldCache['nextQuery'] is num
          ? (oldCache['nextQuery'] as num).toInt()
          : 0;
      if (page < 1 || page > 10) page = 1;
      if (queryIndex < 0 || queryIndex >= _searchQueries.length) queryIndex = 0;
      var cycleCompleted = false;
      final found = <String>{};

      // GitHub Search exposes up to 1,000 results per query. Walk its pages
      // incrementally; there is deliberately no fixed repository/feed count.
      // A two-minute background budget and four workers bound resource use.
      while (stopwatch.elapsed < _cycleBudget &&
          !(shouldStop?.call() ?? false)) {
        final query = Uri.encodeQueryComponent(_searchQueries[queryIndex]);
        final searchUri = Uri.parse(
          '$_api/search/repositories?q=$query&sort=updated&order=desc&per_page=$_pageSize&page=$page',
        );
        final search = await client
            .get(searchUri, headers: _headers)
            .timeout(const Duration(seconds: 5));
        if (search.statusCode != 200 || search.body.length > 1024 * 1024) {
          break;
        }
        final searchJson = jsonDecode(search.body);
        final items = searchJson is Map ? searchJson['items'] : null;
        if (items is! List) break;
        if (items.isEmpty) {
          page = 1;
          queryIndex++;
          if (queryIndex >= _searchQueries.length) {
            queryIndex = 0;
            cycleCompleted = true;
            break;
          }
          continue;
        }

        final repos = <({String fullName, String branch})>[];
        for (final item in items) {
          if (item is! Map) continue;
          final fullName = item['full_name'];
          final branchName = item['default_branch'];
          if (fullName is! String ||
              branchName is! String ||
              !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+
          repos.add((fullName: fullName, branch: branchName));
        }

        var nextRepo = 0;
        Future<void> worker() async {
          while (nextRepo < repos.length &&
              stopwatch.elapsed < _cycleBudget &&
              !(shouldStop?.call() ?? false)) {
            final repo = repos[nextRepo++];
            try {
              final treeUri = Uri.parse(
                '$_api/repos/${repo.fullName}/git/trees/${Uri.encodeComponent(repo.branch)}?recursive=1',
              );
              final response = await client
                  .get(treeUri, headers: _headers)
                  .timeout(const Duration(seconds: 5));
              if (response.statusCode != 200 ||
                  response.body.length > _maxTreeResponseChars) {
                continue;
              }
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
              candidates.sort((a, b) =>
                  _pathScore(b.path).compareTo(_pathScore(a.path)));
              for (final candidate in candidates) {
                final encodedPath = candidate.path
                    .split('/')
                    .map(Uri.encodeComponent)
                    .join('/');
                final rawBranch = repo.branch
                    .split('/')
                    .map(Uri.encodeComponent)
                    .join('/');
                final url = normalizeFeedUrl(
                  'https://raw.githubusercontent.com/${repo.fullName}/$rawBranch/$encodedPath',
                );
                if (url != null) found.add(url);
              }
            } catch (_) {
              // A malformed, unavailable, or rate-limited repository is isolated.
            }
          }
        }

        await Future.wait(List.generate(4, (_) => worker()));
        if (shouldStop?.call() ?? false) return;
        if (nextRepo < repos.length) break; // Resume this page next cycle.
        page++;
        if (page > 10) {
          page = 1;
          queryIndex++;
          if (queryIndex >= _searchQueries.length) {
            queryIndex = 0;
            cycleCompleted = true;
            break;
          }
        }
      }
      if (shouldStop?.call() ?? false) return;
      final previous = await cachedFeeds();
      final merged = <String>{...found, ...previous}.toList(growable: false);
      final file = await _cacheFile();
      final temp = File(file.path + '.tmp');
      await temp.writeAsString(
        jsonEncode(<String, dynamic>{
          'updatedAt': cycleCompleted ? now : last,
          'lastAttemptAt': now,
          'nextPage': page,
          'nextQuery': queryIndex,
          'feeds': merged,
        }),
        flush: true,
      );
      await temp.rename(file.path);
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
).hasMatch(segment));
  }

  static String? normalizeFeedUrl(String value) {
    const prefix = 'https://raw.githubusercontent.com/';
    if (!value.startsWith(prefix)) return null;
    final rawPath = value.substring(prefix.length).split(RegExp(r'[?#]')).first;
    try {
      final segments = rawPath.split('/').map(Uri.decodeComponent).toList();
      if (segments.length < 4 || segments.any((s) =>
          s.isEmpty || s == '.' || s == '..' || s.contains('/') || s.contains(String.fromCharCode(92)))) {
        return null;
      }
    } catch (_) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' ||
        uri.host != 'raw.githubusercontent.com' || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment || uri.pathSegments.length < 4) {
      return null;
    }
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
      final lastAttempt = oldCache['lastAttemptAt'] is num
          ? (oldCache['lastAttemptAt'] as num).toInt()
          : 0;
      if (now - last < _ttl.inMilliseconds ||
          now - lastAttempt < _retryDelay.inMilliseconds) return;

      final stopwatch = Stopwatch()..start();
      var page = oldCache['nextPage'] is num
          ? (oldCache['nextPage'] as num).toInt()
          : 1;
      var queryIndex = oldCache['nextQuery'] is num
          ? (oldCache['nextQuery'] as num).toInt()
          : 0;
      if (page < 1 || page > 10) page = 1;
      if (queryIndex < 0 || queryIndex >= _searchQueries.length) queryIndex = 0;
      var cycleCompleted = false;
      final found = <String>{};

      // GitHub Search exposes up to 1,000 results per query. Walk its pages
      // incrementally; there is deliberately no fixed repository/feed count.
      // A two-minute background budget and four workers bound resource use.
      while (stopwatch.elapsed < _cycleBudget &&
          !(shouldStop?.call() ?? false)) {
        final query = Uri.encodeQueryComponent(_searchQueries[queryIndex]);
        final searchUri = Uri.parse(
          '$_api/search/repositories?q=$query&sort=updated&order=desc&per_page=$_pageSize&page=$page',
        );
        final search = await client
            .get(searchUri, headers: _headers)
            .timeout(const Duration(seconds: 5));
        if (search.statusCode != 200 || search.body.length > 1024 * 1024) {
          break;
        }
        final searchJson = jsonDecode(search.body);
        final items = searchJson is Map ? searchJson['items'] : null;
        if (items is! List) break;
        if (items.isEmpty) {
          page = 1;
          queryIndex++;
          if (queryIndex >= _searchQueries.length) {
            queryIndex = 0;
            cycleCompleted = true;
            break;
          }
          continue;
        }

        final repos = <({String fullName, String branch})>[];
        for (final item in items) {
          if (item is! Map) continue;
          final fullName = item['full_name'];
          final branchName = item['default_branch'];
          if (fullName is! String ||
              branchName is! String ||
              !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')
                  .hasMatch(fullName) ||
              !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(branchName)) {
            continue;
          }
          repos.add((fullName: fullName, branch: branchName));
        }

        var nextRepo = 0;
        Future<void> worker() async {
          while (nextRepo < repos.length &&
              stopwatch.elapsed < _cycleBudget &&
              !(shouldStop?.call() ?? false)) {
            final repo = repos[nextRepo++];
            try {
              final treeUri = Uri.parse(
                '$_api/repos/${repo.fullName}/git/trees/${Uri.encodeComponent(repo.branch)}?recursive=1',
              );
              final response = await client
                  .get(treeUri, headers: _headers)
                  .timeout(const Duration(seconds: 5));
              if (response.statusCode != 200 ||
                  response.body.length > _maxTreeResponseChars) {
                continue;
              }
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
              candidates.sort((a, b) =>
                  _pathScore(b.path).compareTo(_pathScore(a.path)));
              for (final candidate in candidates) {
                final encodedPath = candidate.path
                    .split('/')
                    .map(Uri.encodeComponent)
                    .join('/');
                final url = normalizeFeedUrl(
                  'https://raw.githubusercontent.com/${repo.fullName}/${Uri.encodeComponent(repo.branch)}/$encodedPath',
                );
                if (url != null) found.add(url);
              }
            } catch (_) {
              // A malformed, unavailable, or rate-limited repository is isolated.
            }
          }
        }

        await Future.wait(List.generate(4, (_) => worker()));
        if (shouldStop?.call() ?? false) return;
        if (nextRepo < repos.length) break; // Resume this page next cycle.
        page++;
        if (page > 10) {
          page = 1;
          queryIndex++;
          if (queryIndex >= _searchQueries.length) {
            queryIndex = 0;
            cycleCompleted = true;
            break;
          }
        }
      }
      if (shouldStop?.call() ?? false) return;
      final previous = await cachedFeeds();
      final merged = <String>{...found, ...previous}.toList(growable: false);
      final file = await _cacheFile();
      final temp = File(file.path + '.tmp');
      await temp.writeAsString(
        jsonEncode(<String, dynamic>{
          'updatedAt': cycleCompleted ? now : last,
          'lastAttemptAt': now,
          'nextPage': page,
          'nextQuery': queryIndex,
          'feeds': merged,
        }),
        flush: true,
      );
      await temp.rename(file.path);
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
)
                  .hasMatch(fullName) ||
              !isSafeGitRef(branchName)) {
            continue;
          }
          repos.add((fullName: fullName, branch: branchName));
        }

        var nextRepo = 0;
        Future<void> worker() async {
          while (nextRepo < repos.length &&
              stopwatch.elapsed < _cycleBudget &&
              !(shouldStop?.call() ?? false)) {
            final repo = repos[nextRepo++];
            try {
              final treeUri = Uri.parse(
                '$_api/repos/${repo.fullName}/git/trees/${Uri.encodeComponent(repo.branch)}?recursive=1',
              );
              final response = await client
                  .get(treeUri, headers: _headers)
                  .timeout(const Duration(seconds: 5));
              if (response.statusCode != 200 ||
                  response.body.length > _maxTreeResponseChars) {
                continue;
              }
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
              candidates.sort((a, b) =>
                  _pathScore(b.path).compareTo(_pathScore(a.path)));
              for (final candidate in candidates) {
                final encodedPath = candidate.path
                    .split('/')
                    .map(Uri.encodeComponent)
                    .join('/');
                final url = normalizeFeedUrl(
                  'https://raw.githubusercontent.com/${repo.fullName}/${Uri.encodeComponent(repo.branch)}/$encodedPath',
                );
                if (url != null) found.add(url);
              }
            } catch (_) {
              // A malformed, unavailable, or rate-limited repository is isolated.
            }
          }
        }

        await Future.wait(List.generate(4, (_) => worker()));
        if (shouldStop?.call() ?? false) return;
        if (nextRepo < repos.length) break; // Resume this page next cycle.
        page++;
        if (page > 10) {
          page = 1;
          queryIndex++;
          if (queryIndex >= _searchQueries.length) {
            queryIndex = 0;
            cycleCompleted = true;
            break;
          }
        }
      }
      if (shouldStop?.call() ?? false) return;
      final previous = await cachedFeeds();
      final merged = <String>{...found, ...previous}.toList(growable: false);
      final file = await _cacheFile();
      final temp = File(file.path + '.tmp');
      await temp.writeAsString(
        jsonEncode(<String, dynamic>{
          'updatedAt': cycleCompleted ? now : last,
          'lastAttemptAt': now,
          'nextPage': page,
          'nextQuery': queryIndex,
          'feeds': merged,
        }),
        flush: true,
      );
      await temp.rename(file.path);
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
).hasMatch(segment));
  }

  static String? normalizeFeedUrl(String value) {
    const prefix = 'https://raw.githubusercontent.com/';
    if (!value.startsWith(prefix)) return null;
    final rawPath = value.substring(prefix.length).split(RegExp(r'[?#]')).first;
    try {
      final segments = rawPath.split('/').map(Uri.decodeComponent).toList();
      if (segments.length < 4 || segments.any((s) =>
          s.isEmpty || s == '.' || s == '..' || s.contains('/') || s.contains(String.fromCharCode(92)))) {
        return null;
      }
    } catch (_) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' ||
        uri.host != 'raw.githubusercontent.com' || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment || uri.pathSegments.length < 4) {
      return null;
    }
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
      final lastAttempt = oldCache['lastAttemptAt'] is num
          ? (oldCache['lastAttemptAt'] as num).toInt()
          : 0;
      if (now - last < _ttl.inMilliseconds ||
          now - lastAttempt < _retryDelay.inMilliseconds) return;

      final stopwatch = Stopwatch()..start();
      var page = oldCache['nextPage'] is num
          ? (oldCache['nextPage'] as num).toInt()
          : 1;
      var queryIndex = oldCache['nextQuery'] is num
          ? (oldCache['nextQuery'] as num).toInt()
          : 0;
      if (page < 1 || page > 10) page = 1;
      if (queryIndex < 0 || queryIndex >= _searchQueries.length) queryIndex = 0;
      var cycleCompleted = false;
      final found = <String>{};

      // GitHub Search exposes up to 1,000 results per query. Walk its pages
      // incrementally; there is deliberately no fixed repository/feed count.
      // A two-minute background budget and four workers bound resource use.
      while (stopwatch.elapsed < _cycleBudget &&
          !(shouldStop?.call() ?? false)) {
        final query = Uri.encodeQueryComponent(_searchQueries[queryIndex]);
        final searchUri = Uri.parse(
          '$_api/search/repositories?q=$query&sort=updated&order=desc&per_page=$_pageSize&page=$page',
        );
        final search = await client
            .get(searchUri, headers: _headers)
            .timeout(const Duration(seconds: 5));
        if (search.statusCode != 200 || search.body.length > 1024 * 1024) {
          break;
        }
        final searchJson = jsonDecode(search.body);
        final items = searchJson is Map ? searchJson['items'] : null;
        if (items is! List) break;
        if (items.isEmpty) {
          page = 1;
          queryIndex++;
          if (queryIndex >= _searchQueries.length) {
            queryIndex = 0;
            cycleCompleted = true;
            break;
          }
          continue;
        }

        final repos = <({String fullName, String branch})>[];
        for (final item in items) {
          if (item is! Map) continue;
          final fullName = item['full_name'];
          final branchName = item['default_branch'];
          if (fullName is! String ||
              branchName is! String ||
              !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')
                  .hasMatch(fullName) ||
              !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(branchName)) {
            continue;
          }
          repos.add((fullName: fullName, branch: branchName));
        }

        var nextRepo = 0;
        Future<void> worker() async {
          while (nextRepo < repos.length &&
              stopwatch.elapsed < _cycleBudget &&
              !(shouldStop?.call() ?? false)) {
            final repo = repos[nextRepo++];
            try {
              final treeUri = Uri.parse(
                '$_api/repos/${repo.fullName}/git/trees/${Uri.encodeComponent(repo.branch)}?recursive=1',
              );
              final response = await client
                  .get(treeUri, headers: _headers)
                  .timeout(const Duration(seconds: 5));
              if (response.statusCode != 200 ||
                  response.body.length > _maxTreeResponseChars) {
                continue;
              }
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
              candidates.sort((a, b) =>
                  _pathScore(b.path).compareTo(_pathScore(a.path)));
              for (final candidate in candidates) {
                final encodedPath = candidate.path
                    .split('/')
                    .map(Uri.encodeComponent)
                    .join('/');
                final url = normalizeFeedUrl(
                  'https://raw.githubusercontent.com/${repo.fullName}/${Uri.encodeComponent(repo.branch)}/$encodedPath',
                );
                if (url != null) found.add(url);
              }
            } catch (_) {
              // A malformed, unavailable, or rate-limited repository is isolated.
            }
          }
        }

        await Future.wait(List.generate(4, (_) => worker()));
        if (shouldStop?.call() ?? false) return;
        if (nextRepo < repos.length) break; // Resume this page next cycle.
        page++;
        if (page > 10) {
          page = 1;
          queryIndex++;
          if (queryIndex >= _searchQueries.length) {
            queryIndex = 0;
            cycleCompleted = true;
            break;
          }
        }
      }
      if (shouldStop?.call() ?? false) return;
      final previous = await cachedFeeds();
      final merged = <String>{...found, ...previous}.toList(growable: false);
      final file = await _cacheFile();
      final temp = File(file.path + '.tmp');
      await temp.writeAsString(
        jsonEncode(<String, dynamic>{
          'updatedAt': cycleCompleted ? now : last,
          'lastAttemptAt': now,
          'nextPage': page,
          'nextQuery': queryIndex,
          'feeds': merged,
        }),
        flush: true,
      );
      await temp.rename(file.path);
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
