import 'dart:async';
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
    'vless', 'vmess', 'trojan', 'ss', 'hysteria2', 'hy2', 'wireguard',
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

    // Hysteria 2 share links are parsed explicitly before the generic
    // multi-protocol path so URI authority/auth data is retained verbatim.
    if (engineId == 'hysteria2' || engineId == 'sing_box') {
      final hysteriaProfiles = <KingImportedServerProfile>[];
      final hysteriaSeen = <String>{};
      for (final line in value.split(RegExp(r'[\\r\\n]+'))) {
        final item = line.trim();
        if (item.isEmpty || item.startsWith('#') || item.startsWith(';')) continue;
        final uri = Uri.tryParse(item);
        final scheme = uri?.scheme.toLowerCase();
        if (uri == null || !const {'hy2', 'hysteria2'}.contains(scheme) ||
            uri.host.isEmpty || uri.port < 1 || uri.port > 65535) {
          continue;
        }
        final profile = KingImportedServerProfile(
          engineId: engineId,
          format: KingServerConfigFormat.hysteria2Uri,
          raw: item,
          sourceId: sourceId,
        );
        if (hysteriaSeen.add(profile.fingerprint)) {
          hysteriaProfiles.add(profile);
        }
      }
      if (hysteriaProfiles.isNotEmpty) {
        return List.unmodifiable(hysteriaProfiles);
      }
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
        'wireguard' => KingServerConfigFormat.wireGuardConfig,
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
    if (engineId != 'xray' && engineId != 'sing_box') return const [];
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
      if (!_supports(engineId, _engineForScheme(type))) continue;
      if (engineId == 'sing_box' && !_hasUsableSingBoxEndpoint(type, outbound)) {
        continue;
      }
      supported.add(type);
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

  bool _hasUsableSingBoxEndpoint(String type, Map outbound) {
    if (type == 'wireguard') {
      final peers = outbound['peers'];
      return peers is List && peers.isNotEmpty;
    }
    final server = outbound['server'];
    final rawPort = outbound['server_port'];
    final port = rawPort is int ? rawPort : int.tryParse('$rawPort');
    return server is String && server.trim().isNotEmpty &&
        port != null && port > 0 && port <= 65535;
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

  bool _isOpenVpnProfile(String value) {
    final lines = value
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#') && !line.startsWith(';'))
        .toList(growable: false);
    final hasClientMode = lines.any((line) {
      final normalized = line.toLowerCase();
      return normalized == 'client' || normalized == 'tls-client';
    });
    final hasRemote = lines.any((line) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 3 || parts[0].toLowerCase() != 'remote') return false;
      final host = parts[1];
      final port = int.tryParse(parts[2]);
      return host.isNotEmpty &&
          !host.contains(RegExp(r'[\s/@]')) &&
          port != null && port > 0 && port <= 65535;
    });
    final transports = <String>{
      'udp', 'udp4', 'udp6', 'tcp', 'tcp4', 'tcp6',
      'udp-client', 'tcp-client',
    };
    final hasTransport = lines.any((line) {
      final parts = line.split(RegExp(r'\s+'));
      return parts.length >= 2 &&
          parts[0].toLowerCase() == 'proto' &&
          transports.contains(parts[1].toLowerCase());
    });
    return hasClientMode && hasRemote && hasTransport;
  }

  bool _isWireGuardProfile(String value) {
    final interface = RegExp(
      r'^\s*\[Interface\]\s*(.*?)^(?=\s*\[|\s*$)', multiLine: true, caseSensitive: false, dotAll: true).firstMatch(value)?.group(1) ?? '';
    final peer = RegExp(
      r'^\s*\[Peer\]\s*(.*?)^(?=\s*\[|\s*$)', multiLine: true, caseSensitive: false, dotAll: true).firstMatch(value)?.group(1) ?? '';
    final privateKey = RegExp(r'^\s*PrivateKey\s*=\s*([^\s#]+)', multiLine: true, caseSensitive: false)
        .firstMatch(interface)?.group(1);
    final publicKey = RegExp(r'^\s*PublicKey\s*=\s*([^\s#]+)', multiLine: true, caseSensitive: false)
        .firstMatch(peer)?.group(1);
    final endpoint = RegExp(
      r'^\s*Endpoint\s*=\s*(\[[0-9a-fA-F:]+\]|[^:\s]+):(\d{1,5})\s*$', multiLine: true, caseSensitive: false).firstMatch(peer);
    final port = int.tryParse(endpoint?.group(2) ?? '');
    final allowedIpLine = RegExp(r'^\s*AllowedIPs\s*=\s*([^\r\n#]+)', multiLine: true, caseSensitive: false)
        .firstMatch(peer)?.group(1);

    if (interface.isEmpty || peer.isEmpty ||
        !_isWireGuardKey(privateKey) || !_isWireGuardKey(publicKey) ||
        endpoint == null || port == null || port < 1 || port > 65535 ||
        allowedIpLine == null || allowedIpLine.trim().isEmpty) {
      return false;
    }

    final endpointHost = endpoint.group(1)!.replaceAll(RegExp(r'^\[|\]$'), '');
    if (endpointHost.isEmpty ||
        endpointHost.contains(RegExp(r'\s')) ||
        endpointHost.contains('/') ||
        endpointHost.contains('@')) {
      return false;
    }

    final allowedIps = allowedIpLine.split(',');
    if (allowedIps.isEmpty) return false;
    for (final item in allowedIps) {
      final parts = item.trim().split('/');
      if (parts.length != 2) return false;
      final address = InternetAddress.tryParse(parts[0]);
      final prefix = int.tryParse(parts[1].trim());
      if (address == null || prefix == null) return false;
      final maxPrefix = address.type == InternetAddressType.IPv4 ? 32 : 128;
      if (prefix < 0 || prefix > maxPrefix) return false;
    }
    return true;
  }

  bool _isWireGuardKey(String? value) {
    if (value == null || value.isEmpty) return false;
    try {
      return base64.decode(base64.normalize(value)).length == 32;
    } catch (_) {
      return false;
    }
  }

  bool _containsAmneziaParameters(String value) =>
      RegExp(
        r'^\s*(Jc|Jmin|Jmax|S[1-4]|I[1-5]|H[1-4]|HeaderProtectionKey|RandomTrailers)\s*=', multiLine: true, caseSensitive: false).hasMatch(value);

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
    if (uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasFragment) {
      throw const FormatException(
        'Only absolute HTTPS source URLs without credentials or fragments are accepted',
      );
    }
    final request = await _client.getUrl(uri).timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, 'text/plain, application/json, */*');
    request.headers.set(HttpHeaders.userAgentHeader, 'KING-VPN-SourceSync/1.0');
    final response = await request.close().timeout(timeout);
    // HttpClient follows redirects by default. A trusted HTTPS feed must never
    // be silently downgraded to cleartext during that redirect chain.
    for (final redirect in response.redirects) {
      final target = redirect.location.hasScheme
          ? redirect.location
          : uri.resolveUri(redirect.location);
      if (target.scheme.toLowerCase() != 'https' ||
          target.host.isEmpty ||
          target.userInfo.isNotEmpty) {
        await response.drain<void>();
        throw const FormatException(
          'Source redirect must remain an absolute HTTPS URL without credentials',
        );
      }
    }
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
            final downloadUri = Uri.tryParse(downloadUrl);
            if (!name.toLowerCase().endsWith('.ovpn') ||
                downloadUri == null ||
                downloadUri.scheme.toLowerCase() != 'https' ||
                downloadUri.host.isEmpty ||
                downloadUri.userInfo.isNotEmpty ||
                downloadUri.hasFragment) {
              continue;
            }
            final config = await fetchText(downloadUri.toString());
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


