import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'king_network_engines.dart';

enum KingServerSourceKind { publicSubscription, userProvided }

enum KingServerConfigFormat {
  xrayUri,
  hysteria2Uri,
  singBoxJson,
  openVpnProfile,
  wireGuardConfig,
  amneziaWgConfig,
  openConnectEndpoint,
  socksOrHttpProxy,
  shadowsocksUri,
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

class KingServerSource {
  const KingServerSource({
    required this.id,
    required this.name,
    required this.url,
    required this.kind,
    required this.formats,
    required this.engineIds,
    this.updateCadence,
  });

  final String id;
  final String name;
  final String url;
  final KingServerSourceKind kind;
  final Set<KingServerConfigFormat> formats;
  final Set<String> engineIds;
  final String? updateCadence;
}

class KingServerProfile {
  const KingServerProfile({
    required this.raw,
    required this.format,
    this.sourceId = '',
  });

  final String raw;
  final KingServerConfigFormat format;
  final String sourceId;
}

class KingServerSourceFailure {
  const KingServerSourceFailure({required this.sourceId, required this.message});
  final String sourceId;
  final String message;
}

class KingServerSourceSyncResult {
  const KingServerSourceSyncResult({
    required this.profiles,
    required this.failures,
  });
  final List<KingServerProfile> profiles;
  final List<KingServerSourceFailure> failures;
}

class KingEngineServerSourceCatalog {
  KingEngineServerSourceCatalog._();

  static const String _gh = 'https://raw.githubusercontent.com/';
  static final List<String> _xrayPaths = <String>[
    for (var i = 1; i <= 10; i++) 'V2RAYCONFIGSPOOL/V2RAY_SUB/main/v2ray_configs_no$i.txt',
    'iboxz/free-v2ray-collector/main/main/mix.txt',
    'iboxz/free-v2ray-collector/main/main/vless.txt',
    'iboxz/free-v2ray-collector/main/main/vmess.txt',
    'iboxz/free-v2ray-collector/main/main/shadowsocks.txt',
    'iboxz/free-v2ray-collector/main/main/trojan.txt',
    'ebrasha/free-v2ray-public-list/main/V2Ray-Config-By-EbraSha.txt',
    'MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/all_sub.txt',
    '0xRadikal/Free-v2ray-Configs/main/protocols/vless.txt',
    '0xRadikal/Free-v2ray-Configs/main/protocols/vmess.txt',
    '0xRadikal/Free-v2ray-Configs/main/protocols/trojan.txt',
    'Idolvpn/Automate-V2ray-Config-Collector/main/configs/vless.txt',
    'Idolvpn/Automate-V2ray-Config-Collector/main/configs/vmess.txt',
    'Idolvpn/Automate-V2ray-Config-Collector/main/configs/trojan.txt',
    'barry-far/V2ray-Config/main/All_Configs_Sub.txt',
    'Epodonios/v2ray-configs/refs/heads/main/All_Configs_Sub.txt',
    'soroushmirzaei/telegram-configs-collector/main/splitted/mixed',
    'soroushmirzaei/telegram-configs-collector/main/splitted/vmess',
    'soroushmirzaei/telegram-configs-collector/main/splitted/vless',
    'soroushmirzaei/telegram-configs-collector/main/splitted/trojan',
    'soroushmirzaei/telegram-configs-collector/main/splitted/shadowsocks',
    'itsyebekhe/PSG/main/subscriptions/xray/normal/mix',
    'itsyebekhe/PSG/main/subscriptions/xray/normal/vmess',
    'itsyebekhe/PSG/main/subscriptions/xray/normal/vless',
    'itsyebekhe/PSG/main/subscriptions/xray/normal/trojan',
    'itsyebekhe/PSG/main/subscriptions/xray/normal/ss',
    for (var i = 1; i <= 8; i++) 'AvenCores/goida-vpn-configs/main/githubmirror/$i.txt',
    'hamedcode/port-based-v2ray-configs/main/sub/vless.txt',
    'hamedcode/port-based-v2ray-configs/main/sub/vmess.txt',
    'hamedcode/port-based-v2ray-configs/main/sub/trojan.txt',
    'hamedcode/port-based-v2ray-configs/main/sub/ss.txt',
    'lagzian/SS-Collector/main/configs/mixed/vless.txt',
    'lagzian/SS-Collector/main/configs/mixed/trojan.txt',
    'lagzian/SS-Collector/main/configs/mixed/ss.txt',
  ];

