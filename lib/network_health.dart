import 'dart:io';

/// Independent domestic/global network evidence model for Smart Pilot ∞.
enum LinkHealth { unknown, healthy, degraded, unreachable }
enum DetectedNetworkMode { unknown, domesticOnly, globalOnly, dualStack, offline }

/// Internal route selected by the single Smart Pilot controller.
enum PilotNetworkStrategy { domestic, global, preserve, offline }

class NetworkEvidence {
  const NetworkEvidence({
    required this.domestic,
    required this.global,
    this.domesticSamples = 0,
    this.globalSamples = 0,
    this.domesticSuccesses = 0,
    this.globalSuccesses = 0,
    this.domesticLatencyMs,
    this.globalLatencyMs,
    this.domesticTlsReachabilityVerified = false,
    this.globalTlsReachabilityVerified = false,
    this.domesticIpv6Successes = 0,
    this.globalIpv6Successes = 0,
    this.domesticIpv6LatencyMs,
    this.globalIpv6LatencyMs,
  });

  final LinkHealth domestic;
  final LinkHealth global;
  final int domesticSamples;
  final int globalSamples;
  final int domesticSuccesses;
  final int globalSuccesses;
  final int? domesticLatencyMs;
  final int? globalLatencyMs;
  final bool domesticTlsReachabilityVerified;
  final bool globalTlsReachabilityVerified;
  /// IPv6 path reachability is tracked separately from authenticated TLS.
  final int domesticIpv6Successes;
  final int globalIpv6Successes;
  final int? domesticIpv6LatencyMs;
  final int? globalIpv6LatencyMs;

  Map<String, Object?> toMap() => <String, Object?>{
    'domestic': domestic.name,
    'global': global.name,
    'domesticSamples': domesticSamples,
    'globalSamples': globalSamples,
    'domesticSuccesses': domesticSuccesses,
    'globalSuccesses': globalSuccesses,
    'domesticLatencyMs': domesticLatencyMs,
    'globalLatencyMs': globalLatencyMs,
    'domesticIpv6Successes': domesticIpv6Successes,
    'globalIpv6Successes': globalIpv6Successes,
    'domesticIpv6LatencyMs': domesticIpv6LatencyMs,
    'globalIpv6LatencyMs': globalIpv6LatencyMs,
    'confidence': confidence,
    'mode': mode.name,
  };

  NetworkEvidence withIpv6Evidence({
    required int domesticIpv6Successes,
    required int globalIpv6Successes,
    int? domesticIpv6LatencyMs,
    int? globalIpv6LatencyMs,
  }) => NetworkEvidence(
    domestic: domestic,
    global: global,
    domesticSamples: domesticSamples,
    globalSamples: globalSamples,
    domesticSuccesses: this.domesticSuccesses,
    globalSuccesses: this.globalSuccesses,
    domesticLatencyMs: this.domesticLatencyMs,
    globalLatencyMs: this.globalLatencyMs,
    domesticTlsReachabilityVerified: domesticTlsReachabilityVerified,
    globalTlsReachabilityVerified: globalTlsReachabilityVerified,
    domesticIpv6Successes: domesticIpv6Successes,
    globalIpv6Successes: globalIpv6Successes,
    domesticIpv6LatencyMs: domesticIpv6LatencyMs,
    globalIpv6LatencyMs: globalIpv6LatencyMs,
  );

  DetectedNetworkMode get mode {
    if (domestic == LinkHealth.unknown && global == LinkHealth.unknown) {
      return DetectedNetworkMode.unknown;
    }
    // A degraded group means only one endpoint responded; do not label it
    // as a confirmed network class or infer the other side is unavailable.
    if (domestic == LinkHealth.degraded || global == LinkHealth.degraded) {
      return DetectedNetworkMode.unknown;
    }
    final domesticUp = domestic == LinkHealth.healthy;
    final globalUp = global == LinkHealth.healthy;
    final domesticIpv6Hint = domesticIpv6Successes >= 2;
    final globalIpv6Hint = globalIpv6Successes >= 2;
    if (!domesticUp && !globalUp) {
      if (domestic == LinkHealth.unreachable && global == LinkHealth.unreachable) {
        // TCP/443 over IPv6 is only a path hint; it prevents a false offline
        // label but never upgrades the route to verified HTTPS reachability.
        return domesticIpv6Hint || globalIpv6Hint
            ? DetectedNetworkMode.unknown
            : DetectedNetworkMode.offline;
      }
      return DetectedNetworkMode.unknown;
    }
    if (domesticUp && globalUp) return DetectedNetworkMode.dualStack;
    if (domesticUp && global == LinkHealth.unreachable) {
      return globalIpv6Hint
          ? DetectedNetworkMode.unknown
          : DetectedNetworkMode.domesticOnly;
    }
    if (globalUp && domestic == LinkHealth.unreachable) {
      return domesticIpv6Hint
          ? DetectedNetworkMode.unknown
          : DetectedNetworkMode.globalOnly;
    }
    return DetectedNetworkMode.unknown;
  }

