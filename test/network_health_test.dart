import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/main.dart' show corroboratePilotStrategy;
import 'package:king_vpn/nnie_core.dart' show NatNetworkClass;
import 'package:king_vpn/network_health.dart';

void main() {
  group('Smart Pilot route policy', () {
    test('confidence reaches 1.0 when all six dedicated probes are verified', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.healthy,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 3,
        globalSuccesses: 3,
        domesticTlsReachabilityVerified: true,
        globalTlsReachabilityVerified: true,
      );
      expect(evidence.confidence, 1.0);
    });

    test('confidence remains bounded and lower when probe coverage is partial', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.degraded,
        global: LinkHealth.unknown,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 1,
        globalSuccesses: 0,
      );
      expect(evidence.confidence, greaterThan(0));
      expect(evidence.confidence, lessThan(1));
    });

    test('keeps IPv6 reachability separate from TLS route classification', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 3,
        globalSuccesses: 0,
        domesticTlsReachabilityVerified: true,
        domesticIpv6Successes: 2,
        globalIpv6Successes: 0,
        domesticIpv6LatencyMs: 85,
      );
      expect(evidence.mode, DetectedNetworkMode.domesticOnly);
      expect(evidence.toMap()['domesticIpv6Successes'], 2);
      expect(evidence.toMap()['globalIpv6Successes'], 0);
      expect(evidence.toMap()['domesticIpv6LatencyMs'], 85);
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.domestic);
    });

    test('failed attempts do not inflate reachability confidence', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.unreachable,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 0,
        globalSuccesses: 0,
      );
      expect(evidence.confidence, 0);
      expect(evidence.mode, DetectedNetworkMode.offline);
    });

    test('one successful handshake gives only proportional confidence', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.degraded,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 1,
        globalSuccesses: 0,
      );
      expect(evidence.confidence, closeTo(0.55 / 6, 0.0001));
    });

    test('selects domestic only when global probes fail', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticLatencyMs: 140,
        domesticTlsReachabilityVerified: true,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.domestic);
    });

    test('selects global only when domestic probes fail', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.unreachable,
        global: LinkHealth.healthy,
        domesticSamples: 3,
        globalSamples: 3,
        globalLatencyMs: 190,
        globalTlsReachabilityVerified: true,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.global);
    });

    test('chooses materially faster route when both are reachable', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.healthy,
        domesticSamples: 3,
        globalSamples: 3,
        domesticLatencyMs: 120,
        globalLatencyMs: 280,
        domesticTlsReachabilityVerified: true,
        globalTlsReachabilityVerified: true,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.domestic);
    });

    test('preserves strategy when latency difference is insignificant', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.healthy,
        domesticSamples: 3,
        globalSamples: 3,
        domesticLatencyMs: 180,
        globalLatencyMs: 200,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.preserve);
    });


    test('reports unknown mode when only one domestic endpoint responds', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.degraded,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
      );
      expect(evidence.mode, DetectedNetworkMode.unknown);
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.preserve);
    });

    test('does not switch on a single responding endpoint', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.degraded,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticTlsReachabilityVerified: false,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.preserve);
    });

    test('does not classify domestic-only when global IPv6 path is independently reachable', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 3,
        domesticTlsReachabilityVerified: true,
        globalIpv6Successes: 2,
      );
      expect(evidence.mode, DetectedNetworkMode.unknown);
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.preserve);
    });

    test('merges independent IPv6 hints before Smart Pilot route selection', () {
      const tlsOnly = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 3,
        domesticTlsReachabilityVerified: true,
      );
      final merged = tlsOnly.withIpv6Evidence(
        domesticIpv6Successes: 0,
        globalIpv6Successes: 2,
      );
      expect(merged.mode, DetectedNetworkMode.unknown);
      expect(choosePilotNetworkStrategy(merged), PilotNetworkStrategy.preserve);
    });

    test('does not classify offline when either IPv6 path has independent reachability', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.unreachable,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        globalIpv6Successes: 2,
      );
      expect(evidence.mode, DetectedNetworkMode.unknown);
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.preserve);
    });

    test('independent DNS diagnosis vetoes contradictory domestic-only selection', () {
      expect(
        corroboratePilotStrategy(
          PilotNetworkStrategy.domestic,
          NatNetworkClass.globalReachable,
        ),
        PilotNetworkStrategy.preserve,
      );
    });

    test('independent DNS diagnosis vetoes contradictory global-only selection', () {
      expect(
        corroboratePilotStrategy(
          PilotNetworkStrategy.global,
          NatNetworkClass.domesticOnlyLikely,
        ),
        PilotNetworkStrategy.preserve,
      );
    });

    test('independent DNS evidence prevents a false offline switch', () {
      expect(
        corroboratePilotStrategy(
          PilotNetworkStrategy.offline,
          NatNetworkClass.transportRestricted,
        ),
        PilotNetworkStrategy.preserve,
      );
    });

    test('does not infer offline from missing evidence', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.unknown,
        global: LinkHealth.unknown,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.preserve);
    });

    test('selects offline only after both route groups fail', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.unreachable,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.offline);
    });
  });
  group('Net Melli network-change guard', () {
    test('fingerprint is stable regardless of interface ordering', () {
      final first = KingNetworkFingerprint.fromInterfaces(
        const <KingNetworkInterfaceSnapshot>[
          KingNetworkInterfaceSnapshot(name: 'wlan0', addresses: <String>['192.168.1.10', 'fe80::1']),
          KingNetworkInterfaceSnapshot(name: 'rmnet_data0', addresses: <String>['10.20.30.40']),
        ],
      );
      final second = KingNetworkFingerprint.fromInterfaces(
        const <KingNetworkInterfaceSnapshot>[
          KingNetworkInterfaceSnapshot(name: 'rmnet_data0', addresses: <String>['10.20.30.40']),
          KingNetworkInterfaceSnapshot(name: 'wlan0', addresses: <String>['fe80::1', '192.168.1.10']),
        ],
      );
      expect(first, second);
      expect(first, isNotEmpty);
    });

    test('VPN tunnel interfaces are excluded from the physical fingerprint', () {
      final physical = KingNetworkFingerprint.fromInterfaces(
        const <KingNetworkInterfaceSnapshot>[
          KingNetworkInterfaceSnapshot(name: 'wlan0', addresses: <String>['192.168.1.10']),
        ],
      );
      final withTunnel = KingNetworkFingerprint.fromInterfaces(
        const <KingNetworkInterfaceSnapshot>[
          KingNetworkInterfaceSnapshot(name: 'wlan0', addresses: <String>['192.168.1.10']),
          KingNetworkInterfaceSnapshot(name: 'tun0', addresses: <String>['10.8.0.2']),
        ],
      );
      expect(withTunnel, physical);
    });

    test('default route changes are detected even when both interfaces stay up', () {
      const interfaces = 'rmnet_data0|10.20.30.40;wlan0|192.168.1.10';
      final wifiRoute = KingNetworkFingerprint.withDefaultRoutes(
        interfaces, const <String>['v4:wlan0:0101A8C0:00000064']);
      final cellularRoute = KingNetworkFingerprint.withDefaultRoutes(
        interfaces, const <String>['v4:rmnet_data0:281E140A:00000032']);
      expect(KingNetworkFingerprint.changed(wifiRoute, cellularRoute), isTrue);
    });

    test('default-route parser ignores VPN tunnel routes and non-default routes', () {
      final routes = KingNetworkFingerprint.parseDefaultRoutes(
        ipv4Lines: const <String>[
          'Iface Destination Gateway Flags RefCnt Use Metric Mask MTU Window IRTT',
          'wlan0 00000000 0101A8C0 0001 0 0 100 00000000 0 0 0',
          'tun0 00000000 0100000A 0001 0 0 1 00000000 0 0 0',
          'wlan0 0001A8C0 00000000 0001 0 0 100 00FFFFFF 0 0 0',
        ],
      );
      expect(routes, <String>['v4:wlan0:0101A8C0:100']);
    });

    test('network handover cancels the scan monotonically', () {
      const initial = 'wlan0|192.168.1.10';
      final guard = KingNetworkScanGuard(initialFingerprint: initial);
      expect(guard.shouldCancel, isFalse);
      guard.observe(vpnInterfaceActive: false, currentFingerprint: initial);
      expect(guard.shouldCancel, isFalse);
      guard.observe(
        vpnInterfaceActive: false,
        currentFingerprint: 'rmnet_data0|10.20.30.40',
      );
      expect(guard.shouldCancel, isTrue);
      guard.observe(vpnInterfaceActive: false, currentFingerprint: initial);
      expect(guard.shouldCancel, isTrue);
    });

    test('VPN start and missing network evidence both fail closed', () {
      final guard = KingNetworkScanGuard(
        initialFingerprint: 'wlan0|192.168.1.10',
      );
      guard.observe(
        vpnInterfaceActive: true,
        currentFingerprint: 'wlan0|192.168.1.10',
      );
      expect(guard.shouldCancel, isTrue);
      final unknown = KingNetworkScanGuard(initialFingerprint: '');
      expect(unknown.shouldCancel, isTrue);
    });
  });

}
