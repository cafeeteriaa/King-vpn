import 'dart:convert';
import 'dart:io';

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

class KingImportedServerProfile {
  const KingImportedServerProfile({
    required this.engineId,
    required this.format,
    required this.raw,
    required this.sourceId,
    this.name,
  });

  final String engineId;
  final KingServerConfigFormat format;
  final String raw;
  final String sourceId;
  final String? name;

  String get fingerprint => '${engineId}:${format.name}:${raw.trim()}';
}

/// Parses only formats that can be identified from their syntax. It does not
/// authenticate a server or prove that a profile is reachable.
class KingServerPayloadParser {
  static const _shareSchemes = {
    'vless', 'vmess', 'trojan', 'ss', 'hysteria2', 'hy2',
  };

  List<KingImportedServerProfile> parse({
    required String engineId,
    required String payload,
    String sourceId = 'offline',
  }) {
    final text = payload.trim();
    if (text.isEmpty) return const [];
    final decoded = _decodeIfBase64(text);
    final value = decoded.trim();

    final jsonProfiles = _parseJson(engineId, value, sourceId);
    if (jsonProfiles.isNotEmpty) return jsonProfiles;

    if (_isOpenVpnProfile(value) && engineId == 'openvpn') {
      return [KingImportedServerProfile(
        engineId: engineId, format: KingServerConfigFormat.openVpnProfile,
        raw: value, sourceId: sourceId,
      )];
    }

    if (_isWireGuardProfile(value)) {
      final isAwg = _containsAmneziaParameters(value);
      final target = isAwg ? 'amneziawg' : 'wireguard';
      if (engineId == target || engineId == 'sing_box') {
        return [KingImportedServerProfile(
          engineId: engineId,
          format: isAwg ? KingServerConfigFormat.amneziaWgConfig
              : KingServerConfigFormat.wireGuardConfig,
          raw: value, sourceId: sourceId,
        )];
      }
    }

    if (engineId == 'openconnect' && _isHttpsEndpoint(value)) {
      return [KingImportedServerProfile(
        engineId: engineId, format: KingServerConfigFormat.openConnectEndpoint,
        raw: value, sourceId: sourceId,
      )];
    }

    if (engineId == 'shroudly') {
      final proxyProfiles = <KingImportedServerProfile>[];
      for (final line in value.split(RegExp(r'[\r\n]+'))) {
        final item = line.trim();
        final uri = Uri.tryParse(item);
        if (uri != null && const {'socks5', 'socks5h', 'http', 'https'}.contains(uri.scheme.toLowerCase()) && uri.host.isNotEmpty) {
          proxyProfiles.add(KingImportedServerProfile(
            engineId: engineId, format: KingServerConfigFormat.socksOrHttpProxy,
            raw: item, sourceId: sourceId,
          ));
        }
      }
      if (proxyProfiles.isNotEmpty) return List.unmodifiable(proxyProfiles);
    }

    final found = <KingImportedServerProfile>[];
    final seen = <String>{};
    for (final line in value.split(RegExp(r'[\r\n]+'))) {
      final item = line.trim();
      if (item.isEmpty || item.startsWith('#') || item.startsWith(';')) continue;
      final uri = Uri.tryParse(item);
      final scheme = uri?.scheme.toLowerCase();
      if (scheme == null || !_shareSchemes.contains(scheme)) continue;
      final target = _engineForScheme(scheme);
      if (!_supports(engineId, target)) continue;
      final format = switch (scheme) {
        'hysteria2' || 'hy2' => KingServerConfigFormat.hysteria2Uri,
        'ss' => KingServerConfigFormat.shadowsocksUri,
        _ => KingServerConfigFormat.mixedShareLinks,
      };
      final profile = KingImportedServerProfile(
        engineId: engineId, format: format, raw: item, sourceId: sourceId,
      );
      if (seen.add(profile.fingerprint)) found.add(profile);
    }
    return List.unmodifiable(found);
  }