  /// TLS reachability is not proof that VPN tunnel traffic is passing.
  /// This helper reports only the matching endpoint group's TLS evidence.
  bool acceptsTlsReachability({required bool nationalOnly}) =>
      nationalOnly ? domesticTlsReachabilityVerified : globalTlsReachabilityVerified;

  double get confidence {
    // Count actual successful TLS handshakes, not attempts. Failed probes are
    // evidence for route classification but must never inflate reachability confidence.
    final successfulSamples = (domesticSuccesses + globalSuccesses).clamp(0, 6);
    if (successfulSamples <= 0) return 0;
    // The dedicated pilot scanner samples exactly three domestic and three global targets.
    // Six successful samples with both groups verified reach 100%.
    final coverage = (successfulSamples / 6).clamp(0, 1).toDouble();
    final verified = (domesticTlsReachabilityVerified ? 1 : 0) +
        (globalTlsReachabilityVerified ? 1 : 0);
    return (coverage * (0.55 + verified * 0.225)).clamp(0, 1).toDouble();
  }
}


/// Conservative strategy selection with minimum evidence requirements.
/// Partial evidence preserves the last strategy instead of guessing.
PilotNetworkStrategy choosePilotNetworkStrategy(NetworkEvidence evidence) {
  // A single successful endpoint is only a hint (degraded), not enough to
  // change the active route. Require the scanner's >=2/3 quorum on each side.
  final domesticConfirmed = evidence.domestic == LinkHealth.healthy &&
      evidence.domesticSamples >= 3;
  final globalConfirmed = evidence.global == LinkHealth.healthy &&
      evidence.globalSamples >= 3;
  final domesticFailed = evidence.domestic == LinkHealth.unreachable &&
      evidence.domesticSamples >= 2;
  final globalFailed = evidence.global == LinkHealth.unreachable &&
      evidence.globalSamples >= 2;

  // A contradictory IPv6 path is a reason to preserve the current route,
  // not proof that HTTPS works over IPv6. Do not label the opposite family cut.
  if (domesticConfirmed && globalFailed && evidence.globalIpv6Successes >= 2) {
    return PilotNetworkStrategy.preserve;
  }
  if (globalConfirmed && domesticFailed && evidence.domesticIpv6Successes >= 2) {
    return PilotNetworkStrategy.preserve;
  }
  if (domesticConfirmed && globalConfirmed) {
    final domesticMs = evidence.domesticLatencyMs;
    final globalMs = evidence.globalLatencyMs;
    if (domesticMs != null && globalMs != null) {
      // Switch only for a material gain; avoid oscillation on tiny variations.
      if (domesticMs <= globalMs * 0.80 && globalMs - domesticMs >= 80) {
        return PilotNetworkStrategy.domestic;
      }
      if (globalMs <= domesticMs * 0.80 && domesticMs - globalMs >= 80) {
        return PilotNetworkStrategy.global;
      }
    }
    return PilotNetworkStrategy.preserve;
  }
  if (domesticConfirmed && !globalConfirmed && globalFailed) return PilotNetworkStrategy.domestic;
  if (globalConfirmed && !domesticConfirmed && domesticFailed) return PilotNetworkStrategy.global;
  if (domesticFailed && globalFailed) {
    return evidence.domesticIpv6Successes >= 2 ||
            evidence.globalIpv6Successes >= 2
        ? PilotNetworkStrategy.preserve
        : PilotNetworkStrategy.offline;
  }
  return PilotNetworkStrategy.preserve;
}


