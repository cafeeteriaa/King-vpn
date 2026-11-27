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
  double? latencyEwmaMs;
  DateTime? lastAt;
  double get confidence => (successes + 1) / (attempts + 2);
}

/// A distinct fourth connection mode; it is not Smart/Auto.
bool scannerMode = false;
bool? _scannerTargetNationalMode;

enum KingNatScanPhase { idle, diagnosis, dns, domain, ip, sniAlpn, config, complete, cancelled }

class KingNatScanReport {
  const KingNatScanReport({
    required this.completed, required this.timedOut, required this.networkClass,
    required this.nationalMode, required this.dnsResolvers, required this.domainEndpoints,
    required this.ipEndpoints, required this.sniHandshakes, required this.alpnNegotiations,
    required this.configsValidated, required this.elapsedMs, this.warnings = const <String>[],
    this.domesticTlsSuccesses = 0, this.globalTlsSuccesses = 0,
    this.domesticLatencyMs, this.globalLatencyMs,
    this.networkConfidence = 0, this.inventoryPassComplete = false,
    this.sliceYielded = false,
    this.domesticIpv6Successes = 0, this.globalIpv6Successes = 0,
    this.domesticIpv6LatencyMs, this.globalIpv6LatencyMs,
  });
  final bool completed, timedOut, nationalMode;
  final NatNetworkClass networkClass;
  final int dnsResolvers, domainEndpoints, ipEndpoints;
  final int sniHandshakes, alpnNegotiations, configsValidated, elapsedMs;
  final int domesticTlsSuccesses, globalTlsSuccesses;
  final int? domesticLatencyMs, globalLatencyMs;
  final double networkConfidence;
  final bool inventoryPassComplete, sliceYielded;
  final int domesticIpv6Successes, globalIpv6Successes;
  final int? domesticIpv6LatencyMs, globalIpv6LatencyMs;
  final List<String> warnings;
  String get summary => 'اسکن این نوبت: DNS $dnsResolvers • دامنه/IP $domainEndpoints • IP $ipEndpoints • SNI $sniHandshakes • ALPN $alpnNegotiations • IPv6 داخلی/جهانی $domesticIpv6Successes/$globalIpv6Successes • کانفیگ ساختاری $configsValidated • موجودی IP: ${inventoryPassComplete ? 'کامل' : 'ادامه از Cursor ذخیره‌شده'}';
  Map<String, Object?> toMap() => <String, Object?>{
    'completed': completed, 'timedOut': timedOut,
    'networkClass': natNetworkClassLabel(networkClass), 'nationalMode': nationalMode,
    'dnsResolvers': dnsResolvers, 'domainEndpoints': domainEndpoints, 'ipEndpoints': ipEndpoints,
    'sniHandshakes': sniHandshakes, 'alpnNegotiations': alpnNegotiations,
    'configsValidated': configsValidated,
    'configsStructurallyValidated': configsValidated,
    'domesticTlsSuccesses': domesticTlsSuccesses,
    'globalTlsSuccesses': globalTlsSuccesses,
    'domesticLatencyMs': domesticLatencyMs,
    'globalLatencyMs': globalLatencyMs,
    'networkConfidence': networkConfidence,
    'inventoryPassComplete': inventoryPassComplete,
    'sliceYielded': sliceYielded,
    'domesticIpv6Successes': domesticIpv6Successes,
    'globalIpv6Successes': globalIpv6Successes,
    'domesticIpv6LatencyMs': domesticIpv6LatencyMs,
    'globalIpv6LatencyMs': globalIpv6LatencyMs,
    'elapsedMs': elapsedMs, 'warnings': warnings,
  };
}

class KingNationalScannerEngine {
  KingNationalScannerEngine._();

