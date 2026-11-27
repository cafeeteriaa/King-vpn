import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'king_network_engines.dart';

enum KingServerSourceKind { publicSubscription, providerManaged }
enum KingServerConfigFormat {
  xrayUri,
  hysteria2Uri,
  singBoxJson,
  shadowsocksUri,
  openVpnProfile,
  wireGuardConfig,
  amneziaWgConfig,
  openConnectEndpoint,
  socksOrHttpProxy,
}
enum KingOfflineImportKind {
  androidDocumentPicker,
  localFile,
  clipboardText,
  qrCode,
  amneziaWgConf,
  openVpnOvpn,
  wireGuardConf,
  openConnectUrl,
  shadowsocksUri,
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
  });
  final String id, name, url;
  final KingServerSourceKind kind;
  final Set<KingServerConfigFormat> formats;
  final Set<String> engineIds;
  final String? updateCadence;
}

class KingServerProfile {
  const KingServerProfile({
    required this.raw,
    required this.format,
    this.sourceId,
  });
  final String raw;
  final KingServerConfigFormat format;
  final String? sourceId;
}

class KingServerSourceFailure {
  const KingServerSourceFailure({required this.sourceId, required this.message});
  final String sourceId, message;
}

class KingServerSourceRefreshResult {
  const KingServerSourceRefreshResult({required this.profiles, required this.failures});
  final List<KingServerProfile> profiles;
  final List<KingServerSourceFailure> failures;
}

class KingEngineServerSourceCatalog {
  static const List<String> _xrayUrls = <String>[
    'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/vless_configs.txt',
    'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/vmess_configs.txt',
    'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/trojan_configs.txt',
    'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/ss_configs.txt',
    'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/all_extracted_configs.txt',
    'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/V2Ray-Config-By-EbraSha-All-Type.txt',
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/verified/configs.txt',
    'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/all/configs.txt',
    'https://raw.githubusercontent.com/Alirewa/V2ray-Configs/main/config.txt',
    'https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/all_sub.txt',
    'https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_Sub.txt',
    'https://raw.githubusercontent.com/barry-far/V2ray-Config/main/All_Configs_Sub.txt',
    'https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/vless.txt',
    'https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/vmess.txt',
    'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/subs/bundles/iran.txt',
    'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/subs/bundles/best.txt',
    'https://raw.githubusercontent.com/HosseinKoofi/GO_V2rayCollector/main/mixed_iran.txt',
    'https://raw.githubusercontent.com/youfoundamin/V2rayCollector/main/mixed_iran.txt',
    'https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/protocols/vless',
    'https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/protocols/vmess',
    'https://raw.githubusercontent.com/3inker/v2ray-subscription/main/subs/all_not_ru.txt',
    'https://raw.githubusercontent.com/3inker/v2ray-subscription/main/subs/all_ru.txt',
    'https://raw.githubusercontent.com/free-nodes/v2rayfree/main/sub',
    'https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/v2ray.txt',
    'https://raw.githubusercontent.com/Au1rxx/free-vpn-subscriptions/main/output/v2ray-base64.txt',
    'https://raw.githubusercontent.com/mahdibland/ShadowsocksAggregator/master/sub/sub_merge.txt',
    'https://raw.githubusercontent.com/mahdibland/ShadowsocksAggregator/master/sub/sub_merge_base64.txt',
    'https://raw.githubusercontent.com/mahdibland/ShadowsocksAggregator/master/sub/sub_merge_raw.txt',
    'https://raw.githubusercontent.com/peasoft/NoMoreWalls/master/list.txt',
    'https://raw.githubusercontent.com/peasoft/NoMoreWalls/master/list_raw.txt',
    'https://raw.githubusercontent.com/peasoft/NoMoreWalls/master/list_base64.txt',
    'https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub',
    'https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub/all',
    'https://raw.githubusercontent.com/Barabama/FreeNodes/main/nodes/ndoe.txt',
    'https://raw.githubusercontent.com/Barabama/FreeNodes/main/nodes/clashmeta.yaml',
    'https://raw.githubusercontent.com/ts-sf/fly/main/v2',
    'https://raw.githubusercontent.com/aiboboxx/v2rayfree/main/v2',
    'https://raw.githubusercontent.com/learnhard-cn/free_proxy_ss/main/v2ray.txt',
    'https://raw.githubusercontent.com/Leon406/SubCrawler/main/sub/share/v2',
    'https://raw.githubusercontent.com/Leon406/SubCrawler/main/sub/share/v2ray',
    'https://raw.githubusercontent.com/Leon406/SubCrawler/main/sub/share/ss',
    'https://raw.githubusercontent.com/Leon406/SubCrawler/main/sub/share/trojan',
    'https://raw.githubusercontent.com/Leon406/SubCrawler/main/sub/share/vmess',
    'https://raw.githubusercontent.com/Leon406/SubCrawler/main/sub/share/vless',
    'https://raw.githubusercontent.com/Leon406/SubCrawler/main/sub/share/hysteria2',
    'https://raw.githubusercontent.com/Leon406/SubCrawler/main/sub/share/tuic',
    'https://raw.githubusercontent.com/Leon406/SubCrawler/main/sub/share/socks',
    'https://raw.githubusercontent.com/Leon406/SubCrawler/main/sub/share/http',
    'https://raw.githubusercontent.com/Leon406/SubCrawler/main/sub/share/ss2022',
    'https://raw.githubusercontent.com/Leon406/SubCrawler/main/sub/share/trojan-go',
  ];