  List<KingImportedServerProfile> _parseJson(
    String engineId, String payload, String sourceId,
  ) {
    if (!payload.startsWith('{') && !payload.startsWith('[')) return const [];
    dynamic decoded;
    try { decoded = jsonDecode(payload); } catch (_) { return const []; }
    if (decoded is! Map<String, dynamic>) return const [];
    final outbounds = decoded['outbounds'];
    if (outbounds is! List) return const [];
    final supported = <String>{};
    for (final outbound in outbounds) {
      if (outbound is! Map) continue;
      final type = (outbound['type'] ?? outbound['protocol'] ?? '').toString().toLowerCase();
      if (type.isEmpty) continue;
      if (engineId == 'sing_box' && const {
        'direct', 'block', 'dns', 'selector', 'urltest', 'url_test',
      }.contains(type)) continue;
      if (_supports(engineId, _engineForScheme(type))) supported.add(type);
    }
    if (supported.isEmpty) return const [];
    final format = engineId == 'xray'
        ? KingServerConfigFormat.xraySubscription
        : KingServerConfigFormat.singBoxJson;
    return [KingImportedServerProfile(
      engineId: engineId, format: format, raw: payload, sourceId: sourceId,
      name: 'JSON profile (${supported.join(', ')})',
    )];
  }

  String _decodeIfBase64(String input) {
    if (input.contains('://') || input.startsWith('{') || input.startsWith('[')) {
      return input;
    }
    final compact = input.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 16 || !RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(compact)) {
      return input;
    }
    try {
      final normalized = base64.normalize(compact.replaceAll('-', '+').replaceAll('_', '/'));
      final decoded = utf8.decode(base64.decode(normalized));
      if (decoded.contains('://') || decoded.trimLeft().startsWith('{')) return decoded;
    } catch (_) {}
    return input;
  }

  bool _isOpenVpnProfile(String value) =>
      RegExp(r'(?im)^\s*client\s*$').hasMatch(value) &&
      RegExp(r'(?im)^\s*remote\s+\S+\s+\d+').hasMatch(value);

  bool _isWireGuardProfile(String value) =>
      RegExp(r'(?im)^\s*\[Interface\]\s*$').hasMatch(value) &&
      RegExp(r'(?im)^\s*\[Peer\]\s*$').hasMatch(value);

  bool _containsAmneziaParameters(String value) =>
      RegExp(r'(?im)^\s*(Jc|Jmin|Jmax|S1|S2|H1|H2|H3|H4)\s*=').hasMatch(value);

  bool _isHttpsEndpoint(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme.toLowerCase() == 'https' && uri.host.isNotEmpty;
  }

  String _engineForScheme(String scheme) => switch (scheme) {
    'hysteria2' || 'hy2' => 'hysteria2',
    'ss' || 'shadowsocks' => 'shadowsocks',
    'vless' || 'vmess' || 'trojan' => 'xray',
    'wireguard' => 'wireguard',
    _ => scheme,
  };

  bool _supports(String requested, String detected) {
    if (requested == detected) return true;
    if (requested == 'sing_box') {
      return const {'xray', 'hysteria2', 'shadowsocks', 'wireguard'}.contains(detected);
    }
    if (requested == 'xray') return detected == 'xray';
    return false;
  }
}

/// Fetches only HTTPS sources, keeps TLS verification enabled, and leaves
/// source failures isolated so one dead feed cannot discard successful feeds.
class KingHttpSourceFetcher {
  KingHttpSourceFetcher({HttpClient? client, this.timeout = const Duration(seconds: 35)})
      : _client = client ?? HttpClient();

  final HttpClient _client;
  final Duration timeout;

  Future<String> fetch(String sourceUrl) async {
    final uri = Uri.parse(sourceUrl);
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('Only absolute HTTPS source URLs are accepted');
    }
    final request = await _client.getUrl(uri).timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, 'text/plain, application/json, */*');
    request.headers.set(HttpHeaders.userAgentHeader, 'KING-VPN-SourceSync/1.0');
    final response = await request.close().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException('Source returned HTTP ${response.statusCode}', uri: uri);
    }
    return response.transform(utf8.decoder).join().timeout(timeout);
  }

  void close({bool force = false}) => _client.close(force: force);
}