  static List<KingServerSource> xrayFeeds() => <KingServerSource>[
    for (var i = 0; i < _xrayPaths.length; i++)
      KingServerSource(
        id: 'xray-public-$i',
        name: 'Public Xray feed ${i + 1}',
        url: '$_gh${_xrayPaths[i]}',
        kind: KingServerSourceKind.publicSubscription,
        formats: const <KingServerConfigFormat>{
          KingServerConfigFormat.xrayUri,
          KingServerConfigFormat.shadowsocksUri,
        },
        engineIds: const <String>{KingEngineId.xray},
        updateCadence: i < 10 ? '15m' : null,
      ),
  ];

  static List<KingServerSource> forEngine(String engineId) {
    if (engineId == KingEngineId.xray) return xrayFeeds();
    List<String> paths;
    Set<KingServerConfigFormat> formats;
    switch (engineId) {
      case KingEngineId.hysteria2:
        paths = <String>[
          '10Dream/sub-mod/main/sub/split/protocols/hy2.txt',
          '10ium/VpnClashFaCollector/main/sub/all/hysteria2.txt',
          'Argh94/V2RayAutoConfig/main/configs/Hysteria2.txt',
          'nimazolfaghari66-sketch/iran-vpn-radar/main/subscriptions/candidates/hysteria2',
        ];
        formats = const <KingServerConfigFormat>{KingServerConfigFormat.hysteria2Uri};
        break;
      case KingEngineId.singBox:
        paths = <String>[
          '10Dream/sub-mod/main/sub/clash/mixed.yaml',
          '10Dream/sub-mod/main/sub/normal/10Dream-VpnClashFaCollector-mixed.txt',
          'morpheusadam/v2ray-config/main/subs/all.txt',
          'mahdibland/V2RayAggregator/master/Eternity.txt',
          'ermaozi/get_subscribe/main/subscribe/v2ray.txt',
          'soroushmirzaei/telegram-configs-collector/main/splitted/mixed',
          'iboxz/free-v2ray-collector/main/main/mix.txt',
          'barry-far/V2ray-Config/main/All_Configs_Sub.txt',
          'Epodonios/v2ray-configs/refs/heads/main/All_Configs_Sub.txt',
          'Delta-Kronecker/V2ray-Config/main/config/protocols/vless.txt',
        ];
        formats = const <KingServerConfigFormat>{KingServerConfigFormat.singBoxJson};
        break;
      case KingEngineId.shadowsocks:
        paths = <String>[
          'soroushmirzaei/telegram-configs-collector/main/splitted/shadowsocks',
          'iboxz/free-v2ray-collector/main/main/shadowsocks.txt',
          'lagzian/SS-Collector/main/configs/mixed/ss.txt',
          'ZendanTeam/SS44-sub/main/SS44-gold.txt',
        ];
        formats = const <KingServerConfigFormat>{KingServerConfigFormat.shadowsocksUri};
        break;
      case KingEngineId.wireGuard:
        paths = <String>[
          'Argh94/V2RayAutoConfig/main/configs/WireGuard.txt',
        ];
        formats = const <KingServerConfigFormat>{KingServerConfigFormat.wireGuardConfig};
        break;
      default:
        return <KingServerSource>[];
    }
    return <KingServerSource>[
      for (var i = 0; i < paths.length; i++)
        KingServerSource(
          id: '${engineId}-public-$i',
          name: '${engineId} public feed ${i + 1}',
          url: '$_gh${paths[i]}',
          kind: KingServerSourceKind.publicSubscription,
          formats: formats,
          engineIds: <String>{engineId},
        ),
    ];
  }

  static const Set<KingOfflineImportKind> offline = <KingOfflineImportKind>{
    KingOfflineImportKind.androidDocumentPicker,
    KingOfflineImportKind.localFile,
    KingOfflineImportKind.clipboardText,
    KingOfflineImportKind.qrCode,
    KingOfflineImportKind.amneziaWgConf,
    KingOfflineImportKind.openVpnOvpn,
    KingOfflineImportKind.wireGuardConf,
    KingOfflineImportKind.openConnectUrl,
    KingOfflineImportKind.shadowsocksUri,
  };

  static bool needsUserOrProviderServer(String engineId) =>
      engineId == KingEngineId.nthLink;