/// A stable, testable snapshot of the non-VPN network interfaces.
class KingNetworkInterfaceSnapshot {
  const KingNetworkInterfaceSnapshot({
    required this.name,
    required this.addresses,
  });

  final String name;
  final List<String> addresses;
}

/// Fingerprints the active physical network without including the VPN TUN.
/// The result changes when the active interface or its addresses change.
class KingNetworkFingerprint {
  KingNetworkFingerprint._();

  static final RegExp _vpnInterfaceName =
      RegExp(r'^(tun|tap|ppp|wg|utun|vpn)[0-9]*', caseSensitive: false);

  static String fromInterfaces(
    Iterable<KingNetworkInterfaceSnapshot> interfaces,
  ) {
    final values = <String>{};
    for (final interface in interfaces) {
      final name = interface.name.trim().toLowerCase();
      if (name.isEmpty || _vpnInterfaceName.hasMatch(name)) continue;
      for (final rawAddress in interface.addresses) {
        final address = rawAddress.trim();
        if (address.isEmpty || address == '127.0.0.1' || address == '::1') {
          continue;
        }
        values.add('$name|$address');
      }
    }
    final sorted = values.toList()..sort();
    return sorted.join(';');
  }

  static List<String> parseDefaultRoutes({
    Iterable<String> ipv4Lines = const <String>[],
    Iterable<String> ipv6Lines = const <String>[],
  }) {
    final routes = <String>{};
    for (final line in ipv4Lines) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 8 || fields[1] != '00000000' || fields[7] != '00000000') continue;
      final flags = int.tryParse(fields[3], radix: 16) ?? 0;
      final iface = fields[0].toLowerCase();
      if ((flags & 1) == 0 || _vpnInterfaceName.hasMatch(iface)) continue;
      routes.add('v4:$iface:${fields[2]}:${fields[6]}');
    }
    for (final line in ipv6Lines) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 10 || fields[0] != List<String>.filled(32, '0').join() ||
          fields[1].toLowerCase() != '00') continue;
      final flags = int.tryParse(fields[8], radix: 16) ?? 0;
      final iface = fields[9].toLowerCase();
      if ((flags & 1) == 0 || _vpnInterfaceName.hasMatch(iface)) continue;
      routes.add('v6:$iface:${fields[4]}:${fields[5]}');
    }
    return routes.toList()..sort();
  }

  static String withDefaultRoutes(String interfaces, Iterable<String> routes) {
    final sorted = routes.toList()..sort();
    return '$interfaces#${sorted.join(';')}';
  }

  static Future<String> capture() async {
    final interfaces = await NetworkInterface.list(includeLoopback: false);
    final interfaceFingerprint = fromInterfaces(interfaces.map((interface) =>
        KingNetworkInterfaceSnapshot(
          name: interface.name,
          addresses: interface.addresses
              .where((address) => !address.isLoopback)
              .map((address) => address.address)
              .toList(growable: false),
        )));
    // Interface lists alone miss a default-route switch when Wi-Fi and cellular
    // are both up. Linux/Android route tables provide the active default egress.
    Future<List<String>> readRoutes(String path) async {
      try {
        return await File(path).readAsLines();
      } catch (_) {
        return const <String>[];
      }
    }
    final ipv4 = await readRoutes('/proc/net/route');
    final ipv6 = await readRoutes('/proc/net/ipv6_route');
    final defaults = parseDefaultRoutes(ipv4Lines: ipv4, ipv6Lines: ipv6);
    return withDefaultRoutes(interfaceFingerprint, defaults);
  }

  static bool changed(String before, String after) =>
      before.trim().isEmpty || after.trim().isEmpty || before != after;
}

/// Monotonic fail-closed guard for long-running network discovery.
class KingNetworkScanGuard {
  KingNetworkScanGuard({required this.initialFingerprint})
      : _cancelled = initialFingerprint.trim().isEmpty;

  final String initialFingerprint;
  bool _cancelled;

  bool get shouldCancel => _cancelled;

  void observe({
    required bool vpnInterfaceActive,
    required String currentFingerprint,
  }) {
    if (vpnInterfaceActive ||
        KingNetworkFingerprint.changed(initialFingerprint, currentFingerprint)) {
      _cancelled = true;
    }
  }
}
