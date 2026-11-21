import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/network_health.dart';

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
        domesticSuccesses: 2,
        globalSuccesses: 0,
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
        domesticSuccesses: 0,
        globalSuccesses: 2,
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
        domesticSuccesses: 3,
        globalSuccesses: 3,
        domesticLatencyMs: 120,
        globalLatencyMs: 280,
        domesticTlsReachabilityVerified: true,
        globalTlsReachabilityVerified: true,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.domestic);
    });

    test('rejects healthy verdict without successful TLS quorum', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 0,
        globalSuccesses: 0,
        domesticTlsReachabilityVerified: false,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.preserve);
    });

    test('rejects unreachable verdict with contradictory successful probes', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 3,
        globalSuccesses: 1,
        domesticTlsReachabilityVerified: true,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.preserve);
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
  group('Persistent domestic/global route history', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PilotRouteHistory.resetForTesting();
    });

    test('stores aggregate evidence by coarse network group', () async {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 3,
        globalSuccesses: 0,
        domesticLatencyMs: 145,
        domesticTlsReachabilityVerified: true,
      );
      await PilotRouteHistory.record(
        networkGroup: 'mob|AS12345',
        evidence: evidence,
      );
      final saved = PilotRouteHistory.forNetwork('mob|AS12345');
      expect(saved?['observations'], 1);
      expect(saved?['domesticSuccesses'], 3);
      expect(saved?['globalSamples'], 3);
      expect(saved?['domesticOnly'], 1);
      expect(saved?['domesticLatencyEwmaMs'], 145.0);
    });

    test('rejects incomplete samples and identifying network labels', () async {
      const incomplete = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 1,
        globalSamples: 3,
        domesticSuccesses: 1,
      );
      await PilotRouteHistory.record(
        networkGroup: 'mob|AS12345',
        evidence: incomplete,
      );
      const complete = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 2,
      );
      await PilotRouteHistory.record(
        networkGroup: 'mob|AS12345|subscriber=private',
        evidence: complete,
      );
      expect(PilotRouteHistory.forNetwork('mob|AS12345'), isNull);
      expect(PilotRouteHistory.forNetwork('mob|AS12345|subscriber=private'), isNull);
    });
  });

}