  static List<KingEngineServerSource> xrayFeeds() => List<KingEngineServerSource>.unmodifiable(
    List<KingEngineServerSource>.generate(_xrayUrls.length, (index) => KingEngineServerSource(
      id: 'xray-public-${index + 1}',
      name: 'Xray public feed ${index + 1}',
      url: _xrayUrls[index],
      kind: KingServerSourceKind.publicSubscription,
      formats: const {
        KingServerConfigFormat.xrayUri,
        KingServerConfigFormat.hysteria2Uri,
        KingServerConfigFormat.shadowsocksUri,
      },
      engineIds: const {KingEngineId.xray},
    )),
  );

  static final List<KingEngineServerSource> _sources = <KingEngineServerSource>[
    ...List<KingEngineServerSource>.generate(4, (i) => KingEngineServerSource(
      id: 'hysteria2-${i + 1}',
      name: 'Hysteria 2 source ${i + 1}',
      url: i == 0
          ? 'https://raw.githubusercontent.com/10dream/vpn-configs/main/hysteria2.txt'
          : _xrayUrls[35 + i],
      kind: KingServerSourceKind.publicSubscription,
      formats: const {KingServerConfigFormat.hysteria2Uri},
      engineIds: const {KingEngineId.hysteria2},
      updateCadence: 'hourly',
    )),
    ...List<KingEngineServerSource>.generate(10, (i) => KingEngineServerSource(
      id: 'singbox-${i + 1}',
      name: 'sing-box source ${i + 1}',
      url: _xrayUrls[25 + i],
      kind: KingServerSourceKind.publicSubscription,
      formats: const {KingServerConfigFormat.singBoxJson},
      engineIds: const {KingEngineId.singBox},
      updateCadence: 'hourly',
    )),
    ...List<KingEngineServerSource>.generate(4, (i) => KingEngineServerSource(
      id: 'shadowsocks-${i + 1}',
      name: 'Shadowsocks source ${i + 1}',
      url: _xrayUrls[25 + i],
      kind: KingServerSourceKind.publicSubscription,
      formats: const {KingServerConfigFormat.shadowsocksUri},
      engineIds: const {KingEngineId.shadowsocks},
      updateCadence: 'hourly',
    )),
    KingEngineServerSource(
      id: 'wireguard-provider',
      name: 'WireGuard provider feed',
      url: 'https://raw.githubusercontent.com/Leon406/SubCrawler/main/sub/share/wireguard',
      kind: KingServerSourceKind.publicSubscription,
      formats: const {KingServerConfigFormat.wireGuardConfig},
      engineIds: const {KingEngineId.wireGuard},
      updateCadence: 'hourly',
    ),
  ];