  static bool isLocalOnly(String engineId) =>
      engineId == KingEngineId.shroudly ||
      engineId == KingEngineId.byeDpi ||
      engineId == KingEngineId.powerTunnel;
}

class KingServerPayloadParser {
  const KingServerPayloadParser();

  List<KingServerProfile> parse({
    required String engineId,
    required String payload,
    String sourceId = '',
  }) {
    var text = payload.trim();
    if (text.isEmpty) return <KingServerProfile>[];
    if (!text.contains('://') && !text.startsWith('{') && !text.startsWith('[')) {
      try {
        final decoded = utf8.decode(base64.decode(base64.normalize(text)));
        if (decoded.trim().isNotEmpty) text = decoded.trim();
      } catch (_) {}
    }

    if (engineId == KingEngineId.hysteria2) {
      final profiles = <KingServerProfile>[];
      for (final line in text.split(RegExp(r'[\r\n]+'))) {
        final value = line.trim();
        if (!(value.toLowerCase().startsWith('hy2://') ||
            value.toLowerCase().startsWith('hysteria2://'))) continue;
        final uri = Uri.tryParse(value);
        if (uri == null || uri.host.isEmpty || uri.port < 1 || uri.port > 65535) continue;
        profiles.add(KingServerProfile(
          raw: value, format: KingServerConfigFormat.hysteria2Uri, sourceId: sourceId,
        ));
      }
      return _dedupe(profiles);
    }

    if (engineId == KingEngineId.singBox) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map || decoded['outbounds'] is! List) return <KingServerProfile>[];
        final valid = (decoded['outbounds'] as List).any((outbound) {
          if (outbound is! Map) return false;
          final type = outbound['type']?.toString() ?? '';
          final server = outbound['server']?.toString() ?? '';
          final port = outbound['server_port'];
          return type.isNotEmpty && server.isNotEmpty && port is num && port >= 1 && port <= 65535;
        });
        return valid ? <KingServerProfile>[
          KingServerProfile(raw: text, format: KingServerConfigFormat.singBoxJson, sourceId: sourceId),
        ] : <KingServerProfile>[];
      } catch (_) {
        return <KingServerProfile>[];
      }
    }

    if (engineId == KingEngineId.openVpn) {
      final lower = text.toLowerCase();
      final remote = RegExp(r'^\s*remote\s+\S+\s+\d+', multiLine: true).hasMatch(text);
      if (lower.contains('client') && remote &&
          RegExp(r'^\s*proto\s+(udp|tcp)', multiLine: true).hasMatch(lower)) {
        return <KingServerProfile>[
          KingServerProfile(raw: text, format: KingServerConfigFormat.openVpnProfile, sourceId: sourceId),
        ];
      }
      return <KingServerProfile>[];
    }

    if (engineId == KingEngineId.wireGuard || engineId == KingEngineId.amneziaWg) {
      final link = Uri.tryParse(text);
      if (text.toLowerCase().startsWith('wireguard://') &&
          link != null && link.host.isNotEmpty && link.port > 0 && link.userInfo.isNotEmpty) {
        return <KingServerProfile>[
          KingServerProfile(raw: text, format: KingServerConfigFormat.wireGuardConfig, sourceId: sourceId),
        ];
      }
      final parsed = _parseWireGuard(text);
      if (parsed == null) return <KingServerProfile>[];
      final isAmnezia = engineId == KingEngineId.amneziaWg ||
          RegExp(r'^\s*(S[1-4]|Jc|Jmin|Jmax|H[1-4])\s*=', multiLine: true).hasMatch(text);
      return <KingServerProfile>[
        KingServerProfile(
          raw: text,
          format: isAmnezia
              ? KingServerConfigFormat.amneziaWgConfig
              : KingServerConfigFormat.wireGuardConfig,
          sourceId: sourceId,
        ),
      ];
    }

    if (engineId == KingEngineId.openConnect) {
      final uri = Uri.tryParse(text);
      if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
        return <KingServerProfile>[
          KingServerProfile(raw: text, format: KingServerConfigFormat.openConnectEndpoint, sourceId: sourceId),
        ];
      }
      return <KingServerProfile>[];
    }

    if (engineId == KingEngineId.shroudly) {
      final uri = Uri.tryParse(text);
      if (uri != null && const <String>{'socks5', 'socks5h', 'http', 'https'}.contains(uri.scheme) &&
          uri.host.isNotEmpty && uri.port > 0) {
        return <KingServerProfile>[
          KingServerProfile(raw: text, format: KingServerConfigFormat.socksOrHttpProxy, sourceId: sourceId),
        ];
      }
      return <KingServerProfile>[];
    }

    if (engineId == KingEngineId.shadowsocks) {
      final links = <KingServerProfile>[];
      for (final line in text.split(RegExp(r'[\r\n]+'))) {
        final value = line.trim();
        if (!value.toLowerCase().startsWith('ss://')) continue;
        links.add(KingServerProfile(raw: value, format: KingServerConfigFormat.shadowsocksUri, sourceId: sourceId));
      }
      return _dedupe(links);
    }

    final generic = <KingServerProfile>[];
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final value = line.trim();
      if (RegExp(r'^(vless|vmess|trojan|ss)://', caseSensitive: false).hasMatch(value)) {
        generic.add(KingServerProfile(raw: value, format: KingServerConfigFormat.xrayUri, sourceId: sourceId));
      }
    }
    return _dedupe(generic);
  }

  List<KingServerProfile> _dedupe(List<KingServerProfile> values) {
    final seen = <String>{};
    return <KingServerProfile>[
      for (final value in values)
        if (seen.add(value.raw.toLowerCase())) value,
    ];
  }

  List<KingServerProfile>? _parseWireGuard(String text) {
    final sections = <String, Map<String, String>>{};
    String? current;
    for (final raw in text.split(RegExp(r'[\r\n]+'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
      final header = RegExp(r'^\[([^\]]+)\]$').firstMatch(line);
      if (header != null) {
        current = header.group(1)!.toLowerCase();
        sections.putIfAbsent(current, () => <String, String>{});
        continue;
      }
      final eq = line.indexOf('=');
      if (eq <= 0 || current == null) continue;
      sections[current]![line.substring(0, eq).trim().toLowerCase()] =
          line.substring(eq + 1).trim();
    }
    final iface = sections['interface'];
    final peer = sections['peer'];
    if (iface == null || peer == null) return null;
    final privateKey = _validKey(iface['privatekey']);
    final publicKey = _validKey(peer['publickey']);
    final endpoint = peer['endpoint'];
    final allowed = peer['allowedips'];
    if (!privateKey || !publicKey || endpoint == null || !_validEndpoint(endpoint) ||
        allowed == null || !_validAllowedIps(allowed)) return null;
    return <KingServerProfile>[
      KingServerProfile(raw: text, format: KingServerConfigFormat.wireGuardConfig),
    ];
  }

  bool _validKey(String? value) {
    if (value == null) return false;
    try { return base64.decode(base64.normalize(value)).length == 32; } catch (_) { return false; }
  }

  bool _validEndpoint(String value) {
    final endpoint = value.trim();
    if (endpoint.startsWith('[')) {
      final close = endpoint.indexOf(']');
      if (close < 2 || close + 2 >= endpoint.length || endpoint[close + 1] != ':') return false;
      final host = endpoint.substring(1, close);
      final port = int.tryParse(endpoint.substring(close + 2));
      return InternetAddress.tryParse(host) != null && port != null && port > 0 && port <= 65535;
    }
    final split = endpoint.lastIndexOf(':');
    if (split <= 0) return false;
    final host = endpoint.substring(0, split);
    final port = int.tryParse(endpoint.substring(split + 1));
    return host.isNotEmpty && port != null && port > 0 && port <= 65535;
  }

  bool _validAllowedIps(String value) {
    for (final raw in value.split(',')) {
      final item = raw.trim();
      final split = item.lastIndexOf('/');
      if (split <= 0) return false;
      final address = InternetAddress.tryParse(item.substring(0, split));
      final prefix = int.tryParse(item.substring(split + 1));
      if (address == null || prefix == null) return false;
      final maxPrefix = address.type == InternetAddressType.IPv4 ? 32 : 128;
      if (prefix < 0 || prefix > maxPrefix) return false;
    }
    return true;
  }
}

class KingServerSourceSync {
  KingServerSourceSync({Future<String> Function(String url)? fetchText})
      : _fetchText = fetchText ?? _defaultFetch;

  final Future<String> Function(String url) _fetchText;
  final KingServerPayloadParser _parser = const KingServerPayloadParser();

  Future<KingServerSourceSyncResult> refresh(String engineId) async {
    final profiles = <String, KingServerProfile>{};
    final failures = <KingServerSourceFailure>[];
    for (final source in KingEngineServerSourceCatalog.forEngine(engineId)) {
      try {
        final payload = await _fetchText(source.url);
        for (final profile in _parser.parse(
          engineId: engineId, payload: payload, sourceId: source.id,
        )) {
          profiles.putIfAbsent(profile.raw.toLowerCase(), () => profile);
        }
      } catch (error) {
        failures.add(KingServerSourceFailure(sourceId: source.id, message: error.toString()));
      }
    }
    return KingServerSourceSyncResult(
      profiles: profiles.values.toList(growable: false),
      failures: failures,
    );
  }

  static Future<String> _defaultFetch(String url) async {
    final fetcher = KingHttpSourceFetcher();
    try { return await fetcher.fetch(url); } finally { fetcher.close(force: true); }
  }
}

class KingHttpSourceFetcher {
  final HttpClient _client = HttpClient();

  Future<String> fetch(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Only credential-free HTTPS source URLs are accepted');
    }
    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 15));
    request.headers.set(HttpHeaders.userAgentHeader, 'KING-VPN-SourceSync/1.0');
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Source returned HTTP ${response.statusCode}', uri: uri);
    }
    return await utf8.decoder.bind(response).join();
  }

  void close({bool force = false}) => _client.close(force: force);
}

