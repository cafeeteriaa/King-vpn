import 'king_engine_sources.dart';

class KingProxySource {
  const KingProxySource({required this.id, required this.name, required this.url});
  final String id;
  final String name;
  final String url;
}

class KingProxySourceCatalog {
  KingProxySourceCatalog._();

  static final List<KingProxySource> online = List<KingProxySource>.unmodifiable(
    KingEngineServerSourceCatalog.xrayFeeds().map((source) => KingProxySource(
      id: source.id,
      name: source.name,
      url: source.url,
    )),
  );

  static List<KingProxySource> forXray() => List<KingProxySource>.unmodifiable(online);
}
