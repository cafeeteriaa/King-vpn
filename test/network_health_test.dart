import 'package:flutter_test/flutter_test.dart';
import '../lib/network_health.dart';

void main() {
  group('Smart Pilot route policy', () {
    test('confidence reaches 1.0 when all collected probes are verified', () {
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

    test('confidence scales with dynamically expanded probe coverage', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.healthy,
        domesticSamples: 10,
        globalSamples: 10,
        domesticSuccesses: 10,
        globalSuccesses: 10,
        domesticTlsReachabilityVerified: true,
        globalTlsReachabilityVerified: true,
      );
      expect(evidence.confidence, 1.0);
    });

    test('partial evidence uses the actual sample count, not a fixed six-sample denominator', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.degraded,
        global: LinkHealth.unknown,
        domesticSamples: 10,
        globalSamples: 10,
        domesticSuccesses: 1,
        globalSuccesses: 0,
      );
      expect(evidence.confidence, closeTo(0.55 / 20, 0.0001));
    });

    test('success counters cannot exceed their route attempt counts', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unknown,
        domesticSamples: 2,
        globalSamples: 0,
        domesticSuccesses: 200,
        globalSuccesses: 200,
        domesticTlsReachabilityVerified: true,
        globalTlsReachabilityVerified: true,
      );
      expect(evidence.confidence, closeTo(0.775, 0.0001));
    });

    test('success counters without recorded attempts do not create confidence', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.healthy,
        domesticSuccesses: 100,
        globalSuccesses: 100,
        domesticTlsReachabilityVerified: true,
        globalTlsReachabilityVerified: true,
      );
      expect(evidence.confidence, 0);
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
}
