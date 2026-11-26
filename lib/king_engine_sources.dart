import 'king_auto_switch.dart';
import 'king_proxy_sources.dart';

enum KingServerSourceKind {
  publicSubscription,
  generatedDirectory,
  providerProvisioning,
  manualEndpoint,
  offlineImport,
  localModule,
}

enum KingServerConfigFormat {
  xraySubscription,
  singBoxJson,
  mixedShareLinks,
  hysteria2Uri,
  shadowsocksUri,
  openVpnProfile,
  wireGuardConfig,
  amneziaWgConfig,
  openConnectEndpoint,
  socksOrHttpProxy,
  providerManaged,
  none,
}

enum KingOfflineImportKind {
  androidDocumentPicker,
  localFile,
  clipboardText,
  qrCode,
  manualShareLink,
  base64Subscription,
  singBoxJson,
  xrayJson,
  openVpnOvpn,
  wireGuardConf,
  amneziaWgConf,
  openConnectUrl,
  shadowsocksUri,
  providerProfile,
}

class KingEngineServerSource {
  const KingEngineServerSource({
    required this.id,
    required this.name,
    required this.url,
    required this.kind,
    required this.formats,
    required this.engineIds,
    this.updateCadence,
    this.notes = '',
  });

  final String id;
  final String name;
  final String url;
  final KingServerSourceKind kind;
  final Set<KingServerConfigFormat> formats;
  final Set<String> engineIds;
  /// Publisher-stated cadence; null means unknown, never inferred.
  final String? updateCadence;
  final String notes;
}

/// Protocol-aware sources. A source is never assigned to an engine merely
/// because its URL is reachable; its published formats must match.
class KingEngineServerSourceCatalog {
  static const List<KingEngineServerSource> online = [
    KingEngineServerSource(
      id: 'au1rxx_singbox',
      name: 'Au1rxx Free VPN Subscriptions',
      url: 'https://github.com/Au1rxx/free-vpn-subscriptions/raw/main/output/singbox.json',
      kind: KingServerSourceKind.publicSubscription,
      formats: {KingServerConfigFormat.singBoxJson},
      engineIds: {'sing_box', 'hysteria2', 'shadowsocks'},
      updateCadence: 'hourly',
      notes: 'Publisher reports hourly refresh and recent HTTP-over-proxy checks; nodes are third-party and untrusted.',
    ),
    KingEngineServerSource(
      id: 'parsabrg_mixed',
      name: 'Parsabrg Free Sub',
      url: 'https://parsabrg.github.io/free_sub/sub.txt',
      kind: KingServerSourceKind.publicSubscription,
      formats: {KingServerConfigFormat.mixedShareLinks},
      engineIds: {'xray', 'hysteria2', 'shadowsocks', 'sing_box'},
      notes: 'Publisher reports VLESS, VMess, Trojan, Shadowsocks, Hysteria2 and SOCKS5 links; refresh cadence not asserted here.',
    ),
    KingEngineServerSource(
      id: 'morpheusadam_hysteria2',
      name: 'morpheusadam v2ray-config',
      url: 'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/subs/all.txt',
      kind: KingServerSourceKind.publicSubscription,
      formats: {KingServerConfigFormat.mixedShareLinks},
      engineIds: {'xray', 'hysteria2', 'shadowsocks', 'sing_box'},
      updateCadence: 'daily',
      notes: 'Mixed-protocol public feed; protocol must be parsed and filtered locally.',
    ),
    KingEngineServerSource(
      id: 'morpheusadam_shadowsocks',
      name: 'morpheusadam Shadowsocks feed',
      url: 'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/subs/bundles/shadowsocks.txt',
      kind: KingServerSourceKind.publicSubscription,
      formats: {KingServerConfigFormat.shadowsocksUri},
      engineIds: {'shadowsocks', 'sing_box'},
      updateCadence: 'daily',
      notes: 'Only Shadowsocks-compatible entries should be retained by the parser.',
    ),
    KingEngineServerSource(
      id: 'auto_ovpn_directory',
      name: '9xN auto-ovpn',
      url: 'https://api.github.com/repos/9xN/auto-ovpn/contents/configs',
      kind: KingServerSourceKind.generatedDirectory,
      formats: {KingServerConfigFormat.openVpnProfile},
      engineIds: {'openvpn'},
      notes: 'Auto-generated public OpenVPN profile directory. Parse the GitHub contents API and fetch individual .ovpn files; server availability is not guaranteed.',
    ),
  ];

  static const List<KingOfflineImportKind> offline = KingOfflineImportKind.values;

  static List<KingEngineServerSource> forEngine(String engineId) =>
      List.unmodifiable(online.where((source) => source.engineIds.contains(engineId)));

  static List<KingProxySource> xrayFeeds() => KingProxySourceCatalog.online;

  static List<KingEngineServerSource> forProtocol(String engineId) =>
      forEngine(engineId);

  static bool needsUserOrProviderServer(String engineId) => const {
    'nthlink', 'amneziawg', 'openconnect', 'wireguard',
  }.contains(engineId);

  static bool isLocalOnly(String engineId) => const {
    'shroudly', 'byedpi', 'powertunnel',
  }.contains(engineId);
}
