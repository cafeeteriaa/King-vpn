import 'package:flutter_test/flutter_test.dart';
import '../lib/network_health.dart';

void main() {
  group('canonical network identity', () {
    test('interface enumeration order does not change the identity input', () {
      expect(
        canonicalNetworkIdentity(['wlan0=192.0.2.2', 'rmnet0=198.51.100.3']),
        canonicalNetworkIdentity(['rmnet0=198.51.100.3', 'wlan0=192.0.2.2']),
      );
    });

    test('empty entries and surrounding whitespace are normalized', () {
      expect(
        canonicalNetworkIdentity([' wlan0=192.0.2.2 ', '', '  ']),
        'wlan0=192.0.2.2',
      );
    });

    test('address changes produce a different identity input', () {
      expect(
        canonicalNetworkIdentity(['wlan0=192.0.2.2']),
        isNot(canonicalNetworkIdentity(['wlan0=192.0.2.3'])),
      );
    });
  });

  group('single-flight probe refresh policy', () {
    test('ordinary refresh joins an existing refresh', () {
      expect(shouldJoinInFlightProbe(
        requestForce: false,
        activeForced: false,
      ), isTrue);
      expect(shouldJoinInFlightProbe(
        requestForce: false,
        activeForced: true,
      ), isTrue);
    });

    test('forced refresh joins only an already-forced refresh', () {
      expect(shouldJoinInFlightProbe(
        requestForce: true,
        activeForced: true,
      ), isTrue);
      expect(shouldJoinInFlightProbe(
        requestForce: true,
        activeForced: false,
      ), isFalse);
    });
  });

  group('network probe cache validity', () {
    final now = DateTime.utc(2026, 11, 25, 12);

    test('reuses only same-network evidence inside its TTL', () {
      expect(isProbeCacheFresh(
        force: false,
        currentIdentity: 'network-a',
        cachedIdentity: 'network-a',
        cachedAt: now.subtract(const Duration(seconds: 30)),
        now: now,
        ttl: const Duration(minutes: 2),
      ), isTrue);
    });

    test('forces refresh for empty or changed network identity', () {
      for (final identity in ['', 'network-b']) {
        expect(isProbeCacheFresh(
          force: false,
          currentIdentity: identity,
          cachedIdentity: 'network-a',
          cachedAt: now,
          now: now,
          ttl: const Duration(minutes: 2),
        ), isFalse);
      }
    });

    test('cache is fresh immediately before TTL but stale at the exact boundary', () {
      for (final sample in <({DateTime at, bool fresh})>[
        (at: now.subtract(const Duration(minutes: 2) - Duration(microseconds: 1)), fresh: true),
        (at: now.subtract(const Duration(minutes: 2)), fresh: false),
      ]) {
        expect(isProbeCacheFresh(
          force: false,
          currentIdentity: 'network-a',
          cachedIdentity: 'network-a',
          cachedAt: sample.at,
          now: now,
          ttl: const Duration(minutes: 2),
        ), sample.fresh);
      }
    });

    test('forces refresh for expired, missing or future-dated cache entries', () {
      final old = now.subtract(const Duration(minutes: 3));
      for (final cachedAt in <DateTime?>[
        old,
        null,
        now.add(const Duration(seconds: 1)),
      ]) {
        expect(isProbeCacheFresh(
          force: false,
          currentIdentity: 'network-a',
          cachedIdentity: 'network-a',
          cachedAt: cachedAt,
          now: now,
          ttl: const Duration(minutes: 2),
        ), isFalse);
      }
    });

    test('force flag and invalid TTL always bypass cache', () {
      expect(isProbeCacheFresh(
        force: true,
        currentIdentity: 'network-a',
        cachedIdentity: 'network-a',
        cachedAt: now,
        now: now,
        ttl: const Duration(minutes: 2),
      ), isFalse);
      expect(isProbeCacheFresh(
        force: false,
        currentIdentity: 'network-a',
        cachedIdentity: 'network-a',
        cachedAt: now,
        now: now,
        ttl: Duration.zero,
      ), isFalse);
    });
  });

  group('Smart Pilot HTTP request serialization', () {
    test('uses actual CRLF wire delimiters and terminates the header block', () {
      final request = buildPilotHttpHeadRequest('probe.example');
      expect(request, contains('HEAD / HTTP/1.1\r\n'));
      expect(request, contains('Host: probe.example\r\n'));
      expect(request, contains('Connection: close\r\n\r\n'));
      expect(request, isNot(contains(r'\r\n')));
    });

    test('keeps the host value in the HTTP Host header', () {
      expect(
        buildPilotHttpHeadRequest('edge.example'),
        startsWith('HEAD / HTTP/1.1\r\nHost: edge.example\r\n'),
      );
    });
  });

  group('Smart Pilot latency aggregation', () {
    test('median handles odd and even endpoint counts', () {
      expect(medianLatencyMs([90, 10, 50]), 50);
      expect(medianLatencyMs([100, 20, 80, 40]), 60);
    });

    test('median ignores absent and negative latency samples', () {
      expect(medianLatencyMs([null, -1, 120, 80]), 100);
      expect(medianLatencyMs([null, -1]), isNull);
      expect(medianLatencyMs([]), isNull);
    });
  });

  group('probe evidence consistency', () {
    test('requires health labels to match real sample counters', () {
      expect(isProbeGroupEvidenceConsistent(
        health: LinkHealth.healthy, attempted: 3, successful: 2,
      ), isTrue);
      expect(isProbeGroupEvidenceConsistent(
        health: LinkHealth.degraded, attempted: 3, successful: 1,
      ), isTrue);
      expect(isProbeGroupEvidenceConsistent(
        health: LinkHealth.unreachable, attempted: 3, successful: 0,
      ), isTrue);
    });

    test('rejects contradictory labels and impossible counters', () {
      expect(isProbeGroupEvidenceConsistent(
        health: LinkHealth.healthy, attempted: 3, successful: 0,
      ), isFalse);
      expect(isProbeGroupEvidenceConsistent(
        health: LinkHealth.unreachable, attempted: 3, successful: 1,
      ), isFalse);
      expect(isProbeGroupEvidenceConsistent(
        health: LinkHealth.healthy, attempted: 2, successful: 3,
      ), isFalse);
    });

    test('sub-quorum TLS observations do not earn a confidence bonus', () {
      const withoutTls = NetworkEvidence(
        domestic: LinkHealth.degraded,
        global: LinkHealth.unreachable,
        domesticSamples: 5,
        globalSamples: 5,
        domesticSuccesses: 3,
        globalSuccesses: 0,
      );
      const withTls = NetworkEvidence(
        domestic: LinkHealth.degraded,
        global: LinkHealth.unreachable,
        domesticSamples: 5,
        globalSamples: 5,
        domesticSuccesses: 3,
        globalSuccesses: 0,
        domesticTlsReachabilityVerified: true,
      );
      expect(withTls.acceptsTlsReachability(nationalOnly: true), isFalse);
      expect(withTls.confidence, withoutTls.confidence);
    });

    test('inconsistent counters cannot inflate confidence or TLS reachability', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 0,
        globalSuccesses: 0,
        domesticTlsReachabilityVerified: true,
      );
      expect(evidence.confidence, 0);
      expect(evidence.acceptsTlsReachability(nationalOnly: true), isFalse);
    });

    test('inconsistent group evidence cannot trigger route changes', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 0,
        globalSuccesses: 0,
      );
      expect(evidence.mode, DetectedNetworkMode.unknown);
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.preserve);
    });
  });

  group('independent probe-group classification', () {
    test('success quorum scales with the observed endpoint inventory', () {
      expect(requiredProbeSuccessQuorum(1), 2);
      expect(requiredProbeSuccessQuorum(2), 2);
      expect(requiredProbeSuccessQuorum(3), 2);
      expect(requiredProbeSuccessQuorum(4), 3);
      expect(requiredProbeSuccessQuorum(5), 4);
      expect(requiredProbeSuccessQuorum(6), 4);
      expect(requiredProbeSuccessQuorum(100), 67);
      expect(
        requiredProbeSuccessQuorum(0x7fffffffffffffff),
        0x5555555555555555,
      );
    });

    test('expanded inventories require a proportional healthy quorum', () {
      expect(classifyLinkHealth(attempted: 5, successful: 4), LinkHealth.healthy);
      expect(classifyLinkHealth(attempted: 5, successful: 3), LinkHealth.degraded);
      expect(classifyLinkHealth(attempted: 5, successful: 0), LinkHealth.unreachable);
    });

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
      expect(classifyLinkHealth(attempted: 2, successful: 99), LinkHealth.unknown);
      expect(classifyLinkHealth(attempted: 2, successful: -1), LinkHealth.unknown);
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
        global: LinkHealth.unreachable,
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
      expect(evidence.confidence, 0);
    });

    test('confidence scales with expanded probe inventories without a three-target cap', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.degraded,
        domesticSamples: 5,
        globalSamples: 5,
        domesticSuccesses: 4,
        globalSuccesses: 3,
        domesticTlsReachabilityVerified: true,
        globalTlsReachabilityVerified: true,
      );
      expect(evidence.confidence, closeTo(0.5425, 0.0001));
    });

    test('an unobserved group contributes zero coverage instead of disappearing', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unknown,
        domesticSamples: 5,
        globalSamples: 0,
        domesticSuccesses: 5,
        globalSuccesses: 0,
        domesticTlsReachabilityVerified: true,
      );
      expect(evidence.confidence, closeTo(0.3875, 0.0001));
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
        domesticSuccesses: 2,
        globalSuccesses: 2,
        domesticLatencyMs: 151,
        globalLatencyMs: 230,
      );
      const atThreshold = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.healthy,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 2,
        globalSuccesses: 2,
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
        domesticSuccesses: 2,
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
        globalSuccesses: 2,
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
        domesticSuccesses: 2,
        globalSuccesses: 2,
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
        domesticSuccesses: 2,
        globalSuccesses: 2,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.preserve);
    });


    test('reports unknown mode when only one domestic endpoint responds', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.degraded,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 1,
        globalSuccesses: 0,
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
        domesticSuccesses: 1,
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