class KingServerSourceRefreshScheduler {
  KingServerSourceRefreshScheduler({
    required this.sync,
    required this.onResult,
  });

  final KingServerSourceSync sync;
  final Future<void> Function(KingServerSourceSyncResult result) onResult;
  final Map<String, Future<KingServerSourceSyncResult>> _inFlight = {};
  bool _disposed = false;

  static Duration? intervalForSource(KingServerSource source) {
    final cadence = source.updateCadence?.trim().toLowerCase();
    if (cadence == null || cadence.isEmpty) return null;
    final minutes = RegExp(r'^(\d+)m$').firstMatch(cadence);
    if (minutes != null) return Duration(minutes: int.parse(minutes.group(1)!));
    if (cadence == 'hourly' || cadence == '1h') return const Duration(hours: 1);
    if (cadence == 'daily' || cadence == '24h') return const Duration(hours: 24);
    final hours = RegExp(r'^(\d+)h$').firstMatch(cadence);
    if (hours != null) return Duration(hours: int.parse(hours.group(1)!));
    return null;
  }

  Future<KingServerSourceSyncResult> refreshNow(String engineId) {
    if (_disposed) return Future<KingServerSourceSyncResult>.error(StateError('scheduler disposed'));
    final existing = _inFlight[engineId];
    if (existing != null) return existing;
    late Future<KingServerSourceSyncResult> future;
    future = sync.refresh(engineId).then((result) async {
      if (!_disposed) await onResult(result);
      return result;
    }).whenComplete(() {
      if (identical(_inFlight[engineId], future)) _inFlight.remove(engineId);
    });
    _inFlight[engineId] = future;
    return future;
  }

