import 'king_engine_sources.dart';
import 'king_network_engines.dart';

class KingProxySourceCatalog {
  static List<KingEngineServerSource> get online =>
      List<KingEngineServerSource>.unmodifiable(KingEngineServerSourceCatalog.xrayFeeds());

  static List<KingEngineServerSource> forXray() =>
      List<KingEngineServerSource>.unmodifiable(KingEngineServerSourceCatalog.xrayFeeds());
}