/// Schedules refreshes at the fastest cadence explicitly published by the
/// sources for each engine. Unknown cadences are never guessed. Call
/// refreshNow once on app startup, then start periodic refreshes.
class KingServerSourceRefreshScheduler {
  KingServerSourceRefreshScheduler({
    required this.sync,
    required this.onResult,
  });

  final KingServerSourceSync sync;
  final Future<void> Function(KingServerSyncResult result) onResult;
  final Map<String, Timer> _timers = {};
  final Map<String, Future<KingServerSyncResult>> _inFlight = {};
  bool _disposed = false;

  void start({Iterable<String>? engineIds}) {
    if (_disposed) throw StateError('Refresh scheduler is disposed');
    final ids = engineIds ??
        KingEngineServerSourceCatalog.online.expand((s) => s.engineIds).toSet();
    for (final engineId in ids) {
      final intervals = KingEngineServerSourceCatalog.forEngine(engineId)
          .map(intervalForSource)
          .whereType<Duration>()
          .toList(growable: false);
      if (intervals.isEmpty || _timers.containsKey(engineId)) continue;
      intervals.sort((a, b) => a.compareTo(b));
      final interval = intervals.first;
      _timers[engineId] = Timer.periodic(interval, (_) {
        unawaited(refreshNow(engineId).then(onResult).catchError((Object _) {}));
      });
    }
  }