  static List<KingEngineServerSource> get all => List.unmodifiable([...xrayFeeds(), ..._sources]);
  static List<KingEngineServerSource> forEngine(String engineId) =>
      List.unmodifiable(_sources.where((source) => source.engineIds.contains(engineId)));

  static List<KingOfflineImportKind> get offline => const [
    KingOfflineImportKind.androidDocumentPicker,
    KingOfflineImportKind.localFile,
    KingOfflineImportKind.clipboardText,
    KingOfflineImportKind.qrCode,
    KingOfflineImportKind.amneziaWgConf,
    KingOfflineImportKind.openVpnOvpn,
    KingOfflineImportKind.wireGuardConf,
    KingOfflineImportKind.openConnectUrl,
    KingOfflineImportKind.shadowsocksUri,
  ];

  static bool needsUserOrProviderServer(String engineId) =>
      engineId == KingEngineId.nthLink;
  static bool isLocalOnly(String engineId) =>
      KingEngineId.localTransportIds.contains(engineId);
}

class KingServerPayloadParser {
  const KingServerPayloadParser();

  List<KingServerProfile> parse({
    required String engineId,
    required String payload,
    String? sourceId,
  }) {
    var text = payload.trim().replaceAll(r'\n', '\n').replaceAll(r'\r', '\r');
    if (text.isEmpty) return const [];
    final direct = _parseText(engineId, text, sourceId);
    if (direct.isNotEmpty) return direct;
    if (!text.contains('://') && !text.startsWith('{') && !text.startsWith('[')) {
      try {
        final decoded = utf8.decode(base64.decode(base64.normalize(text)));
        return _parseText(engineId, decoded, sourceId);
      } catch (_) {}
    }
    return const [];
  }

