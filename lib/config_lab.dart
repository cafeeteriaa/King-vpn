import 'dart:convert';
import 'dart:io';

/// A parsed, editable share-link document. Secrets are kept in memory only and
/// are never included in scan summaries or diagnostic strings.
class KingConfigDocument {
  KingConfigDocument._(this.protocol, this._values, this._original);

  final String protocol;
  final Map<String, dynamic> _values;
  final String _original;

  String get address => (_values['add'] ?? _values['address'] ?? _values['_host'] ?? '').toString();
  int? get port => int.tryParse((_values['port'] ?? '').toString());
  String get sni => (_values['sni'] ?? _values['peer'] ?? '').toString();
  String get hostHeader => (_values['host'] ?? '').toString();
  String get network => (_values['net'] ?? _values['type'] ?? '').toString();

  Map<String, dynamic> get values => Map.unmodifiable(_values);

  static KingConfigDocument parse(String input) {
    final raw = input.trim();
    final marker = raw.indexOf('://');
    if (marker <= 0) throw const FormatException('Unsupported config link');
    final scheme = raw.substring(0, marker).toLowerCase();
    if (!const {'vmess', 'vless', 'trojan'}.contains(scheme)) {
      throw FormatException('Unsupported editable share-link protocol: $scheme');
    }
    if (scheme == 'vmess') {
      final encodedBody = raw.substring(marker + 3);
      final hashAt = encodedBody.indexOf('#');
      final fragment = hashAt < 0 ? '' : encodedBody.substring(hashAt + 1);
      var payload = (hashAt < 0 ? encodedBody : encodedBody.substring(0, hashAt))
          .split('?').first;
      payload = payload.replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = jsonDecode(utf8.decode(base64.decode(payload)));
      if (decoded is! Map) throw const FormatException('Invalid VMess JSON');
      return KingConfigDocument._(
        scheme,
        <String, dynamic>{
          ...Map<String, dynamic>.from(decoded),
          '_kingFragment': fragment,
        },
        raw,
      );
    }

    final uri = Uri.parse(raw);
    if (uri.host.isEmpty || uri.port < 1 || uri.port > 65535) {
      throw const FormatException('Missing or invalid endpoint');
    }
    return KingConfigDocument._(scheme, <String, dynamic>{
      '_userinfo': uri.userInfo,
      '_host': uri.host,
      'port': uri.port,
      '_fragment': uri.hasFragment ? uri.fragment : '',
      '_query': Map<String, String>.from(uri.queryParameters),
      '_path': uri.path,
    }, raw);
  }

  /// Returns a new config. Only fields meaningful to the selected share-link
  /// format are changed; credentials and unrelated query fields are preserved.
  KingConfigDocument withOverrides(Map<String, Object?> overrides) {
    final next = Map<String, dynamic>.from(_values);
    for (final entry in overrides.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value == null) continue;
      switch (key) {
        case 'address':
          if (protocol == 'vmess') {
            next['add'] = value.toString();
          } else {
            next['_host'] = value.toString();
          }
          break;
        case 'port':
          final parsed = int.tryParse(value.toString());
          if (parsed == null || parsed < 1 || parsed > 65535) {
            throw const FormatException('Port must be between 1 and 65535');
          }
          next['port'] = protocol == 'vmess' ? parsed.toString() : parsed;
          break;
        case 'sni':
          if (protocol == 'vmess') {
            if (value.toString().isEmpty) {
              next.remove('sni');
            } else {
              next['sni'] = value.toString();
            }
          } else {
            final q = Map<String, String>.from(next['_query'] as Map);
            if (value.toString().isEmpty) {
              q.remove('sni');
            } else {
              q['sni'] = value.toString();
            }
            next['_query'] = q;
          }
          break;
        case 'host':
          if (protocol == 'vmess') {
            if (value.toString().isEmpty) {
              next.remove('host');
            } else {
              next['host'] = value.toString();
            }
          } else {
            final q = Map<String, String>.from(next['_query'] as Map);
            if (value.toString().isEmpty) {
              q.remove('host');
            } else {
              q['host'] = value.toString();
            }
            next['_query'] = q;
          }
          break;
        case 'path':
        case 'type':
        case 'security':
        case 'fp':
        case 'alpn':
        case 'flow':
        case 'serviceName':
          final wireKey = key == 'type' ? 'type' : key;
          if (protocol == 'vmess') {
            final mapKey = key == 'type' ? 'net' : key;
            if (value.toString().isEmpty) {
              next.remove(mapKey);
            } else {
              next[mapKey] = value.toString();
            }
          } else {
            final q = Map<String, String>.from(next['_query'] as Map);
            if (value.toString().isEmpty) {
              q.remove(wireKey);
            } else {
              q[wireKey] = value.toString();
            }
            next['_query'] = q;
          }
          break;
        default:
          throw FormatException('Field is not editable in share-link format: $key');
      }
    }
    return KingConfigDocument._(protocol, next, _original);
  }

  String toShareLink() {
    if (protocol == 'vmess') {
      final jsonValues = Map<String, dynamic>.from(_values)
        ..remove('_kingFragment');
      final bytes = utf8.encode(jsonEncode(jsonValues));
      final encoded = base64Url.encode(bytes).replaceAll('=', '');
      final fragment = (_values['_kingFragment'] ?? '').toString();
      return 'vmess://$encoded${fragment.isEmpty ? '' : '#$fragment'}';
    }
    final query = Map<String, String>.from(_values['_query'] as Map);
    final uri = Uri(
      scheme: protocol,
      userInfo: _values['_userinfo']?.toString() ?? '',
      host: _values['_host']?.toString() ?? '',
      port: int.tryParse((_values['port'] ?? '').toString()),
      path: _values['_path']?.toString() ?? '',
      queryParameters: query.isEmpty ? null : query,
      fragment: (_values['_fragment'] ?? '').toString(),
    );
    return uri.toString();
  }

  String get originalLink => _original;
}