  void dispose() {
    _disposed = true;
    _inFlight.clear();
  }
}

class KingAdaptiveBatchResult<T, R> {
  const KingAdaptiveBatchResult({
    required this.item,
    required this.succeeded,
    this.value,
    this.error,
  });
  final T item;
  final bool succeeded;
  final R? value;
  final Object? error;
}

class KingAdaptiveBatchRunner {
  KingAdaptiveBatchRunner._();

  static Future<List<KingAdaptiveBatchResult<T, R>>> run<T, R>({
    required Iterable<T> items,
    required int initialBatchSize,
    required Future<R> Function(T item) probe,
    int Function(int previousBatchSize, int completedItems)? nextBatchSize,
  }) async {
    if (initialBatchSize <= 0) throw ArgumentError.value(initialBatchSize, 'initialBatchSize');
    var batchSize = initialBatchSize;
    var inBatch = 0;
    var completed = 0;
    final results = <KingAdaptiveBatchResult<T, R>>[];
    for (final item in items) {
      try {
        final value = await probe(item);
        results.add(KingAdaptiveBatchResult<T, R>(item: item, succeeded: true, value: value));
      } catch (error) {
        results.add(KingAdaptiveBatchResult<T, R>(item: item, succeeded: false, error: error));
      }
      completed++;
      inBatch++;
      if (inBatch >= batchSize && nextBatchSize != null) {
        final next = nextBatchSize(batchSize, completed);
        if (next <= 0) throw ArgumentError.value(next, 'nextBatchSize');
        batchSize = next;
        inBatch = 0;
      }
    }
    return results;
  }
}