  List<KingServerProfile> _parseText(String engineId, String text, String? sourceId) {
    final out = <KingServerProfile>[];
    // OpenVPN and WireGuard are multi-line profile documents. Validate the
    // whole document before considering line-oriented feed entries.
    if (engineId == KingEngineId.openVpn && _validOpenVpn(text)) {
      return <KingServerProfile>[
        KingServerProfile(raw: text.trim(), format: KingServerConfigFormat.openVpnProfile, sourceId: sourceId),
      ];
    }
    if (engineId == KingEngineId.wireGuard && _validWireGuard(text)) {
      return <KingServerProfile>[
        KingServerProfile(raw: text.trim(), format: KingServerConfigFormat.wireGuardConfig, sourceId: sourceId),
      ];
    }
    if (engineId == KingEngineId.amneziaWg && _validWireGuard(text, amnezia: true)) {
      return <KingServerProfile>[
        KingServerProfile(raw: text.trim(), format: KingServerConfigFormat.amneziaWgConfig, sourceId: sourceId),
      ];
    }
    final seen = <String>{};
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final value = line.trim();
      if (value.isEmpty || !seen.add(value)) continue;
      if (engineId == KingEngineId.hysteria2 &&
          _validUri(value, const {'hy2', 'hysteria2'})) {
        out.add(KingServerProfile(raw: value, format: KingServerConfigFormat.hysteria2Uri, sourceId: sourceId));
      } else if (engineId == KingEngineId.singBox) {
        final parsed = _parseSingBox(value, sourceId);
        if (parsed != null) out.add(parsed);
      } else if (engineId == KingEngineId.shadowsocks &&
          _validUri(value, const {'ss'})) {
        out.add(KingServerProfile(raw: value, format: KingServerConfigFormat.shadowsocksUri, sourceId: sourceId));
      } else if (engineId == KingEngineId.openVpn && _validOpenVpn(value)) {
        out.add(KingServerProfile(raw: value, format: KingServerConfigFormat.openVpnProfile, sourceId: sourceId));
      } else if (engineId == KingEngineId.wireGuard && _validWireGuard(value)) {
        out.add(KingServerProfile(raw: value, format: KingServerConfigFormat.wireGuardConfig, sourceId: sourceId));
      } else if (engineId == KingEngineId.amneziaWg && _validWireGuard(value, amnezia: true)) {
        out.add(KingServerProfile(raw: value, format: KingServerConfigFormat.amneziaWgConfig, sourceId: sourceId));
      } else if (engineId == KingEngineId.openConnect && _validHttpsEndpoint(value)) {
        out.add(KingServerProfile(raw: value, format: KingServerConfigFormat.openConnectEndpoint, sourceId: sourceId));
      } else if (engineId == KingEngineId.shroudly && _validProxy(value)) {
        out.add(KingServerProfile(raw: value, format: KingServerConfigFormat.socksOrHttpProxy, sourceId: sourceId));
      } else if (engineId == KingEngineId.xray &&
          _validUri(value, const {'vless','vmess','trojan','ss','socks','http'})) {
        out.add(KingServerProfile(raw: value, format: KingServerConfigFormat.xrayUri, sourceId: sourceId));
      }
    }
    return List.unmodifiable(out);
  }

  KingServerProfile? _parseSingBox(String value, String? sourceId) {
    if (!value.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map || decoded['outbounds'] is! List) return null;
      final outbounds = decoded['outbounds'] as List;
      final valid = outbounds.any((item) {
        if (item is! Map) return false;
        final server = item['server'];
        final port = item['server_port'];
        final type = item['type']?.toString();
        return server is String && server.trim().isNotEmpty &&
            port is num && port > 0 && port <= 65535 &&
            type != null && type.isNotEmpty;
      });
      return valid ? KingServerProfile(raw: value, format: KingServerConfigFormat.singBoxJson, sourceId: sourceId) : null;
    } catch (_) {
      return null;
    }
  }

  bool _validUri(String value, Set<String> schemes) {
    try {
      final uri = Uri.parse(value);
      return schemes.contains(uri.scheme.toLowerCase()) &&
          uri.host.isNotEmpty && (uri.hasPort ? uri.port > 0 && uri.port <= 65535 : true);
    } catch (_) { return false; }
  }

  bool _validHttpsEndpoint(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  bool _validProxy(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && const {'socks5','socks5h','http','https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty && uri.hasPort && uri.port > 0 && uri.port <= 65535;
  }

  bool _validOpenVpn(String value) {
    final normalized = value
        .replaceAll(r'\r\n', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\n')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = normalized.split('\n').map((line) => line.trim());
    var hasClient = false;
    var hasRemote = false;
    for (final line in lines) {
      if (line == 'client') hasClient = true;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 3 && parts.first == 'remote') {
        final port = int.tryParse(parts[2]);
        if (parts[1].isNotEmpty && port != null && port > 0 && port <= 65535) {
          hasRemote = true;
        }
      }
    }
    return hasClient && hasRemote;
  }

  bool _validWireGuard(String value, {bool amnezia = false}) {
    if (value.startsWith('wireguard://')) {
      final uri = Uri.tryParse(value);
      return uri != null && uri.host.isNotEmpty && uri.hasPort && uri.port > 0 && uri.port <= 65535;
    }
    final sections = RegExp(r'^\[(Interface|Peer)\]\s*$', multiLine: true);
    if (!sections.hasMatch(value) ||
        !RegExp(r'^PrivateKey\s*=\s*\S+', multiLine: true).hasMatch(value) ||
        !RegExp(r'^PublicKey\s*=\s*\S+', multiLine: true).hasMatch(value) ||
        !RegExp(r'^Endpoint\s*=\s*\S+:\d+', multiLine: true).hasMatch(value) ||
        !RegExp(r'^AllowedIPs\s*=\s*\S+', multiLine: true).hasMatch(value)) return false;
    final privateKey = RegExp(r'^PrivateKey\s*=\s*(\S+)', multiLine: true).firstMatch(value)?.group(1);
    final publicKey = RegExp(r'^PublicKey\s*=\s*(\S+)', multiLine: true).firstMatch(value)?.group(1);
    if (!_validKey(privateKey) || !_validKey(publicKey)) return false;
    final allowed = RegExp(r'^AllowedIPs\s*=\s*(.+)$', multiLine: true).firstMatch(value)?.group(1) ?? '';
    for (final item in allowed.split(',')) {
      final pair = item.trim().split('/');
      final address = pair.isEmpty ? null : InternetAddress.tryParse(pair.first.trim());
      final prefix = pair.length == 2 ? int.tryParse(pair[1].trim()) : null;
      if (address == null || prefix == null ||
          (address.type == InternetAddressType.IPv4 ? prefix < 0 || prefix > 32 : prefix < 0 || prefix > 128)) return false;
    }
    if (amnezia && !RegExp(r'^S\d+\s*=', multiLine: true).hasMatch(value)) return false;
    return true;
  }

  bool _validKey(String? value) {
    if (value == null) return false;
    try { return base64.decode(base64.normalize(value)).length == 32; } catch (_) { return false; }
  }
}

typedef KingSourceFetchText = Future<String> Function(String url);

class KingServerSourceSync {
  KingServerSourceSync({required this.fetchText, KingServerPayloadParser parser = const KingServerPayloadParser()})
      : parser = parser;
  final KingSourceFetchText fetchText;
  final KingServerPayloadParser parser;

  Future<KingServerSourceRefreshResult> refresh(String engineId) async {
    final profiles = <KingServerProfile>[];
    final failures = <KingServerSourceFailure>[];
    final seen = <String>{};
    for (final source in KingEngineServerSourceCatalog.forEngine(engineId)) {
      try {
        final body = await fetchText(source.url);
        for (final profile in parser.parse(engineId: engineId, payload: body, sourceId: source.id)) {
          if (seen.add(profile.raw)) profiles.add(profile);
        }
      } catch (error) {
        failures.add(KingServerSourceFailure(sourceId: source.id, message: error.toString()));
      }
    }
    return KingServerSourceRefreshResult(
      profiles: List.unmodifiable(profiles),
      failures: List.unmodifiable(failures),
    );
  }
}

class KingHttpSourceFetcher {
  KingHttpSourceFetcher({HttpClient? client}) : _client = client ?? HttpClient();
  final HttpClient _client;

  Future<String> fetch(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Only credential-free HTTPS source URLs are accepted.');
    }
    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 20));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException('Source returned HTTP ${response.statusCode}', uri: uri);
    }
    return response.transform(utf8.decoder).join();
  }

  void close({bool force = false}) => _client.close(force: force);
}