  Future<KingServerSyncResult> refreshNow(String engineId) {
    if (_disposed) {
      return Future.error(StateError('Refresh scheduler is disposed'));
    }
    final active = _inFlight[engineId];
    if (active != null) return active;
    late final Future<KingServerSyncResult> tracked;
    tracked = sync.refresh(engineId).whenComplete(() {
      if (identical(_inFlight[engineId], tracked)) _inFlight.remove(engineId);
    });
    _inFlight[engineId] = tracked;
    return tracked;
  }

  static Duration? intervalForSource(KingEngineServerSource source) {
    final cadence = source.updateCadence?.trim().toLowerCase();
    if (cadence == null || cadence.isEmpty) return null;
    if (cadence == 'daily') return const Duration(days: 1);
    if (cadence == 'hourly') return const Duration(hours: 1);
    final match = RegExp(
      r'^(\d+)\s*(m|min|mins|minute|minutes|h|hr|hrs|hour|hours)$',
    ).firstMatch(cadence);
    if (match == null) return null;
    final amount = int.tryParse(match.group(1)!);
    if (amount == null || amount <= 0) return null;
    final unit = match.group(2)!;
    return unit.startsWith('m')
        ? Duration(minutes: amount)
        : Duration(hours: amount);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}

/// Protocol-aware sources. A source is never assigned to an engine merely
/// because its URL is reachable; its published formats must match.
class KingEngineServerSourceCatalog {
  static const List<KingEngineServerSource> online = [
    KingEngineServerSource(
      id: 'morpheusadam_hysteria2',
      name: 'morpheusadam v2ray-config',
      url: 'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/subs/bundles/hysteria2.txt',
      kind: KingServerSourceKind.publicSubscription,
      formats: {KingServerConfigFormat.mixedShareLinks},
      engineIds: {'hysteria2', 'sing_box'},
      updateCadence: 'daily',
      notes: 'Dedicated Hysteria2 URI bundle; publisher rebuilds protocol bundles daily.',
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
      id: 'morpheusadam_wireguard',
      name: 'morpheusadam WireGuard bundle',
      url: 'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/subs/bundles/wireguard.txt',
      kind: KingServerSourceKind.publicSubscription,
      formats: {KingServerConfigFormat.mixedShareLinks},
      engineIds: {'wireguard', 'sing_box'},
      updateCadence: 'daily',
      notes: 'Dedicated WireGuard bundle; entries require protocol-specific parsing and endpoint verification.',
    ),
    KingEngineServerSource(
      id: 'radikal_hysteria2',
      name: '0xRadikal Hysteria2',
      url: 'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/protocols/hysteria2.txt',
      kind: KingServerSourceKind.publicSubscription,
      formats: {KingServerConfigFormat.hysteria2Uri},
      engineIds: {'hysteria2', 'sing_box'},
      updateCadence: '15m',
      notes: 'Publisher advertises a 15-minute update cycle; live repository activity was observed within minutes of this audit.',
    ),
    KingEngineServerSource(
      id: 'radikal_singbox',
      name: '0xRadikal sing-box JSON',
      url: 'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/all/singbox.json',
      kind: KingServerSourceKind.publicSubscription,
      formats: {KingServerConfigFormat.singBoxJson},
      engineIds: {'sing_box'},
      updateCadence: 'hourly',
      notes: 'Publisher advertises a 15-minute update cycle; JSON contains multiple proxy outbounds including Hysteria2 and Shadowsocks.',
    ),
    KingEngineServerSource(
      id: 'mohammadaz2_shadowsocks',
      name: 'mohammadaz2 hourly Shadowsocks',
      url: 'https://raw.githubusercontent.com/mohammadaz2/v2rayConfigsForYou/main/sub/ss.txt',
      kind: KingServerSourceKind.publicSubscription,
      formats: {KingServerConfigFormat.shadowsocksUri},
      engineIds: {'shadowsocks', 'sing_box'},
      updateCadence: 'hourly',
      notes: 'Repository documents hourly scraping and TCP reachability validation; latest repository update observed on 2026-11-26.',
    ),
    KingEngineServerSource(
      id: 'radikal_shadowsocks',
      name: '0xRadikal Shadowsocks',
      url: 'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/protocols/shadowsocks.txt',
      kind: KingServerSourceKind.publicSubscription,
      formats: {KingServerConfigFormat.shadowsocksUri},
      engineIds: {'shadowsocks', 'sing_box'},
      updateCadence: 'hourly',
      notes: 'Publisher advertises a 15-minute update cycle; protocol-specific plain-text feed.',
    ),
    KingEngineServerSource(
      id: 'shatak_hysteria2_ae',
      name: 'ShatakVPN Hysteria2 AE',
      url: 'https://raw.githubusercontent.com/ShatakVPN/ConfigForge-V2Ray/main/configs/ae/hysteria2.txt',
      kind: KingServerSourceKind.publicSubscription,
      formats: {KingServerConfigFormat.hysteria2Uri},
      engineIds: {'hysteria2', 'sing_box'},
      updateCadence: 'daily',
      notes: 'Repository automation published a fresh commit within the last day; this country feed was fetched and parsed as Hysteria2 URIs.',
    ),
    KingEngineServerSource(
      id: 'shatak_shadowsocks',
      name: 'ShatakVPN Shadowsocks',
      url: 'https://raw.githubusercontent.com/ShatakVPN/ConfigForge-V2Ray/main/configs/shadowsocks.txt',
      kind: KingServerSourceKind.publicSubscription,
      formats: {KingServerConfigFormat.shadowsocksUri},
      engineIds: {'shadowsocks', 'sing_box'},
      updateCadence: 'daily',
      notes: 'Repository automation published a fresh commit within the last day; dedicated Shadowsocks feed.',
    ),
    KingEngineServerSource(
      id: 'tendream_hysteria2',
      name: '10Dream Hysteria2 Base64',
      url: 'https://raw.githubusercontent.com/10Dream/sub-mod/main/sub/base64/10ium-VpnClashFaCollector-hysteria2.txt',
      kind: KingServerSourceKind.publicSubscription,
      formats: {KingServerConfigFormat.mixedShareLinks},
      engineIds: {'hysteria2', 'sing_box'},
      updateCadence: 'daily',
      notes: 'Repository automation published a fresh commit within the last day; payload is Base64-encoded Hysteria2 links.',
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