import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Discovers additional public Xray/V2Ray subscription feeds from GitHub.
///
/// Repository metadata is never trusted as a server configuration. Returned
/// raw URLs still pass through the existing parser and real-core/data-plane
/// verification before a server can be used.
class KingDynamicSourceDiscovery {
  KingDynamicSourceDiscovery._();

  static const Duration _ttl = Duration(hours: 12);
  static const Duration _retryDelay = Duration(minutes: 15);
  static const int _pageSize = 100;
  static const int _maxSearchPages = 10; // GitHub Search API: max 1,000 results/query.
  static const int _maxSearchResponseChars = 1024 * 1024;
  static const int _maxTreeResponseChars = 8 * 1024 * 1024;
  static const int _maxFileBytes = 1500000;
  static const Duration _cycleBudget = Duration(minutes: 2);
  static const Duration _requestTimeout = Duration(seconds: 5);
  static const int _workerCount = 4;
  static const String _api = 'https://api.github.com';
  static const List<String> _searchQueries = <String>[
    'v2ray subscription config',
    'xray subscription config',
    'vless vmess trojan config',
    'shadowsocks subscription proxy',
    'vpn proxy nodes subscription',
  ];

  static bool _refreshing = false;

  /// Accepts likely subscription/config artifacts without imposing a total
  /// inventory count. Per-file size and path checks bound the work safely.
  static bool isCandidatePath(String path, {int? size}) {
    if (path.isEmpty || path.contains(r'\')) return false;
    final normalized = path.toLowerCase();
    final segments = normalized.split('/');
    if (segments.any((segment) =>
        segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.startsWith('.'))) {
      return false;
    }
    if (size != null && (size <= 0 || size > _maxFileBytes)) return false;
    if (RegExp(r'(^|/)docs(/|$)').hasMatch(normalized)) return false;
    if (RegExp(r'(^|/)(readme|license|changelog|contributing)(\.|$)')
        .hasMatch(normalized)) {
      return false;
    }

    final name = segments.last;
    final feedName = RegExp(
      r'(sub|config|proxy|v2ray|xray|node|server|all|mix|vless|vmess|trojan|shadowsocks|hysteria2|singbox|wireguard)',
    ).hasMatch(name);
    final knownExtension =
        RegExp(r'\.(txt|yaml|yml|json|conf|sub)$').hasMatch(name);
    final extensionlessFeed = !name.contains('.') && feedName;
    return feedName && (knownExtension || extensionlessFeed);
  }

  /// Validates a Git ref without excluding valid Unicode branch names.
  static bool isSafeGitRef(String ref) {
    if (ref.isEmpty ||
        ref == '@' ||
        ref.startsWith('/') ||
        ref.endsWith('/') ||
        ref.contains('//') ||
        ref.contains('..') ||
        ref.contains('@{')) {
      return false;
    }
    const forbidden = <int>{
      0x20, // space
      0x7f,
      0x5c, // backslash
      0x7e, // ~
      0x5e, // ^
      0x3a, // :
      0x3f, // ?
      0x2a, // *
      0x5b, // [
    };
    if (ref.codeUnits.any((unit) => unit < 0x20 || forbidden.contains(unit))) {
      return false;
    }
    return ref.split('/').every((segment) =>
        segment.isNotEmpty &&
        segment != '.' &&
        segment != '..' &&
        !segment.startsWith('.') &&
        !segment.endsWith('.') &&
        !segment.toLowerCase().endsWith('.lock'));
  }

  /// Returns a canonical raw.githubusercontent.com file URL or null.
  static String? normalizeFeedUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'raw.githubusercontent.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port != 443) {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.length < 4 ||
        segments.any((segment) =>
            segment.isEmpty ||
            segment == '.' ||
            segment == '..' ||
            segment.contains('/') ||
            segment.contains(r'\') ||
            segment.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f))) {
      return null;
    }
    return uri.toString();
  }