class KingServerSourceRefreshScheduler {
  KingServerSourceRefreshScheduler({required this.sync, required this.onResult});
  final KingServerSourceSync sync;
  final Future<void> Function(KingServerSourceRefreshResult result) onResult;
  final Map<String, Future<KingServerSourceRefreshResult>> _inFlight = {};
  bool _disposed = false;

  static Duration? intervalForSource(KingEngineServerSource source) {
    final cadence = source.updateCadence?.trim().toLowerCase();
    if (cadence == null || cadence.isEmpty) return null;
    if (cadence == 'hourly' || cadence == '1h') return const Duration(hours: 1);
    if (cadence == 'daily' || cadence == '24h') return const Duration(hours: 24);
    final match = RegExp(r'^(\d+)(m|h|d)$').firstMatch(cadence);
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!);
    if (value == null || value <= 0) return null;
    switch (match.group(2)) {
      case 'm': return Duration(minutes: value);
      case 'h': return Duration(hours: value);
      case 'd': return Duration(days: value);
    }
    return null;
  }

  Future<KingServerSourceRefreshResult> refreshNow(String engineId) {
    if (_disposed) return Future.error(StateError('Refresh scheduler is disposed.'));
    final existing = _inFlight[engineId];
    if (existing != null) return existing;
    late final Future<KingServerSourceRefreshResult> operation;
    operation = sync.refresh(engineId).then((result) async {
      await onResult(result);
      return result;
    }).whenComplete(() {
      if (identical(_inFlight[engineId], operation)) _inFlight.remove(engineId);
    });
    _inFlight[engineId] = operation;
    return operation;
  }

  void dispose() {
    _disposed = true;
    _inFlight.clear();
  }
}