  static const String _prefsKey = 'king_nat_strategy_memory_v1';
  static final Map<String, Map<int, _KingNatVariantStats>> _history =
      <String, Map<int, _KingNatVariantStats>>{};
  static final Map<String, int> _featureEvidence = <String, int>{};
  static final Map<String, int> _sniPreferences = <String, int>{};
  static final Map<String, String> _alpnPreferences = <String, String>{};
  static int _sniProbeEvidence = 0, _alpnProbeEvidence = 0;
  static int _recordCount = 0;
  static KingNatScanPhase _scanPhase = KingNatScanPhase.idle;
  static KingNatScanReport? _lastScanReport;
  static Future<KingNatScanReport>? _scanFlight;
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
      if (_persistDirty) _schedulePersist();
    } finally {
      if (identical(_loadFlight, future)) _loadFlight = null;
    }
  }

  /// Isolates preference-backed learning tests from previous process runs.
  static Future<void> resetForTesting() async {
    final pending = _persistFlight;
    if (pending != null) {
      try { await pending; } catch (_) {}
    }
    _history.clear();
    _featureEvidence.clear();
    _sniPreferences.clear();
    _alpnPreferences.clear();
    _sniProbeEvidence = 0;
    _alpnProbeEvidence = 0;
    _recordCount = 0;
    _scanPhase = KingNatScanPhase.idle;
    _lastScanReport = null;
    _lastPlanKey = '';
    _loaded = false;
    _persistDirty = false;
    _loadFlight = null;
    _persistFlight = null;
    // Unit tests may run without a platform path-provider binding. Resetting
    // in-memory learning must still work in that environment; production disk
    // persistence remains covered by the normal loader/writer path.
    try {
      final file = await _strategyStoreFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<void> _loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var hasDiskStore = false;
      String? raw;
      try {
        final storeFile = await _strategyStoreFile();
        hasDiskStore = await storeFile.exists();
        if (hasDiskStore) raw = await storeFile.readAsString();
      } catch (_) {
        // Platform storage may be unavailable in pure unit tests or during
        // transient Android storage failures. Fall back to preferences.
      }
      raw ??= prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || (decoded['version'] != 1 && decoded['version'] != 2 && decoded['version'] != 3 && decoded['version'] != 4)) return;
      final profiles = decoded['profiles'];
      if (profiles is! Map) return;
      final rawSni = decoded['sni'];
      if (rawSni is Map) {
        for (final entry in rawSni.entries) {
          final key = entry.key.toString();
          final index = entry.value;
          if (key.isNotEmpty && key.length <= 256 && index is num &&
              index.toInt() >= 0 && index.toInt() < natFrontSnis.length &&
              InternetAddress.tryParse(natFrontSnis[index.toInt()]) == null) {
            _sniPreferences[key] = index.toInt();
          }
        }
      }
      final rawSniEvidence = decoded['sniEvidence'];
      if (rawSniEvidence is num && rawSniEvidence >= 0) {
        _sniProbeEvidence = rawSniEvidence.toInt();
      }
      final rawAlpn = decoded['alpn'];
      if (rawAlpn is Map) {
        for (final entry in rawAlpn.entries) {
          final key = entry.key.toString();
          final value = entry.value?.toString() ?? '';
          if (key.isNotEmpty && key.length <= 256 &&
              (value == 'h2' || value == 'http/1.1')) {
            _alpnPreferences[key] = value;
          }
        }
      }
      final rawAlpnEvidence = decoded['alpnEvidence'];
      if (rawAlpnEvidence is num && rawAlpnEvidence >= 0) {
        _alpnProbeEvidence = rawAlpnEvidence.toInt();
      }
      final orderedProfiles = profiles.entries.where((entry) =>
          entry.key.toString().isNotEmpty && entry.key.toString().length <= 256 &&
          entry.value is Map).toList()
        ..sort((a, b) {
          DateTime newest(Object? raw) {
            var result = DateTime.fromMillisecondsSinceEpoch(0);
            if (raw is Map) {
              for (final value in raw.values) {
                if (value is Map && value['t'] is num) {
                  final stamp = (value['t'] as num).toInt();
                  if (stamp > result.millisecondsSinceEpoch) {
                    result = DateTime.fromMillisecondsSinceEpoch(stamp);
                  }
                }
              }
            }
            return result;
          }
          return newest(b.value).compareTo(newest(a.value));
        });
      for (final profileEntry in orderedProfiles) {
        final rawVariants = profileEntry.value;
        if (rawVariants is! Map) continue;
        final variants = <int, _KingNatVariantStats>{};
        for (final variantEntry
            in rawVariants.entries) {
          final variant = int.tryParse(variantEntry.key.toString());
          final values = variantEntry.value;
          if (variant == null ||
              variant < 0 ||
              variant >= _natSpecs.length ||
              values is! Map) continue;
          final attempts = values['a'];
          final successes = values['s'];
          final failures = values['f'];
          if (attempts is! num || successes is! num || failures is! num) continue;
          final safeAttempts = attempts.toInt().clamp(0, 0x7fffffffffffffff).toInt();
          final safeSuccesses = successes.toInt().clamp(0, safeAttempts).toInt();
          final safeFailures = failures.toInt()
              .clamp(0, safeAttempts - safeSuccesses).toInt();
          final stat = _KingNatVariantStats()
            ..attempts = safeAttempts
            ..successes = safeSuccesses
            ..failures = safeFailures;
          final latency = values['l'];
          if (latency is num && latency > 0) stat.latencyEwmaMs = latency.toDouble();
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
      _rebuildLearningTotals();
      if (!hasDiskStore && raw != null && raw.isNotEmpty) {
        _persistDirty = true;
      }
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

  static Future<File> _strategyStoreFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/king_nat_strategy_memory_v1.json');
  }

  static Future<void> _persistLoop() async {
    while (_persistDirty) {
      _persistDirty = false;
      try {
        final profiles = <String, Object?>{};
        for (final profileEntry in _history.entries) {
          final variants = <String, Object?>{};
          for (final variantEntry in profileEntry.value.entries) {
            final stat = variantEntry.value;
            variants[variantEntry.key.toString()] = <String, Object?>{
              'a': stat.attempts,
              's': stat.successes,
              'f': stat.failures,
              'l': stat.latencyEwmaMs,
              't': stat.lastAt?.millisecondsSinceEpoch ?? 0,
            };
          }
          profiles[profileEntry.key] = variants;
        }
        final file = await _strategyStoreFile();
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(
          jsonEncode(<String, Object?>{
            'version': 4,
            'profiles': profiles,
            'sni': _sniPreferences,
            'alpn': _alpnPreferences,
            'sniEvidence': _sniProbeEvidence,
            'alpnEvidence': _alpnProbeEvidence,
          }),
          flush: true,
        );
        // Same-directory rename replaces the previous snapshot atomically on Android.
        await temporary.rename(file.path);
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
          var value = (stats.confidence * 100) -
              (stats.failures * 2.5) -
              _strategyCost(_natSpecs[variant]) -
              (position * 0.001);
          final latency = stats.latencyEwmaMs;
          if (latency != null) value -= min(20.0, latency / 100.0).toDouble();
          final preferredSni = _sniPreferences[profileKey(server)];
          if (preferredSni != null && _natSpecs[variant].sniSwap == preferredSni) value += 18;
          final preferredAlpn = _alpnPreferences[profileKey(server)];
          final candidateAlpn = _natSpecs[variant].alpn;
          if (preferredAlpn != null && candidateAlpn != null &&
              candidateAlpn.split(',').contains(preferredAlpn)) value += 8;
          return value;
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
    int? latencyMs,
  }) {
    if (variant < 0 || variant >= _natSpecs.length) return;
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
    if (latencyMs != null && latencyMs > 0) {
      final oldLatency = stats.latencyEwmaMs;
      stats.latencyEwmaMs = oldLatency == null ? latencyMs.toDouble() : oldLatency * 0.75 + latencyMs * 0.25;
    }
    stats.lastAt = DateTime.now();
    _recordCount++;
    _schedulePersist();

    _rebuildLearningTotals();
  }

  static void _rebuildLearningTotals() {
    _featureEvidence.clear();
    var records = 0;
    for (final variants in _history.values) {
      for (final entry in variants.entries) {
        final stat = entry.value;
        records += stat.attempts;
        if (stat.successes <= 0) continue;
        final features = _featuresFor(_natSpecs[entry.key]);
        // A combined variant cannot independently prove each of its features.
        // Only single-feature variants contribute to per-capability verification.
        if (features.length != 1) continue;
        final id = features.single;
        _featureEvidence[id] =
            (_featureEvidence[id] ?? 0) + stat.successes;
      }
    }
    _recordCount = records;
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

    void reference(
      String id,
      String family,
      KingNatCapabilityStatus status,
      String note, {
      bool android = true,
      String source = 'Reference catalog; not activated by this registry',
    }) {
      rows[id] = KingNatCapability(
        id: id,
        family: family,
        status: status,
        source: source,
        note: note,
        android: android,
      );
    }

    void implemented(
      String id,
      String family, {
      required String note,
      String source = 'lib/nat_ultra.dart → _NatSpec / natCfg',
      bool android = true,
    }) {
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
    reference('tcp_segmentation_compatibility', 'Traffic transformation',
        KingNatCapabilityStatus.adapterAvailable,
        'The current Core adapter fragments TLS ClientHello; generic TCP segmentation is not exposed.');
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
    reference('padding_noise', 'Traffic transformation',
        KingNatCapabilityStatus.incompatible,
        'Noise variants are deliberately blocked by the current compatibility guard; no padding is applied.');
    implemented('mss_adaptation', 'Transport compatibility',
        note: 'MSS candidates are registered only when present in the current variant catalog.');
    implemented('transport_mode', 'Transport compatibility',
        note: 'Existing transport-mode variants; actual core support remains authoritative.');

    // Fake-packet and packet-state techniques are explicit, not disguised as
    // implemented config flags. A future adapter must pass protocol/security tests.
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
        KingNatCapabilityStatus.researchOnly,
        'A general adaptive-padding engine is not exposed by the active Android Core.');
    reference('timing_jitter', 'DPI transformation',
        KingNatCapabilityStatus.researchOnly,
        'No independent packet scheduler/timing adapter is exposed.');
    reference('udp_datagram_transformation', 'UDP transport',
        KingNatCapabilityStatus.researchOnly,
        'No generic UDP packet rewrite adapter is present.');
    reference('quic_compatibility', 'QUIC transport',
        KingNatCapabilityStatus.researchOnly,
        'Requires an explicitly supported QUIC Core and endpoint handshake validation.');
    reference('ech_compatibility', 'TLS identity',
        KingNatCapabilityStatus.researchOnly,
        'ECH negotiation and outer/inner-name policy are not exposed by the current Core adapter.');
    reference('domain_fronting', 'Destination compatibility',
        KingNatCapabilityStatus.researchOnly,
        'SNI override alone is not domain fronting; matching CDN routing and server behavior are required.');
    reference('http_authority_rewrite', 'HTTP identity',
        KingNatCapabilityStatus.researchOnly,
        'No independent HTTP Host/:authority rewrite adapter is exposed by the active Core.');
    reference('dnssec_validation', 'DNS security',
        KingNatCapabilityStatus.researchOnly,
        'The current DNS probe validates response structure, not DNSSEC signatures.');
    reference('dns_over_tls', 'DNS transport',
        KingNatCapabilityStatus.researchOnly,
        'No dedicated DoT resolver adapter is connected to the active Core.');
    reference('dns_over_quic', 'DNS transport',
        KingNatCapabilityStatus.researchOnly,
        'No dedicated DoQ resolver adapter is connected to the active Core.');
    reference('ipv6_path_validation', 'IP routing',
        KingNatCapabilityStatus.researchOnly,
        'IPv6 path selection and leak behavior require device-level dual-stack validation.');
    reference('udp_packet_forgery', 'Fake packet',
        KingNatCapabilityStatus.researchOnly,
        'No packet-level UDP forgery adapter is present in the active Android Core.');

    for (final id in const ['vless', 'vmess', 'trojan', 'shadowsocks']) {
      reference('protocol_' + id, 'Proxy protocol',
          KingNatCapabilityStatus.implementedUntested,
          'Existing Xray config path; this registry does not infer a successful handshake.');
    }
    for (final id in const [
      'websocket', 'grpc', 'http2', 'httpupgrade', 'xhttp', 'mkcp',
      'tcp_tls', 'reality', 'xtls_vision'
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

  static bool? chooseNationalMode({
    required NatNetworkClass diagnosis,
    required int domesticTlsSuccesses,
    required int globalTlsSuccesses,
  }) {
    if (domesticTlsSuccesses >= 2 && globalTlsSuccesses == 0) return true;
    if (globalTlsSuccesses >= 2 && domesticTlsSuccesses == 0) return false;
    // Dual-route networks are decided by measured latency, not forced to Global.
    if (domesticTlsSuccesses >= 2 && globalTlsSuccesses >= 2) return null;
    switch (diagnosis) {
      case NatNetworkClass.domesticOnlyLikely:
      case NatNetworkClass.dnsDegraded:
      case NatNetworkClass.transportRestricted:
        return domesticTlsSuccesses >= 2 && globalTlsSuccesses == 0 ? true : null;
      case NatNetworkClass.globalReachable:
      case NatNetworkClass.unknown:
        return null;
    }
  }

  static Future<bool?> detectNationalMode() async {
    try {
      final results = await Future.wait<Object>(<Future<Object>>[
        NatNetworkDiagnosis.refresh(force: true),
        PilotNetworkProbe.refresh(force: true),
      ]);
      final diagnosis = results[0] as NatNetworkClass;
      final tls = results[1] as NetworkEvidence;
      final strategy = choosePilotNetworkStrategy(tls);
      final decision = switch (strategy) {
        PilotNetworkStrategy.domestic => true,
        PilotNetworkStrategy.global => false,
        PilotNetworkStrategy.offline => null,
        PilotNetworkStrategy.preserve => chooseNationalMode(
          diagnosis: diagnosis,
          domesticTlsSuccesses: tls.domesticSuccesses,
          globalTlsSuccesses: tls.globalSuccesses,
        ),
      };
      dbg('KNS-MODE: ' + natNetworkClassLabel(diagnosis) +
          ' domesticTLS=' + tls.domesticSuccesses.toString() +
          ' globalTLS=' + tls.globalSuccesses.toString() +
          ' domesticMs=' + (tls.domesticLatencyMs?.toString() ?? '-') +
          ' globalMs=' + (tls.globalLatencyMs?.toString() ?? '-') +
          ' confidence=' + tls.confidence.toStringAsFixed(2) +
          ' strategy=' + strategy.name +
          ' decision=' + (decision == null ? 'unknown/preserve' : (decision ? 'national' : 'global')));
      return decision;
    } catch (e, st) {
      logError(e, st);
      return null;
    }
  }

  static KingNatScanPhase get scanPhase => _scanPhase;
  static KingNatScanReport? get lastScanReport => _lastScanReport;
  static bool get isScanning => _scanFlight != null;

  static void recordSniProbe(String profile, int index) {
    if (profile.isEmpty || index < 0 || index >= natFrontSnis.length ||
        InternetAddress.tryParse(natFrontSnis[index]) != null) return;
    _sniPreferences[profile] = index;
    _sniProbeEvidence++;
    _schedulePersist();
  }

  static void recordAlpnProbe(String profile, String alpn) {
    if (profile.isEmpty || (alpn != 'h2' && alpn != 'http/1.1')) return;
    _alpnPreferences[profile] = alpn;
    _alpnProbeEvidence++;
    _schedulePersist();
  }

  /// Flushes strategy evidence before the scan journal advances its cursor.
  static Future<void> flushLearning() async {
    await load();
    while (_persistDirty || _persistFlight != null) {
      if (_persistFlight == null) _schedulePersist();
      final pending = _persistFlight;
      if (pending != null) await pending;
    }
  }

  static Future<String?> _probeSniAlpn(String ip, int port, String sni) async {
    Socket? raw;
    SecureSocket? secure;
    try {
      raw = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
      secure = await SecureSocket.secure(
        raw, host: sni, supportedProtocols: const <String>['h2', 'http/1.1'],
      ).timeout(const Duration(seconds: 3));
      return secure.selectedProtocol ?? '';
    } catch (_) {
      return null;
    } finally {
      secure?.destroy();
      raw?.destroy();
    }
  }

  static Future<KingNatScanReport> runPreflight({
    required List<Server> knownServers,
    required void Function(String) onStatus,
    required bool Function() cancelled,
    required Future<void> Function(List<String>) addDiscovered,
    Duration sliceBudget = const Duration(seconds: 60),
  }) async {
    final active = _scanFlight;
    if (active != null) return active;
    final future = _runPreflight(
      knownServers: knownServers, onStatus: onStatus,
      cancelled: cancelled, addDiscovered: addDiscovered,
      sliceBudget: sliceBudget,
    );
    _scanFlight = future;
    try {
      final report = await future;
      _lastScanReport = report;
      if (report.sliceYielded ||
          report.warnings.contains('ip_inventory_cursor_preserved_for_next_slice')) {
        try {
          await KingAiBackgroundSupervisor.scheduleNationalScannerContinuation();
        } catch (e, st) {
          logError(e, st);
        }
      }
      return report;
    } finally {
      if (identical(_scanFlight, future)) _scanFlight = null;
      if (_scanPhase != KingNatScanPhase.cancelled) _scanPhase = KingNatScanPhase.complete;
    }
  }

  static Future<KingNatScanReport> _runPreflight({
    required List<Server> knownServers,
    required void Function(String) onStatus,
    required bool Function() cancelled,
    required Future<void> Function(List<String>) addDiscovered,
    required Duration sliceBudget,
  }) async {
    final clock = Stopwatch()..start();
    final modeSnapshot = nationalMode;
    // Each call is a resumable slice; the total inventory has no pass ceiling.
    bool expired() => clock.elapsed >= sliceBudget;
    bool stopped() => cancelled() || nationalMode != modeSnapshot;
    bool shouldYield() => expired() && !stopped();
    final warnings = <String>[];
    var ownsScannerLease = false;
    var domainHits = 0, ipHits = 0, sniHits = 0, alpnHits = 0;
    var configsValidated = 0, dnsCount = 0;
    var networkEvidence = PilotNetworkProbe.current;
    var ipv6Evidence = PilotIpv6Probe.current;
    var phaseDeferred = false;
    File? processLeaseFile;
    var ownsProcessLease = false;
    KingScanJournal? journal;
    String resumePhase = '';
    Map<String, Object?> resumeCursor = <String, Object?>{};
    const phaseOrder = <String>['dns', 'domain', 'ip', 'sni', 'config', 'complete'];
    int phaseRank(String phase) => phaseOrder.indexOf(phase);
    bool shouldRunPhase(String phase) =>
        resumePhase.isEmpty || phaseRank(phase) >= phaseRank(resumePhase);
    Future<void> persistPhase(
      String phase, {
      required bool completed,
      Map<String, Object?> cursor = const <String, Object?>{},
    }) async {
      final store = journal;
      if (store == null) return;
      try {
        await store.commit(
          phase: phase,
          phaseCompleted: completed,
          cursor: cursor,
          counters: <String, int>{
            'dnsResolvers': dnsCount,
            'domainEndpoints': domainHits,
            'ipEndpoints': ipHits,
            'sniHandshakes': sniHits,
            'alpnNegotiations': alpnHits,
            'configsValidated': configsValidated,
          },
        );
      } catch (e, st) {
        logError(e, st);
        warnings.add('scan_journal_write_failed');
        journal = null;
      }
    }
    Future<void> beginPhase(String phase) async {
      await persistPhase(
        phase,
        completed: false,
        cursor: resumePhase == phase ? resumeCursor : const <String, Object?>{},
      );
    }
    Future<void> completePhase(String phase) async {
      await persistPhase(phase, completed: true);
    }
    void status(KingNatScanPhase phase, String message) {
      _scanPhase = phase;
      if (!stopped()) onStatus(message);
    }

    try {
      await load();
      await NationalNetworkIntelligence.load();
      try {
        final samples = await Future.wait<Object>(<Future<Object>>[
          NatNetworkDiagnosis.refresh(),
          PilotNetworkProbe.refresh(),
          PilotIpv6Probe.refresh(),
        ]).timeout(const Duration(seconds: 12));
        networkEvidence = samples[1] as NetworkEvidence;
        ipv6Evidence = samples[2] as PilotIpv6Evidence;
      } catch (e, st) {
        logError(e, st);
        warnings.add('network_evidence_incomplete');
      }
      // The in-memory scanner lease is isolate-local. A small atomic
      // file lease also prevents the foreground app and WorkManager isolate
      // from traversing the same inventory concurrently.
      try {
        final directory = await getApplicationSupportDirectory();
        final lockFile = File('${directory.path}/king_national_scanner.lock');
        if (await lockFile.exists()) {
          final age = DateTime.now().difference(await lockFile.lastModified());
          if (age < const Duration(minutes: 15)) {
            warnings.add('another_scanner_process_running');
            phaseDeferred = true;
          } else {
            await lockFile.delete();
          }
        }
        if (!phaseDeferred) {
          try {
            await lockFile.create(exclusive: true);
            processLeaseFile = lockFile;
            ownsProcessLease = true;
            await lockFile.writeAsString(
              DateTime.now().millisecondsSinceEpoch.toString(),
              flush: true,
            );
          } on FileSystemException {
            warnings.add('another_scanner_process_running');
            phaseDeferred = true;
          }
        }
      } catch (e, st) {
        logError(e, st);
        // If path-provider is unavailable in a test/headless environment,
        // the existing in-isolate single-flight/lease remains in force.
        warnings.add('cross_process_lease_unavailable');
      }
      try {
        final networkClass = NatNetworkDiagnosis.current.name;
        journal = await KingScanJournal.open(
          jobId: 'scanner-${modeSnapshot ? 'national' : 'global'}-$networkClass',
        );
        final previous = journal!.latestCheckpoint;
        if (previous != null) {
          final previousPhase = previous['phase']?.toString() ?? '';
          final previousRank = phaseRank(previousPhase);
          final wasCompleted = previous['phaseCompleted'] == true;
          final nextRank = previousRank < 0 ? 0 : previousRank + (wasCompleted ? 1 : 0);
          resumePhase = nextRank >= 0 && nextRank < phaseOrder.length
              ? phaseOrder[nextRank] : '';
          if (!wasCompleted && previous['cursor'] is Map) {
            resumeCursor = Map<String, Object?>.from(previous['cursor'] as Map);
          }
          final previousCounters = previous['counters'];
          if (previousCounters is Map) {
            int restored(String key) {
              final value = previousCounters[key];
              return value is int && value >= 0 ? value : 0;
            }
            dnsCount = restored('dnsResolvers');
            domainHits = restored('domainEndpoints');
            ipHits = restored('ipEndpoints');
            sniHits = restored('sniHandshakes');
            alpnHits = restored('alpnNegotiations');
            configsValidated = restored('configsValidated');
          }
          if (resumePhase.isNotEmpty) warnings.add('resuming_from_$resumePhase');
        }
      } catch (e, st) {
        logError(e, st);
        warnings.add('scan_journal_unavailable');
        journal = null;
      }
      // One shared lease serializes Scanner mode with DNS, IP-auto and the
      // generic scanner. The lease is represented by dnsxManualBusy so legacy
      // scanner entry points already respect it; only this coordinator's DNS
      // call is allowed through the lease.
      bool externalScannerBusy() =>
          dnsxManualBusy || _dnsxAutoBusy || ipAutoBusy ||
          _natRangeScanBusy || _autoScanRunning;
      while (externalScannerBusy() && !stopped() && !shouldYield()) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      if (stopped()) {
        _scanPhase = KingNatScanPhase.cancelled;
        return KingNatScanReport(
          completed: false, timedOut: expired(),
          networkClass: NatNetworkDiagnosis.current, nationalMode: modeSnapshot,
          dnsResolvers: 0, domainEndpoints: 0, ipEndpoints: 0,
          sniHandshakes: 0, alpnNegotiations: 0, configsValidated: 0,
          elapsedMs: clock.elapsedMilliseconds, warnings: const ['cancelled'],
        );
      }
      if (externalScannerBusy()) {
        warnings.add('another_scanner_is_still_running');
        _scanPhase = KingNatScanPhase.cancelled;
        return KingNatScanReport(
          completed: false, timedOut: false,
          networkClass: NatNetworkDiagnosis.current, nationalMode: modeSnapshot,
          dnsResolvers: 0, domainEndpoints: 0, ipEndpoints: 0,
          sniHandshakes: 0, alpnNegotiations: 0, configsValidated: 0,
          elapsedMs: clock.elapsedMilliseconds, warnings: List<String>.unmodifiable(warnings),
        );
      }
      dnsxManualBusy = true;
      ownsScannerLease = true;
      if (stopped()) {
        _scanPhase = KingNatScanPhase.cancelled;
        return KingNatScanReport(
          completed: false, timedOut: expired(),
          networkClass: NatNetworkDiagnosis.current, nationalMode: modeSnapshot,
          dnsResolvers: 0, domainEndpoints: 0, ipEndpoints: 0,
          sniHandshakes: 0, alpnNegotiations: 0, configsValidated: 0,
          elapsedMs: clock.elapsedMilliseconds, warnings: const ['cancelled'],
        );
      }

      final unique = <String, Server>{};
      for (final server in <Server>[
        ...knownServers, ...natTemplateSeeds,
      ]) {
        unique.putIfAbsent(server.key, () => server);
      }
      var seeds = unique.values.toList(growable: false);
      if (seeds.length < 8 && !stopped()) {
        try {
          final cached = await natHotNext(80, fetch: false);
          if (!stopped()) {
            for (final server in cached) unique.putIfAbsent(server.key, () => server);
            seeds = unique.values.toList(growable: false);
          }
        } catch (e, st) {
          logError(e, st);
          warnings.add('local_config_cache_unavailable');
        }
      }
      if (seeds.isNotEmpty) natTemplateSeeds = List<Server>.of(seeds);

      if (shouldRunPhase('dns') && !stopped() && !shouldYield() && !phaseDeferred) {
        await beginPhase('dns');
        status(KingNatScanPhase.dns, 'اسکنر: بررسی DNS متناسب با شبکه...');
        if (!stopped() && !shouldYield()) {
          if (_dnsxAutoBusy) {
            warnings.add('dns_scan_busy_skipped');
          } else {
            final dnsClock = Stopwatch()..start();
            await dnsxAutoPick(
              force: true,
              coordinatorOwned: true,
              stop: () => stopped() || shouldYield(),
            );
            dnsCount = dnsxBestCache.length;
            final preferences = await SharedPreferences.getInstance();
            await preferences.flush();
            if (dnsClock.elapsed >= const Duration(seconds: 60)) warnings.add('dns_phase_extended_over_60s');
          }
        }
        if (!stopped() && !shouldYield()) await completePhase('dns');
      }

      if (shouldRunPhase('domain') && !stopped() && !shouldYield() && !phaseDeferred) {
        await beginPhase('domain');
        status(KingNatScanPhase.domain, 'اسکنر: کشف دامنه و endpointهای کانفیگ...');
        if (!stopped() && !shouldYield() && seeds.isNotEmpty && kNatIpScanOn) {
          final found = await _natDomainFirst(
            seeds, conc: max(2, natAdaptiveWorkers()).toInt(),
            stop: () => stopped() || shouldYield(),
          );
          if (!stopped() && found.isNotEmpty) {
            domainHits = found.length;
            await addDiscovered(found);
          }
        }
        if (!stopped() && !shouldYield()) await completePhase('domain');
      }

      if (shouldRunPhase('ip') && !stopped() && !shouldYield() && !phaseDeferred) {
        await beginPhase('ip');
        status(KingNatScanPhase.ip, 'اسکنر: پیمایش پیوستهٔ تمام بازه‌ها و endpointها...');
        if (!stopped() && !shouldYield() && kNatIpScanOn &&
            !ipAutoBusy && !_natRangeScanBusy) {
          // The range scanner owns durable per-range offsets. Run as many
          // bounded batches as fit in this invocation; the complete inventory
          // remains uncapped and resumes after the process/app returns.
          await natRangeStartNextPass();
          final workers = max(1, natAdaptiveWorkers()).toInt();
          final portCount = max(1, natAutoPorts(seeds).length).toInt();
          final batchWaves = max(
            1,
            (sliceBudget.inMilliseconds * 0.50 / (portCount * 1500)).floor(),
          ).toInt();
          final batchAddressBudget = (workers * batchWaves).clamp(1, 768).toInt();
          var batch = 0;
          while (!stopped() && !shouldYield() && !natRangeInventoryPassComplete) {
            batch++;
            final found = await natRangeScanStep(
              known: seeds,
              maxAddrs: batchAddressBudget,
              conc: workers,
              stop: () => stopped() || shouldYield(),
              coordinatorOwned: true,
            );
            if (stopped()) break;
            ipHits += found.length;
            if (found.isNotEmpty) await addDiscovered(found);
            await persistPhase(
              'ip',
              completed: false,
              cursor: <String, Object?>{
                'rangeIndex': _natConfiguredRangeCursor,
                'rangeCount': natRanges.length,
                'batch': batch,
              },
            );
            if (batch % 16 == 0) {
              status(KingNatScanPhase.ip,
                  'اسکنر: ادامهٔ پیمایش بازه‌ها؛ دستهٔ $batch، تعداد کشفیات $ipHits');
              await Future<void>.delayed(Duration.zero);
            }
          }
          if (!stopped() && natRangeInventoryPassComplete) await completePhase('ip');
          if (!natRangeInventoryPassComplete) {
            warnings.add('ip_inventory_cursor_preserved_for_next_slice');
          }
        } else if (!kNatIpScanOn) {
          warnings.add('ip_scan_disabled_by_policy');
          if (!stopped()) await completePhase('ip');
        } else if (ipAutoBusy || _natRangeScanBusy) {
          warnings.add('ip_scan_busy_skipped');
          phaseDeferred = true;
        }
      }

      if (shouldRunPhase('sni') && !stopped() && !shouldYield() && !phaseDeferred) {
        await beginPhase('sni');
        status(KingNatScanPhase.sniAlpn, 'اسکنر: بررسی سازگاری SNI و ALPN...');
      if (!stopped() && !shouldYield()) {
        final targets = <Server>[
          ...seeds.where((s) => s.cdn && !s.reality && _natIsSecure(s)),
        ];
        final seenTargets = <String>{};
        final resumeServerHash = resumePhase == 'sni'
            ? resumeCursor['serverKeyHash']?.toString() : null;
        final foundResumeServer = resumeServerHash == null
            ? 0
            : targets.indexWhere((server) =>
                sha256.convert(utf8.encode(server.key)).toString() == resumeServerHash);
        final resumeServer = foundResumeServer < 0 ? 0 : foundResumeServer;
        final resumeCandidate = resumePhase == 'sni' && foundResumeServer >= 0
            ? (resumeCursor['candidateIndex'] as num?)?.toInt() ?? -1 : -1;
        final candidates = natFrontSnis.asMap().entries.where(
          (entry) => InternetAddress.tryParse(entry.value) == null,
        ).toList(growable: false);
        for (var serverIndex = 0; serverIndex < targets.length; serverIndex++) {
          if (stopped() || shouldYield()) break;
          final server = targets[serverIndex];
          if (serverIndex < resumeServer || !seenTargets.add(server.key)) continue;
          String? ip;
          if (server.isIp) {
            ip = server.host;
          } else {
            try {
              final addresses = await InternetAddress.lookup(server.host)
                  .timeout(const Duration(seconds: 3));
              for (final address in addresses) {
                if (address.type == InternetAddressType.IPv4) { ip = address.address; break; }
              }
            } catch (_) {
              ip = null;
            }
          }
          if (ip != null) {
            for (var candidateIndex = 0; candidateIndex < candidates.length; candidateIndex++) {
              if (stopped() || shouldYield()) break;
              if (serverIndex == resumeServer && candidateIndex <= resumeCandidate) continue;
              final candidate = candidates[candidateIndex];
              final alpn = await _probeSniAlpn(ip, server.port, candidate.value);
              if (stopped()) break;
              if (alpn != null) {
                recordSniProbe(profileKey(server), candidate.key);
                sniHits++;
                if (alpn.isNotEmpty) {
                  recordAlpnProbe(profileKey(server), alpn);
                  alpnHits++;
                }
                await flushLearning();
              }
              await persistPhase(
                'sni',
                completed: false,
                cursor: <String, Object?>{
                  'serverIndex': serverIndex,
                  'serverKeyHash': sha256.convert(utf8.encode(server.key)).toString(),
                  'candidateIndex': candidateIndex,
                },
              );
            }
          }
          if (!stopped() && !shouldYield()) {
            await persistPhase(
              'sni',
              completed: false,
              cursor: <String, Object?>{
                'serverIndex': serverIndex,
                'serverKeyHash': sha256.convert(utf8.encode(server.key)).toString(),
                'candidateIndex': candidates.length - 1,
              },
            );
          }
        }
        if (!stopped() && !shouldYield()) await completePhase('sni');
      }
      }

      if (shouldRunPhase('config') && !stopped() && !shouldYield() && !phaseDeferred) {
        await beginPhase('config');
        status(KingNatScanPhase.config, 'اسکنر: اعتبارسنجی ساختار کانفیگ‌ها...');
      if (!stopped() && !shouldYield()) {
        final resumeServerHash = resumePhase == 'config'
            ? resumeCursor['serverKeyHash']?.toString() : null;
        final foundResumeServer = resumeServerHash == null
            ? 0
            : seeds.indexWhere((server) =>
                sha256.convert(utf8.encode(server.key)).toString() == resumeServerHash);
        final resumeServer = foundResumeServer < 0 ? 0 : foundResumeServer;
        final resumeVariantCode = resumePhase == 'config' && foundResumeServer >= 0
            ? (resumeCursor['variantCode'] as num?)?.toInt() : null;
        for (var serverIndex = 0; serverIndex < seeds.length; serverIndex++) {
          if (stopped() || shouldYield()) break;
          final server = seeds[serverIndex];
          if (serverIndex < resumeServer || coreUnsupportedReason(server.link) != null) continue;
          final variants = planVariants(server, full: true);
          final resumeVariant = serverIndex == resumeServer && resumeVariantCode != null
              ? variants.indexOf(resumeVariantCode) : -1;
          for (var variantIndex = 0; variantIndex < variants.length; variantIndex++) {
            if (stopped() || shouldYield()) break;
            if (serverIndex == resumeServer && variantIndex <= resumeVariant) continue;
            final code = variants[variantIndex];
            try {
              final variant = code % _natCodeBase;
              if (!(server.reality && _natChangesAddr(variant))) {
                final decoded = jsonDecode(natCfg(server, variant));
                if (decoded is Map && decoded['outbounds'] is List &&
                    (decoded['outbounds'] as List).isNotEmpty) configsValidated++;
              }
            } catch (e, st) {
              logError(e, st);
            }
            await persistPhase(
              'config',
              completed: false,
              cursor: <String, Object?>{
                'serverIndex': serverIndex,
                'serverKeyHash': sha256.convert(utf8.encode(server.key)).toString(),
                'variantIndex': variantIndex,
                'variantCode': code,
              },
            );
          }
          if (!stopped() && !shouldYield()) {
            await persistPhase(
              'config',
              completed: false,
              cursor: <String, Object?>{
                'serverIndex': serverIndex,
                'serverKeyHash': sha256.convert(utf8.encode(server.key)).toString(),
                'variantIndex': variants.length - 1,
                if (variants.isNotEmpty) 'variantCode': variants.last,
              },
            );
          }
        }
        if (!stopped() && !shouldYield()) await completePhase('config');
      }
      }

      final didCancel = cancelled() || nationalMode != modeSnapshot;
      final didYield = shouldYield();
      if (!didCancel && !didYield && !phaseDeferred) {
        await beginPhase('complete');
        await completePhase('complete');
      }
      _scanPhase = didCancel ? KingNatScanPhase.cancelled : KingNatScanPhase.complete;
      if (didYield) warnings.add('scan_slice_yielded_cursor_preserved');
      if (kNatIpScanOn && !natRangeInventoryPassComplete &&
          !warnings.contains('ip_inventory_cursor_preserved_for_next_slice')) {
        warnings.add('ip_inventory_cursor_preserved_for_next_slice');
      }
      final report = KingNatScanReport(
        completed: !didCancel && !didYield && !phaseDeferred, timedOut: false,
        networkClass: NatNetworkDiagnosis.current, nationalMode: modeSnapshot,
        dnsResolvers: dnsCount, domainEndpoints: domainHits, ipEndpoints: ipHits,
        sniHandshakes: sniHits, alpnNegotiations: alpnHits,
        configsValidated: configsValidated, elapsedMs: clock.elapsedMilliseconds,
        warnings: List<String>.unmodifiable(warnings),
        domesticTlsSuccesses: networkEvidence.domesticSuccesses,
        globalTlsSuccesses: networkEvidence.globalSuccesses,
        domesticLatencyMs: networkEvidence.domesticLatencyMs,
        globalLatencyMs: networkEvidence.globalLatencyMs,
        networkConfidence: networkEvidence.confidence,
        domesticIpv6Successes: ipv6Evidence.domesticIpv6Successes,
        globalIpv6Successes: ipv6Evidence.globalIpv6Successes,
        domesticIpv6LatencyMs: ipv6Evidence.domesticIpv6LatencyMs,
        globalIpv6LatencyMs: ipv6Evidence.globalIpv6LatencyMs,
        inventoryPassComplete: natRangeInventoryPassComplete,
        sliceYielded: didYield,
      );
      dbg('KNS-SCAN: ' + jsonEncode(report.toMap()));
      return report;
    } catch (e, st) {
      logError(e, st);
      warnings.add('scanner_exception');
      _scanPhase = KingNatScanPhase.complete;
      return KingNatScanReport(
        completed: false, timedOut: expired(),
        networkClass: NatNetworkDiagnosis.current, nationalMode: modeSnapshot,
        dnsResolvers: dnsCount, domainEndpoints: domainHits, ipEndpoints: ipHits,
        sniHandshakes: sniHits, alpnNegotiations: alpnHits,
        configsValidated: configsValidated, elapsedMs: clock.elapsedMilliseconds,
        warnings: List<String>.unmodifiable(warnings),
        domesticTlsSuccesses: networkEvidence.domesticSuccesses,
        globalTlsSuccesses: networkEvidence.globalSuccesses,
        domesticLatencyMs: networkEvidence.domesticLatencyMs,
        globalLatencyMs: networkEvidence.globalLatencyMs,
        networkConfidence: networkEvidence.confidence,
        domesticIpv6Successes: networkEvidence.domesticIpv6Successes,
        globalIpv6Successes: networkEvidence.globalIpv6Successes,
        domesticIpv6LatencyMs: networkEvidence.domesticIpv6LatencyMs,
        globalIpv6LatencyMs: networkEvidence.globalIpv6LatencyMs,
        inventoryPassComplete: natRangeInventoryPassComplete,
        sliceYielded: shouldYield(),
      );
    } finally {
      if (ownsScannerLease) dnsxManualBusy = false;
      if (ownsProcessLease && processLeaseFile != null) {
        try {
          if (await processLeaseFile!.exists()) await processLeaseFile!.delete();
        } catch (e, st) {
          logError(e, st);
        }
      }
    }
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
      'version': 2,
      'networkClass': natNetworkClassLabel(NatNetworkDiagnosis.current),
      'routeEvidence': <String, Object?>{
        ...PilotNetworkProbe.current.toMap(),
        ...PilotIpv6Probe.current.toMap(),
      },
      'nationalMode': nationalMode,
      'variantCatalogSize': _natSpecs.length,
      'profileCount': _history.length,
      'recordCount': _recordCount,
      'scanPhase': _scanPhase.name,
      'lastScan': _lastScanReport?.toMap(),
      'sniPreferenceProfiles': _sniPreferences.length,
      'alpnPreferenceProfiles': _alpnPreferences.length,
      'sniProbeEvidence': _sniProbeEvidence,
      'alpnProbeEvidence': _alpnProbeEvidence,
      'attempts': attempts,
      'realTrafficSuccesses': successes,
      'realTrafficFailures': failures,
      'capabilityStatusCounts': counts,
      'registry': registry.map((e) => e.toMap()).toList(growable: false),
    };
  }
}