  static Future<File> _cacheFile() async {
    final directory = await getApplicationSupportDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(directory.path + '/king_dynamic_sources_v2.json');
  }

  static Future<Map<String, dynamic>> _readCache() async {
    final file = await _cacheFile();
    for (final candidate in <File>[
      file,
      File(file.path + '.bak'),
    ]) {
      try {
        if (!await candidate.exists()) continue;
        final decoded = jsonDecode(await candidate.readAsString());
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // Try the backup if the primary cache was interrupted or corrupted.
      }
    }
    return <String, dynamic>{};
  }

  static Future<void> _writeCacheAtomically(
    Map<String, dynamic> value,
  ) async {
    final file = await _cacheFile();
    final temporary = File(file.path + '.tmp');
    final backup = File(file.path + '.bak');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    try {
      await temporary.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } on FileSystemException {
      if (!await file.exists()) rethrow;
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
      try {
        await temporary.rename(file.path);
        if (await backup.exists()) await backup.delete();
      } catch (_) {
        if (!await file.exists() && await backup.exists()) {
          await backup.rename(file.path);
        }
        rethrow;
      }
    }
  }

  /// Returns the last known-good inventory immediately.
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

  /// Incrementally searches public repositories with bounded concurrency.
  ///
  /// The GitHub search API exposes at most 1,000 results per query. The
  /// checkpoint advances across pages and queries; it never imposes a fixed
  /// total repository/feed cap. A short time budget and four workers protect
  /// battery, memory and background execution time.
  static Future<void> refresh({bool Function()? shouldStop}) async {
    if (_refreshing || (shouldStop?.call() ?? false)) return;
    _refreshing = true;
    final client = http.Client();
    try {
      final oldCache = await _readCache();
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastUpdated = oldCache['updatedAt'] is num
          ? (oldCache['updatedAt'] as num).toInt()
          : 0;
      final lastAttempt = oldCache['lastAttemptAt'] is num
          ? (oldCache['lastAttemptAt'] as num).toInt()
          : 0;
      final sinceUpdate = now - lastUpdated;
      final sinceAttempt = now - lastAttempt;
      if ((lastUpdated > 0 &&
              sinceUpdate >= 0 &&
              sinceUpdate < _ttl.inMilliseconds) ||
          (lastAttempt > 0 &&
              sinceAttempt >= 0 &&
              sinceAttempt < _retryDelay.inMilliseconds)) {
        return;
      }

      final stopwatch = Stopwatch()..start();
      var page = oldCache['nextPage'] is num
          ? (oldCache['nextPage'] as num).toInt()
          : 1;
      var queryIndex = oldCache['nextQuery'] is num
          ? (oldCache['nextQuery'] as num).toInt()
          : 0;
      if (page < 1 || page > _maxSearchPages) page = 1;
      if (queryIndex < 0 || queryIndex >= _searchQueries.length) {
        queryIndex = 0;
      }

      var cycleCompleted = false;
      final found = <String>{};

      while (stopwatch.elapsed < _cycleBudget &&
          !(shouldStop?.call() ?? false)) {
        final searchUri = Uri.https(
          'api.github.com',
          '/search/repositories',
          <String, String>{
            'q': _searchQueries[queryIndex],
            'sort': 'updated',
            'order': 'desc',
            'per_page': '$_pageSize',
            'page': '$page',
          },
        );
        final searchResponse = await client
            .get(searchUri, headers: _headers)
            .timeout(_requestTimeout);
        if (searchResponse.statusCode != 200 ||
            searchResponse.body.length > _maxSearchResponseChars) {
          break;
        }

        final searchJson = jsonDecode(searchResponse.body);
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

        final repositories = <({String owner, String name, String branch})>[];
        for (final item in items) {
          if (item is! Map) continue;
          final fullName = item['full_name'];
          final branch = item['default_branch'];
          if (fullName is! String || branch is! String || !isSafeGitRef(branch)) {
            continue;
          }
          final parts = fullName.split('/');
          if (parts.length != 2 ||
              parts.any((part) =>
                  part.isEmpty ||
                  !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(part))) {
            continue;
          }
          repositories.add((
            owner: parts[0],
            name: parts[1],
            branch: branch,
          ));
        }

        var nextRepository = 0;
        Future<void> worker() async {
          while (nextRepository < repositories.length &&
              stopwatch.elapsed < _cycleBudget &&
              !(shouldStop?.call() ?? false)) {
            final repository = repositories[nextRepository++];
            try {
              final encodedBranch = repository.branch
                  .split('/')
                  .map(Uri.encodeComponent)
                  .join('%2F');
              final treeUri = Uri.parse(
                _api +
                    '/repos/' +
                    Uri.encodeComponent(repository.owner) +
                    '/' +
                    Uri.encodeComponent(repository.name) +
                    '/git/trees/' +
                    encodedBranch +
                    '?recursive=1',
              );
              final response = await client
                  .get(treeUri, headers: _headers)
                  .timeout(_requestTimeout);
              if (response.statusCode != 200 ||
                  response.body.length > _maxTreeResponseChars) {
                continue;
              }
              final treeJson = jsonDecode(response.body);
              if (treeJson is! Map || treeJson['truncated'] == true) continue;
              final entries = treeJson['tree'];
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
                final score = _pathScore(b.path).compareTo(_pathScore(a.path));
                return score != 0 ? score : a.size.compareTo(b.size);
              });

              final rawBranch = repository.branch
                  .split('/')
                  .map(Uri.encodeComponent)
                  .join('/');
              for (final candidate in candidates) {
                if (shouldStop?.call() ?? false) break;
                final encodedPath = candidate.path
                    .split('/')
                    .map(Uri.encodeComponent)
                    .join('/');
                final url = normalizeFeedUrl(
                  'https://raw.githubusercontent.com/' +
                      repository.owner +
                      '/' +
                      repository.name +
                      '/' +
                      rawBranch +
                      '/' +
                      encodedPath,
                );
                if (url != null) found.add(url);
              }
            } catch (_) {
              // A malformed, unavailable or rate-limited repository is isolated.
            }
          }
        }

        await Future.wait(
          List<Future<void>>.generate(_workerCount, (_) => worker()),
        );
        if (shouldStop?.call() ?? false) break;
        if (nextRepository < repositories.length) {
          break; // Resume the same page on the next cycle.
        }

        page++;
        if (page > _maxSearchPages) {
          page = 1;
          queryIndex++;
          if (queryIndex >= _searchQueries.length) {
            queryIndex = 0;
            cycleCompleted = true;
            break;
          }
        }
      }

