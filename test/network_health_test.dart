import 'package:flutter_test/flutter_test.dart';
import '../lib/network_health.dart';

void main() {
  group('independent probe-group classification', () {
    test('two successful handshakes establish a healthy group', () {
      expect(classifyLinkHealth(attempted: 3, successful: 2), LinkHealth.healthy);
      expect(classifyLinkHealth(attempted: 2, successful: 2), LinkHealth.healthy);
    });

    test('one successful handshake is degraded, not healthy', () {
      expect(classifyLinkHealth(attempted: 3, successful: 1), LinkHealth.degraded);
    });

    test('attempted probes with no success are unreachable', () {
      expect(classifyLinkHealth(attempted: 3, successful: 0), LinkHealth.unreachable);
    });

    test('no attempts and malformed counters cannot imply a failure or success', () {
      expect(classifyLinkHealth(attempted: 0, successful: 0), LinkHealth.unknown);
      expect(classifyLinkHealth(attempted: -1, successful: 9), LinkHealth.unknown);
      expect(classifyLinkHealth(attempted: 2, successful: 99), LinkHealth.healthy);
      expect(classifyLinkHealth(attempted: 2, successful: -1), LinkHealth.unreachable);
    });
  });

  group('Smart Pilot route policy', () {
    test('accepts valid HTTP final response lines over the verified TLS channel', () {
      expect(isValidHttpResponseLine('HTTP/1.1 200 OK'), isTrue);
      expect(isValidHttpResponseLine('HTTP/1.1 204 No Content'), isTrue);
      // A server-side 4xx/5xx still proves the network route reached the peer.
      expect(isValidHttpResponseLine('HTTP/1.1 403 Forbidden'), isTrue);
      expect(isValidHttpResponseLine('HTTP/1.0 503 Service Unavailable'), isTrue);
      expect(isValidHttpResponseLine('  HTTP/1.1\t 200\tOK  '), isTrue);
      expect(isValidHttpResponseLine('HTTP/1.1 599 Edge Error'), isTrue);
    });

    test('rejects malformed, proxy-banner and non-final response lines', () {
      for (final line in ['', 'connected', 'HTTP/2 200', 'HTTP/1.1 101 Switching Protocols', 'HTTP/1.1 xyz OK', 'HTTP/1.1 600 Unknown', 'HTTP/1.1 2000 OK', 'HTTP/1.1 099 Early', 'HTTP/1.1 2000', 'HTTP/1.1']) {
        expect(isValidHttpResponseLine(line), isFalse, reason: line);
      }
    });

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

    test('partial or absent probe groups never become an offline mode', () {
      const noSamples = NetworkEvidence(
        domestic: LinkHealth.unreachable,
        global: LinkHealth.unreachable,
      );
      const partial = NetworkEvidence(
        domestic: LinkHealth.unreachable,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 1,
      );
      expect(noSamples.mode, DetectedNetworkMode.unknown);
      expect(partial.mode, DetectedNetworkMode.unknown);
      expect(choosePilotNetworkStrategy(noSamples), PilotNetworkStrategy.preserve);
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

    test('confidence cannot exceed attempted samples or unearned TLS flags', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.healthy,
        domesticSamples: 1,
        globalSamples: 1,
        domesticSuccesses: 99,
        globalSuccesses: 99,
        domesticTlsReachabilityVerified: true,
        globalTlsReachabilityVerified: true,
      );
      expect(evidence.confidence, closeTo(2 / 6 * 0.55, 0.0001));
    });

    test('negative and inconsistent counters cannot create confidence', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.healthy,
        domesticSamples: -3,
        globalSamples: 0,
        domesticSuccesses: 3,
        globalSuccesses: 3,
        domesticTlsReachabilityVerified: true,
        globalTlsReachabilityVerified: true,
      );
      expect(evidence.confidence, 0);
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

    test('accepts the documented two-of-three success quorum', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 2,
        domesticSuccesses: 2,
        globalSuccesses: 0,
        domesticLatencyMs: 170,
        domesticTlsReachabilityVerified: true,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.domestic);
    });

    test('does not change route when the healthy group lacks full probe coverage', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 2,
        globalSamples: 3,
        domesticSuccesses: 2,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.preserve);
    });

    test('requires at least the full 80ms material latency gain', () {
      const below = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.healthy,
        domesticSamples: 3,
        globalSamples: 3,
        domesticLatencyMs: 151,
        globalLatencyMs: 230,
      );
      const atThreshold = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.healthy,
        domesticSamples: 3,
        globalSamples: 3,
        domesticLatencyMs: 150,
        globalLatencyMs: 230,
      );
      expect(choosePilotNetworkStrategy(below), PilotNetworkStrategy.preserve);
      expect(choosePilotNetworkStrategy(atThreshold), PilotNetworkStrategy.domestic);
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
