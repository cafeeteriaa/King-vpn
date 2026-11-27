part of 'main.dart';

// KING NATIONAL SCANNER (KNS)
// Unified registry/strategy layer over the existing national scanners.
// It preserves nip_scan, DNS/IP/SNI scanners and the Xray variant compiler.

enum KingNatCapabilityStatus {
  implementedVerified,
  implementedUntested,
  adapterAvailable,
  requiresServerInfrastructure,
  researchOnly,
  incompatible,
  rejectedForSecurityReasons,
}

class KingNatCapability {
  const KingNatCapability({
    required this.id,
    required this.family,
    required this.status,
    required this.source,
    required this.note,
    this.android = true,
    this.evidenceCount = 0,
    this.variantCount = 0,
  });

  final String id;
  final String family;
  final KingNatCapabilityStatus status;
  final String source;
  final String note;
  final bool android;
  final int evidenceCount;
  final int variantCount;

  String get statusLabel {
    switch (status) {
      case KingNatCapabilityStatus.implementedVerified:
        return 'Implemented & Verified';
      case KingNatCapabilityStatus.implementedUntested:
        return 'Implemented but Untested';
      case KingNatCapabilityStatus.adapterAvailable:
        return 'Adapter Available';
      case KingNatCapabilityStatus.requiresServerInfrastructure:
        return 'Requires Server Infrastructure';
      case KingNatCapabilityStatus.researchOnly:
        return 'Research Only';
      case KingNatCapabilityStatus.incompatible:
        return 'Incompatible';
      case KingNatCapabilityStatus.rejectedForSecurityReasons:
        return 'Rejected for Security Reasons';
    }
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'family': family,
        'status': statusLabel,
        'source': source,
        'note': note,
        'android': android,
        'evidenceCount': evidenceCount,
        'variantCount': variantCount,
      };
}

class _KingNatVariantStats {
  int attempts = 0;
  int successes = 0;
  int failures = 0;
  DateTime? lastAt;

  double get confidence => (successes + 1) / (attempts + 2);
}

class KingNationalScannerEngine {
  KingNationalScannerEngine._();

  static const String _prefsKey = 'king_nat_strategy_memory_v1';
  static const int _maxProfiles = 80;
  static const int _maxVariantsPerProfile = 128;
  static final Map<String, Map<int, _KingNatVariantStats>> _history =
      <String, Map<int, _KingNatVariantStats>>{};
  static final Map<String, int> _featureEvidence = <String, int>{};
  static int _recordCount = 0;
  static String _lastPlanKey = '';
  static bool _loaded = false;
  static bool _persistDirty = false;
  static Future<void>? _loadFlight;
  static Future<void>? _persistFlight;

  /// Privacy-preserving strategy profile: raw host is hashed; no IP, UUID,
  /// credential, or raw config is written to persistent memory.
  static String profileKey(Server s) {
    final protocol = s.link.contains('://')
        ? s.link.substring(0, s.link.indexOf('://')).toLowerCase()
        : 'unknown';
    final network = nationalMode ? 'national' : 'global';
    final transport = s.net.toLowerCase();
    final security = s.reality ? 'reality' : (s.cdn ? 'cdn-tls' : 'direct');
    final hostHash =
        sha256.convert(utf8.encode(s.host.toLowerCase())).toString().substring(0, 16);
    return <String>[
      network, protocol, transport, security, s.port.toString(), hostHash
    ].join('|');
  }

  static Future<void> load() async {
    if (_loaded) return;
    final active = _loadFlight;
    if (active != null) { await active; return; }
    final future = _loadFromPreferences();
    _loadFlight = future;
    try {
      await future;
    } finally {
      if (identical(_loadFlight, future)) _loadFlight = null;
    }
  }