      // Persist partial discoveries and the cursor even when a caller stops
      // the cycle. This avoids throwing away useful work from completed workers.
      final cached = oldCache['feeds'];
      final previous = cached is List
          ? cached
              .whereType<String>()
              .map(normalizeFeedUrl)
              .whereType<String>()
              .toSet()
          : <String>{};
      final merged = <String>{...previous, ...found}.toList()..sort();
      await _writeCacheAtomically(<String, dynamic>{
        'updatedAt': cycleCompleted ? now : lastUpdated,
        'lastAttemptAt': now,
        'nextPage': page,
        'nextQuery': queryIndex,
        'feeds': merged,
      });
    } catch (_) {
      // Preserve the last known-good source inventory on discovery errors.
    } finally {
      client.close();
      _refreshing = false;
    }
  }

  static const Map<String, String> _headers = <String, String>{
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'KING-VPN-Dynamic-Source-Discovery',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  static int _pathScore(String path) {
    final normalized = path.toLowerCase();
    var score = 0;
    if (normalized.contains('all') || normalized.contains('mix')) score += 5;
    if (normalized.contains('sub')) score += 4;
    if (normalized.contains('vless') ||
        normalized.contains('vmess') ||
        normalized.contains('trojan')) {
      score += 3;
    }
    if (normalized.contains('config') || normalized.contains('proxy')) {
      score += 2;
    }
    return score;
  }
}
