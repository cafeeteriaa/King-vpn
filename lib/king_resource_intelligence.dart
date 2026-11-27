/// Source intelligence for the unified KING VPN scanner.
///
/// This module orders sources without deleting or capping any configured source.
/// Host classification is only a scheduling hint; it never proves reachability.
/// User-provided subscriptions are treated as already-owned inputs: the app may
/// fetch them using the user's existing access, but never purchases or creates
/// an account for a paid provider.
enum KingResourceSourceKind {
  userProvided,
  domesticPublic,
  communityPublic,
  unknown,
}

enum KingResourceAccess {
  publicSource,
  userSuppliedAccess,
  unknown,
}

class KingResourceSource {
  const KingResourceSource({
    required this.url,
    required this.kind,
    required this.access,
    required this.priority,
  });

  final String url;
  final KingResourceSourceKind kind;
  final KingResourceAccess access;
  final int priority;
}

class KingResourceIntelligence {
  KingResourceIntelligence._();

  static const Set<String> _knownDomesticHosts = <String>{
    'aparat.com',
    'digikala.com',
    'divar.ir',
    'digikala.ir',
    'shatel.ir',
    'mci.ir',
    'mtnirancell.ir',
  };

  static bool _isDomesticHost(String host) {
    final normalizedHost = host.toLowerCase();
    final value = normalizedHost.startsWith('www.')
        ? normalizedHost.substring(4)
        : normalizedHost;
    if (value.endsWith('.ir')) return true;
    if (_knownDomesticHosts.contains(value)) return true;
    return value.endsWith('.iran') ||
        value == 'iranhost.com' || value.endsWith('.iranhost.com') ||
        value == 'iranserver.com' || value.endsWith('.iranserver.com');
  }

  static KingResourceSource describe(
    String rawUrl, {
    bool userProvided = false,
    required bool nationalMode,
  }) {
    final url = rawUrl.trim();
    if (userProvided) {
      return KingResourceSource(
        url: url,
        kind: KingResourceSourceKind.userProvided,
        access: KingResourceAccess.userSuppliedAccess,
        priority: nationalMode ? 400 : 500,
      );
    }

    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return KingResourceSource(
        url: url,
        kind: KingResourceSourceKind.unknown,
        access: KingResourceAccess.unknown,
        priority: 0,
      );
    }

    if (_isDomesticHost(uri.host)) {
      return KingResourceSource(
        url: url,
        kind: KingResourceSourceKind.domesticPublic,
        access: KingResourceAccess.publicSource,
        priority: nationalMode ? 500 : 250,
      );
    }

    return KingResourceSource(
      url: url,
      kind: KingResourceSourceKind.communityPublic,
      access: KingResourceAccess.publicSource,
      priority: nationalMode ? 100 : 350,
    );
  }

  /// Stable priority ordering. Every input survives; no arbitrary source cap,
  /// no automatic paid subscription, and no mutation of the caller's list.
  static List<String> orderSources(
    Iterable<String> sources, {
    required bool nationalMode,
    Iterable<String> userProvidedSources = const <String>[],
  }) {
    final userSet = userProvidedSources.map((e) => e.trim()).toSet();
    final indexed = <({int index, KingResourceSource source})>[];
    var index = 0;
    for (final raw in sources) {
      final source = describe(
        raw,
        userProvided: userSet.contains(raw.trim()),
        nationalMode: nationalMode,
      );
      indexed.add((index: index++, source: source));
    }
    indexed.sort((a, b) {
      final byPriority = b.source.priority.compareTo(a.source.priority);
      return byPriority != 0 ? byPriority : a.index.compareTo(b.index);
    });
    return <String>[for (final item in indexed) item.source.url];
  }
}