enum KingConfigProbeKind { dns, tcp, tls, httpHost }

class KingConfigProbe {
  const KingConfigProbe({
    required this.kind,
    required this.value,
    required this.success,
    this.latency,
    this.detail = '',
  });

  final KingConfigProbeKind kind;
  final String value;
  final bool success;
  final Duration? latency;
  final String detail;
}

class KingConfigVariant {
  const KingConfigVariant({
    required this.label,
    required this.config,
    required this.probes,
  });

  final String label;
  final String config;
  final List<KingConfigProbe> probes;

  bool get transportReachable =>
      probes.any((p) => p.kind == KingConfigProbeKind.tcp && p.success) ||
      probes.any((p) => p.kind == KingConfigProbeKind.tls && p.success);
}

/// Automatic, endpoint-scoped diagnostics. It never scans unrelated networks:
/// targets come from the supplied config and caller-provided values.
class KingConfigAutoScanner {
  const KingConfigAutoScanner();

  Future<List<KingConfigProbe>> scan(
    KingConfigDocument config, {
    Iterable<String> additionalSni = const [],
    Iterable<int> additionalPorts = const [],
    Duration timeout = const Duration(seconds: 4),
    bool Function()? cancelled,
  }) async {
    bool stopped() => cancelled?.call() ?? false;
    final results = <KingConfigProbe>[];
    final host = config.address.trim();
    if (host.isEmpty) return results;

    final addresses = <String>{};
    final dnsWatch = Stopwatch()..start();
    try {
      final parsed = InternetAddress.tryParse(host);
      if (parsed != null) {
        addresses.add(parsed.address);
      } else {
        final resolved = await InternetAddress.lookup(host).timeout(timeout);
        addresses.addAll(resolved.map((e) => e.address));
      }
      results.add(KingConfigProbe(
        kind: KingConfigProbeKind.dns,
        value: host,
        success: addresses.isNotEmpty,
        latency: dnsWatch.elapsed,
        detail: addresses.join(','),
      ));
    } catch (e) {
      results.add(KingConfigProbe(
        kind: KingConfigProbeKind.dns,
        value: host,
        success: false,
        latency: dnsWatch.elapsed,
        detail: e.runtimeType.toString(),
      ));
    }
    if (stopped()) return results;

    final ports = <int>{
      if (config.port != null) config.port!,
      ...additionalPorts.where((p) => p >= 1 && p <= 65535),
    };
    final snis = <String>{
      if (config.sni.isNotEmpty) config.sni,
      if (config.hostHeader.isNotEmpty) config.hostHeader,
      if (host.contains('.') && InternetAddress.tryParse(host) == null) host,
      ...additionalSni.map((e) => e.trim()).where((e) => e.isNotEmpty),
    };

    for (final ip in addresses) {
      for (final port in ports) {
        if (stopped()) return results;
        final watch = Stopwatch()..start();
        Socket? socket;
        try {
          socket = await Socket.connect(ip, port, timeout: timeout);
          results.add(KingConfigProbe(
            kind: KingConfigProbeKind.tcp,
            value: '$ip:$port',
            success: true,
            latency: watch.elapsed,
          ));
        } catch (e) {
          results.add(KingConfigProbe(
            kind: KingConfigProbeKind.tcp,
            value: '$ip:$port',
            success: false,
            latency: watch.elapsed,
            detail: e.runtimeType.toString(),
          ));
        } finally {
          socket?.destroy();
        }
        if (stopped()) return results;

        for (final sni in snis) {
          if (stopped()) return results;
          final tlsWatch = Stopwatch()..start();
          Socket? raw;
          SecureSocket? secure;
          try {
            raw = await Socket.connect(ip, port, timeout: timeout);
            secure = await SecureSocket.secure(raw, host: sni)
                .timeout(timeout);
            results.add(KingConfigProbe(
              kind: KingConfigProbeKind.tls,
              value: '$ip:$port SNI=$sni',
              success: true,
              latency: tlsWatch.elapsed,
              detail: 'TLS handshake completed; this is not proof of tunnel traffic.',
            ));
          } catch (e) {
            results.add(KingConfigProbe(
              kind: KingConfigProbeKind.tls,
              value: '$ip:$port SNI=$sni',
              success: false,
              latency: tlsWatch.elapsed,
              detail: e.runtimeType.toString(),
            ));
          } finally {
            secure?.destroy();
            raw?.destroy();
          }
        }
      }
    }
    return results;
  }