class KingServerSourceFailure {
  const KingServerSourceFailure(this.sourceId, this.message);
  final String sourceId;
  final String message;
}

class KingServerSyncResult {
  const KingServerSyncResult({
    required this.engineId,
    required this.profiles,
    required this.failures,
  });
  final String engineId;
  final List<KingImportedServerProfile> profiles;
  final List<KingServerSourceFailure> failures;
}

/// Source refresh is exhaustive over the registered source iterable. There is
/// no fixed source-count or profile-count ceiling; results are deduplicated by
/// exact engine/format/payload identity. Provider outages never erase old data.
class KingServerSourceSync {
  KingServerSourceSync({
    required this.fetchText,
    KingServerPayloadParser? parser,
  }) : _parser = parser ?? KingServerPayloadParser();

  final Future<String> Function(String url) fetchText;
  final KingServerPayloadParser _parser;

  Future<KingServerSyncResult> refresh(String engineId) async {
    final sources = KingEngineServerSourceCatalog.forEngine(engineId);
    final profiles = <KingImportedServerProfile>[];
    final fingerprints = <String>{};
    final failures = <KingServerSourceFailure>[];

    for (final source in sources) {
      try {
        final payload = await fetchText(source.url);
        if (source.kind == KingServerSourceKind.generatedDirectory) {
          final directory = jsonDecode(payload);
          if (directory is! List) {
            throw const FormatException('Generated directory response is not a JSON list');
          }
          for (final entry in directory) {
            if (entry is! Map) continue;
            final name = (entry['name'] ?? '').toString();
            final downloadUrl = (entry['download_url'] ?? '').toString();
            if (!name.toLowerCase().endsWith('.ovpn') || downloadUrl.isEmpty) continue;
            final config = await fetchText(downloadUrl);
            final parsed = _parser.parse(
              engineId: engineId, payload: config, sourceId: source.id,
            );
            for (final profile in parsed) {
              if (fingerprints.add(profile.fingerprint)) profiles.add(profile);
            }
          }
        } else {
          final parsed = _parser.parse(
            engineId: engineId, payload: payload, sourceId: source.id,
          );
          for (final profile in parsed) {
            if (fingerprints.add(profile.fingerprint)) profiles.add(profile);
          }
        }
      } catch (error) {
        failures.add(KingServerSourceFailure(source.id, error.toString()));
      }
    }
    return KingServerSyncResult(
      engineId: engineId,
      profiles: List.unmodifiable(profiles),
      failures: List.unmodifiable(failures),
    );
  }
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
      notes: 'Auto-generated public OpenVPN profile directory. Directory expansion into individual .ovpn files is a follow-up fetcher step; server availability is not guaranteed.',
    ),
  ];

  static const List<KingOfflineImportKind> offline = KingOfflineImportKind.values;

  static List<KingEngineServerSource> forEngine(String engineId) {
    final sources = <KingEngineServerSource>[
      ...online.where((source) => source.engineIds.contains(engineId)),
    ];
    if (engineId == 'xray') {
      sources.addAll(KingProxySourceCatalog.online.map((source) =>
        KingEngineServerSource(
          id: source.id,
          name: 'Xray public feed ${source.id}',
          url: source.url,
          kind: KingServerSourceKind.publicSubscription,
          formats: const {KingServerConfigFormat.mixedShareLinks},
          engineIds: const {'xray'},
          notes: 'Legacy Xray-compatible feed; payload must be parsed and validated.',
        )));
    }
    return List.unmodifiable(sources);
  }

  static List<KingProxySource> xrayFeeds() => KingProxySourceCatalog.online;

  static bool needsUserOrProviderServer(String engineId) => const {
    'nthlink', 'amneziawg', 'openconnect', 'wireguard',
  }.contains(engineId);

  static bool isLocalOnly(String engineId) => const {
    'shroudly', 'byedpi', 'powertunnel',
  }.contains(engineId);
}