  static Future<void> _loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != 1) return;
      final profiles = decoded['profiles'];
      if (profiles is! Map) return;
      for (final profileEntry in profiles.entries.take(_maxProfiles)) {
        final rawVariants = profileEntry.value;
        if (rawVariants is! Map) continue;
        final variants = <int, _KingNatVariantStats>{};
        for (final variantEntry
            in rawVariants.entries.take(_maxVariantsPerProfile)) {
          final variant = int.tryParse(variantEntry.key.toString());
          final values = variantEntry.value;
          if (variant == null ||
              variant <= 0 ||
              variant >= _natSpecs.length ||
              values is! Map) continue;
          final attempts = values['a'];
          final successes = values['s'];
          final failures = values['f'];
          if (attempts is! num || successes is! num || failures is! num) continue;
          final stat = _KingNatVariantStats()
            ..attempts = attempts.toInt().clamp(0, 1000000).toInt()
            ..successes = successes.toInt().clamp(0, 1000000).toInt()
            ..failures = failures.toInt().clamp(0, 1000000).toInt();
          final stamp = values['t'];
          if (stamp is num && stamp > 0) {
            stat.lastAt = DateTime.fromMillisecondsSinceEpoch(stamp.toInt());
          }
          variants[variant] = stat;
          if (stat.successes > 0) {
            for (final id in _featuresFor(_natSpecs[variant])) {
              _featureEvidence[id] = (_featureEvidence[id] ?? 0) + stat.successes;
            }
          }
        }
        if (variants.isNotEmpty) {
          _history[profileEntry.key.toString()] = variants;
        }
      }
      _recordCount = _history.values.fold<int>(
        0,
        (sum, variants) =>
            sum + variants.values.fold<int>(0, (n, stat) => n + stat.attempts),
      );
    } catch (e, st) {
      logError(e, st);
    } finally {
      _loaded = true;
    }
  }

  static void _schedulePersist() {
    _persistDirty = true;
    if (_persistFlight != null) return;
    final future = _persistLoop();
    _persistFlight = future;
    future.whenComplete(() {
      if (identical(_persistFlight, future)) _persistFlight = null;
      if (_persistDirty) _schedulePersist();
    });
  }

  static Future<void> _persistLoop() async {
    while (_persistDirty) {
      _persistDirty = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        final profiles = <String, Object?>{};
        for (final profileEntry in _history.entries) {
          final variants = <String, Object?>{};
          for (final variantEntry in profileEntry.value.entries) {
            final stat = variantEntry.value;
            variants[variantEntry.key.toString()] = <String, Object?>{
              'a': stat.attempts,
              's': stat.successes,
              'f': stat.failures,
              't': stat.lastAt?.millisecondsSinceEpoch ?? 0,
            };
          }
          profiles[profileEntry.key] = variants;
        }
        await prefs.setString(
          _prefsKey,
          jsonEncode(<String, Object?>{'version': 1, 'profiles': profiles}),
        );
      } catch (e, st) {
        logError(e, st);
      }
    }
  }

  static int _strategyCost(_NatSpec x) {
    var cost = 0;
    if (x.fp != null) cost += 1;
    if (x.alpn != null) cost += 1;
    if (x.frag != null) cost += 3;
    if (x.sniSwap != null) cost += 4;
    if (x.sniHost) cost += 2;
    if (x.other) cost += 3;
    if (x.port) cost += 3;
    if (x.clean) cost += 4;
    if (x.doh != null) cost += 2;
    if (x.noise) cost += 2;
    if (x.ed) cost += 2;
    if (x.mode != null) cost += 5;
    if (x.mss != null) cost += 1;
    return cost;
  }

  /// Uses the existing variant generator as source of truth. The plain
  /// configuration stays first; compatible candidates are then ranked using
  /// per-destination evidence, negative learning and transformation cost.
  static List<int> planVariants(Server server, {bool full = false}) {
    final proposed = _natOrder(server, full: full);
    final facts = _NatFacts(server);
    final result = <int>[];
    final seen = <int>{};

    for (final code in proposed) {
      final variant = code % _natCodeBase;
      if (variant < 0 || variant >= _natSpecs.length) continue;
      if (!seen.add(code)) continue;
      if (variant != 0) {
        if (natRetired(variant) || natVariantCooling(variant)) continue;
        if (!_natAppliesF(facts, variant)) continue;
        if (server.reality && _natChangesAddr(variant)) continue;
      }
      result.add(code);
    }

    if (!result.any((v) => v % _natCodeBase == 0)) {
      result.insert(0, 0);
    } else {
      final baseAt = result.indexWhere((v) => v % _natCodeBase == 0);
      if (baseAt > 0) result.insert(0, result.removeAt(baseAt));
    }

    final profile = _history[profileKey(server)];
    if (profile != null && profile.isNotEmpty && result.length > 3) {
      // Preserve the original config and the first cached/priority candidate.
      final fixedPrefix = result.take(2).toList();
      final tail = result.skip(fixedPrefix.length).toList();
      tail.sort((a, b) {
        double score(int code, int position) {
          final variant = code % _natCodeBase;
          final stats = profile[variant];
          if (stats == null || stats.attempts < 2) {
            return -position * 0.001;
          }
          return (stats.confidence * 100) -
              (stats.failures * 2.5) -
              _strategyCost(_natSpecs[variant]) -
              (position * 0.001);
        }
        return score(b, result.indexOf(b))
            .compareTo(score(a, result.indexOf(a)));
      });
      result
        ..clear()
        ..addAll(fixedPrefix)
        ..addAll(tail);
    }

    final key = profileKey(server) + '|n=' + result.length.toString();
    if (_lastPlanKey != key) {
      _lastPlanKey = key;
      dbg('KNS-PLAN: profile=' + profileKey(server) +
          ' • candidates=' + result.length.toString() +
          ' • registry=' + registry.length.toString() +
          ' • original-first=1');
    }
    return List<int>.unmodifiable(result);
  }

  /// Called only after CONNECTED + Android TUN + a real outbound traffic probe.
  /// Core delay alone is never recorded as a successful strategy.
  static void recordVariantOutcome(
    int variant,
    bool success, {
    String? profile,
  }) {
    if (variant <= 0 || variant >= _natSpecs.length) return;
    final key = (profile == null || profile.isEmpty) ? 'default' : profile;
    final profiles =
        _history.putIfAbsent(key, () => <int, _KingNatVariantStats>{});
    final stats = profiles.putIfAbsent(variant, _KingNatVariantStats.new);
    stats.attempts++;
    if (success) {
      stats.successes++;
      for (final id in _featuresFor(_natSpecs[variant])) {
        _featureEvidence[id] = (_featureEvidence[id] ?? 0) + 1;
      }
    } else {
      stats.failures++;
    }
    stats.lastAt = DateTime.now();
    _recordCount++;
    _schedulePersist();

    if (profiles.length > _maxVariantsPerProfile) {
      final oldest = profiles.entries.toList()
        ..sort((a, b) {
          final at = a.value.lastAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.value.lastAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return at.compareTo(bt);
        });
      for (final entry
          in oldest.take(profiles.length - _maxVariantsPerProfile)) {
        profiles.remove(entry.key);
      }
    }
    if (_history.length > _maxProfiles) {
      _history.remove(_history.keys.first);
    }
  }

  static Set<String> _featuresFor(_NatSpec x) {
    final out = <String>{};
    if (x.fp != null) out.add('tls_fingerprint');
    if (x.alpn != null) out.add('alpn_negotiation');
    if (x.frag != null) {
      out
        ..add('tls_hello_fragmentation')
        ..add('tcp_segmentation_compatibility');
    }
    if (x.sniSwap != null) out.add('sni_override');
    if (x.sniHost) out.add('sni_host_alignment');
    if (x.other) out.add('endpoint_fallback');
    if (x.port) out.add('cdn_port_fallback');
    if (x.clean) out.add('clean_endpoint_substitution');
    if (x.doh != null) out.add('doh_resolver');
    if (x.v4) out.add('ipv4_preference');
    if (x.tfo) out.add('tcp_fast_open');
    if (x.nodelay) out.add('tcp_nodelay');
    if (x.keep != null) out.add('tcp_keepalive');
    if (x.ed) out.add('early_data_compatibility');
    if (x.noise) out.add('padding_noise');
    if (x.mss != null) out.add('mss_adaptation');
    if (x.mode != null) out.add('transport_mode');
    return out;
  }

  static int _variantCount(String feature) {
    var count = 0;
    for (final x in _natSpecs) {
      if (_featuresFor(x).contains(feature)) count++;
    }
    return count;
  }

  static int _evidence(String feature) => _featureEvidence[feature] ?? 0;

  static List<KingNatCapability> get registry {
    final rows = <String, KingNatCapability>{};

    void implemented(String id, String family,
        {required String note,
        String source = 'lib/nat_ultra.dart → _NatSpec / natCfg',
        bool android = true}) {
      final evidence = _evidence(id);
      rows[id] = KingNatCapability(
        id: id,
        family: family,
        status: evidence > 0
            ? KingNatCapabilityStatus.implementedVerified
            : KingNatCapabilityStatus.implementedUntested,
        source: source,
        note: note,
        android: android,
        evidenceCount: evidence,
        variantCount: _variantCount(id),
      );
    }

    implemented('tls_fingerprint', 'TLS identity',
        note: 'Core fingerprint profiles; selected only when endpoint TLS is compatible.');
    implemented('alpn_negotiation', 'TLS negotiation',
        note: 'ALPN candidates are generated by the existing Xray config matrix.');
    implemented('tls_hello_fragmentation', 'Traffic transformation',
        note: 'Existing Xray freedom fragment adapter; no raw Android packet injection.');
    implemented('tcp_segmentation_compatibility', 'Traffic transformation',
        note: 'Fragment profile compatibility; verified only after real tunnel traffic.');
    implemented('sni_override', 'Destination identity / SNI',
        note: 'Existing CDN-only SNI swap; ECH and REALITY endpoints are excluded.');
    implemented('sni_host_alignment', 'Destination identity / SNI',
        note: 'Existing SNI-from-host profile; it does not claim to rewrite every HTTP Host header.');
    implemented('endpoint_fallback', 'Destination mapping',
        note: 'Existing alternate endpoint fallback; REALITY address substitution is blocked.');
    implemented('cdn_port_fallback', 'CDN compatibility',
        note: 'Existing compatible CDN port matrix; only supported endpoint families.');
    implemented('clean_endpoint_substitution', 'Destination mapping',
        note: 'Existing clean-IP substitution; original SNI/Host identity is preserved.');
    implemented('doh_resolver', 'DNS intelligence',
        note: 'Existing DoH candidates; resolver reachability is not treated as tunnel success.');
    implemented('ipv4_preference', 'Transport compatibility',
        note: 'Existing IPv4 preference variant.');
    implemented('tcp_fast_open', 'Transport compatibility',
        note: 'Existing TCP Fast Open socket option candidate.');
    implemented('tcp_nodelay', 'Transport compatibility',
        note: 'Existing TCP_NODELAY candidate.');
    implemented('tcp_keepalive', 'Transport compatibility',
        note: 'Existing keepalive candidates.');
    implemented('early_data_compatibility', 'Transport compatibility',
        note: 'Existing early-data candidates; only compatible WebSocket/TLS configurations.');
    implemented('padding_noise', 'Traffic transformation',
        note: 'Existing Xray fragment noise option; not arbitrary forged application payload.');
    implemented('mss_adaptation', 'Transport compatibility',
        note: 'MSS candidates are registered only when present in the current variant catalog.');
    implemented('transport_mode', 'Transport compatibility',
        note: 'Existing transport-mode variants; actual core support remains authoritative.');

    void reference(String id, String family, KingNatCapabilityStatus status,
        String note,
        {bool android = true,
        String source = 'Reference catalog; not activated by this registry'}) {
      rows[id] = KingNatCapability(
        id: id,
        family: family,
        status: status,
        source: source,
        note: note,
        android: android,
      );
    }

    // Explicit fake/forgery registry. No fake-packet technique is called
    // implemented unless a real, safe Core adapter exists in this repository.
    reference('fake_tcp_packet', 'Fake packet',
        KingNatCapabilityStatus.researchOnly,
        'No independent raw TCP fake-packet adapter is present in the current Android Core.');
    reference('fake_tls_packet', 'Fake packet',
        KingNatCapabilityStatus.researchOnly,
        'Fake TLS packet generation is not implemented as a standalone adapter.');
    reference('fake_http_request', 'Fake packet',
        KingNatCapabilityStatus.researchOnly,
        'HTTP request forgery is not enabled; Host/SNI compatibility is tracked separately.');
    reference('sequence_number_manipulation', 'TCP state transformation',
        KingNatCapabilityStatus.researchOnly,
        'Requires a packet-level transport adapter and sequence-space validation.');
    reference('ack_window_adaptation', 'TCP state transformation',
        KingNatCapabilityStatus.researchOnly,
        'Requires a packet-level adapter; not safe as a config-only rewrite.');
    reference('checksum_validation', 'Packet integrity',
        KingNatCapabilityStatus.researchOnly,
        'No raw packet checksum inspection hook is exposed by the current Core adapter.');
    reference('multi_split', 'DPI transformation',
        KingNatCapabilityStatus.adapterAvailable,
        'Existing fragment adapter is available; multi-split semantics require Core verification.');
    reference('multi_disorder', 'DPI transformation',
        KingNatCapabilityStatus.researchOnly,
        'Packet reordering requires a stateful transport adapter and reassembly validation.');
    reference('tls_record_segmentation', 'DPI transformation',
        KingNatCapabilityStatus.adapterAvailable,
        'TLS-hello fragmentation is available; arbitrary TLS-record segmentation is not claimed.');
    reference('sni_fragmentation', 'DPI transformation',
        KingNatCapabilityStatus.adapterAvailable,
        'SNI-bearing ClientHello fragmentation is available through the existing fragment profile.');
    reference('adaptive_padding', 'DPI transformation',
        KingNatCapabilityStatus.adapterAvailable,
        'Only the current Core fragment-noise adapter is available; no general padding engine is claimed.');
    reference('timing_jitter', 'DPI transformation',
        KingNatCapabilityStatus.researchOnly,
        'No independent packet scheduler/timing adapter is exposed.');
    reference('udp_datagram_transformation', 'UDP transport',
        KingNatCapabilityStatus.researchOnly,
        'No generic UDP packet rewrite adapter is present.');
    reference('quic_compatibility', 'QUIC transport',
        KingNatCapabilityStatus.researchOnly,
        'Requires an explicitly supported QUIC Core and endpoint handshake validation.');

    for (final id in const ['vless', 'vmess', 'trojan', 'shadowsocks']) {
      reference('protocol_' + id, 'Proxy protocol',
          KingNatCapabilityStatus.implementedUntested,
          'Existing Xray config path; this registry does not infer a successful handshake.');
    }
    for (final id in const [
      'websocket', 'grpc', 'http2', 'httpupgrade', 'xhttp', 'mkcp', 'tcp_tls',
      'reality', 'xtls_vision'
    ]) {
      reference('transport_' + id, 'Xray transport',
          KingNatCapabilityStatus.implementedUntested,
          'Existing config adapter path; endpoint-specific compatibility is checked at runtime.');
    }
    for (final id in const [
      'hysteria2', 'tuic_v4', 'tuic_v5', 'shadow_tls', 'naiveproxy',
      'anytls', 'juicity', 'cloak', 'brook', 'mieru', 'trusttunnel',
      'masque', 'shadowsocks_2022', 'amneziawg', 'proteus', 'upgen'
    ]) {
      reference('protocol_' + id, 'External/native protocol',
          KingNatCapabilityStatus.researchOnly,
          'No verified native Core adapter was found in the inspected app integration.');
    }

    for (final id in const [
      'obfs2', 'obfs3', 'obfs4', 'meek', 'meek_amazon', 'meek_azure',
      'meek_google', 'snowflake', 'webtunnel', 'scramblesuit', 'fte',
      'flashproxy', 'marionette'
    ]) {
      reference('transport_' + id, 'Pluggable transport',
          KingNatCapabilityStatus.requiresServerInfrastructure,
          'Requires matching bridge/server infrastructure and a maintained client adapter.');
    }
    for (final id in const [
      'conjure', 'telex', 'tapdance', 'slitheen', 'cirripede',
      'curveball', 'rebound'
    ]) {
      reference('refraction_' + id, 'Refraction networking',
          KingNatCapabilityStatus.requiresServerInfrastructure,
          'Research architecture requiring coordinated infrastructure beyond a standalone client.');
    }

    for (final id in const [
      'zapret', 'byedpi', 'goodbyedpi', 'slipnet', 'zerodpi', 'b4',
      'sni_proxy', 'ciadpi', 'spoofdpi', 'greentunnel', 'geneva',
      'symtcp', 'ghostcp', 'dpi_tunnel', 'bypass_dpi', 'egcit'
    ]) {
      reference('reference_' + id, 'DPI research source',
          KingNatCapabilityStatus.researchOnly,
          'Reference-only: evaluate individual techniques and licensing; do not embed the tool blindly.',
          android: false);
    }

    return List<KingNatCapability>.unmodifiable(
      rows.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
    );
  }

  static Map<String, Object?> diagnostics() {
    final counts = <String, int>{};
    for (final row in registry) {
      counts[row.statusLabel] = (counts[row.statusLabel] ?? 0) + 1;
    }
    var attempts = 0;
    var successes = 0;
    var failures = 0;
    for (final profile in _history.values) {
      for (final stat in profile.values) {
        attempts += stat.attempts;
        successes += stat.successes;
        failures += stat.failures;
      }
    }
    return <String, Object?>{
      'engine': 'KING National Scanner Engine',
      'version': 1,
      'networkClass': natNetworkClassLabel(NatNetworkDiagnosis.current),
      'nationalMode': nationalMode,
      'variantCatalogSize': _natSpecs.length,
      'profileCount': _history.length,
      'recordCount': _recordCount,
      'attempts': attempts,
      'realTrafficSuccesses': successes,
      'realTrafficFailures': failures,
      'capabilityStatusCounts': counts,
      'registry': registry.map((e) => e.toMap()).toList(growable: false),
    };
  }
}