  /// Generates test variants by changing only values discovered on the
  /// configured endpoint. A caller must run the returned links through the
  /// actual VPN engine and real traffic checks before accepting one.
  List<KingConfigVariant> buildVariants(
    KingConfigDocument config, {
    Iterable<String> addresses = const [],
    Iterable<String> snis = const [],
    Iterable<int> ports = const [],
  }) {
    final variants = <KingConfigVariant>[];
    final seen = <String>{config.originalLink};
    final addressOptions = <String?>[
      null,
      ...addresses.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet(),
    ];
    final portOptions = <int?>[
      null,
      ...ports.where((e) => e >= 1 && e <= 65535).toSet(),
    ];
    final sniOptions = <String?>[
      null,
      ...snis.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet(),
    ];

    // Full Cartesian combinations are retained; no arbitrary variant-count
    // ceiling silently discards a tested combination.
    for (final address in addressOptions) {
      for (final port in portOptions) {
        for (final sni in sniOptions) {
          if (address == null && port == null && sni == null) continue;
          final changes = <String, Object?>{
            if (address != null) 'address': address,
            if (port != null) 'port': port,
            if (sni != null) 'sni': sni,
          };
          try {
            final link = config.withOverrides(changes).toShareLink();
            if (seen.add(link)) {
              final label = [
                if (address != null) 'Address $address',
                if (port != null) 'Port $port',
                if (sni != null) 'SNI $sni',
              ].join(' + ');
              variants.add(KingConfigVariant(
                label: label,
                config: link,
                probes: const [],
              ));
            }
          } on FormatException {
            // Unsupported field/protocol combinations are not emitted.
          }
        }
      }
    }
    return variants;
  }
}

/// Repair orchestrator: accepts a variant only when the injected real-engine
/// callback confirms both connection and end-to-end traffic.
class KingConfigRepairEngine {
  const KingConfigRepairEngine();

  Future<String?> chooseWorkingVariant(
    Iterable<KingConfigVariant> variants, {
    required Future<bool> Function(String config) connectAndVerifyTraffic,
    bool Function()? cancelled,
  }) async {
    for (final variant in variants) {
      if (cancelled?.call() ?? false) return null;
      try {
        if (await connectAndVerifyTraffic(variant.config)) {
          return variant.config;
        }
      } catch (_) {
        // Continue to the next generated variant; do not report false success.
      }
    }
    return null;
  }
}
