import 'package:flutter_test/flutter_test.dart';
import '../lib/network_health.dart';

void main() {
  group('forced network probe refresh coordination', () {
    test('queues one forced scan behind an active ordinary scan', () async {
      final coordinator = NetworkProbeRefreshCoordinator<int>();
      final ordinaryGate = Completer<void>();
      final forcedGate = Completer<void>();
      final calls = <bool>[];

      Future<int> scan({required bool force}) async {
        calls.add(force);
        if (force) {
          await forcedGate.future;
        } else {
          await ordinaryGate.future;
        }
        return calls.length;
      }

      final ordinary = coordinator.run(scan);
      final forced = coordinator.run(scan, force: true);
      final duplicateForced = coordinator.run(scan, force: true);
      final joined = coordinator.run(scan);
      expect(calls, <bool>[false]);

      ordinaryGate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(calls, <bool>[false, true]);

      forcedGate.complete();
      expect(await ordinary, 1);
      expect(await forced, 2);
      expect(await duplicateForced, 2);
      expect(await joined, 2);
      expect(calls, <bool>[false, true]);
    });

    test('a failed ordinary scan does not discard a queued forced scan', () async {
      final coordinator = NetworkProbeRefreshCoordinator<int>();
      final ordinaryGate = Completer<void>();
      final forcedGate = Completer<void>();
      final calls = <bool>[];

      Future<int> scan({required bool force}) async {
        calls.add(force);
        if (force) {
          await forcedGate.future;
          return 7;
        }
        await ordinaryGate.future;
        throw StateError('ordinary probe failed');
      }

      final ordinary = coordinator.run(scan);
      final forced = coordinator.run(scan, force: true);
      ordinaryGate.complete();
      await expectLater(ordinary, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(calls, <bool>[false, true]);

      forcedGate.complete();
      expect(await forced, 7);
    });
  });

  group('network probe cache policy', () {
    final checkedAt = DateTime.utc(2026, 11, 22, 7);
    final now = DateTime.utc(2026, 11, 22, 7, 1);
    const ttl = Duration(minutes: 2);

    test('reuses a fresh cache only for a known matching network identity', () {
      expect(shouldReuseNetworkProbeCache(
        force: false,
        currentIdentity: 'network-a',
        cachedIdentity: 'network-a',
        checkedAt: checkedAt,
        now: now,
        ttl: ttl,
      ), isTrue);
    });

    test('does not reuse cache when current identity could not be read', () {
      expect(shouldReuseNetworkProbeCache(
        force: false,
        currentIdentity: '',
        cachedIdentity: '',
        checkedAt: checkedAt,
        now: now,
        ttl: ttl,
      ), isFalse);
    });

    test('does not reuse cache after the device changes networks', () {
      expect(shouldReuseNetworkProbeCache(
        force: false,
        currentIdentity: 'network-b',
        cachedIdentity: 'network-a',
        checkedAt: checkedAt,
        now: now,
        ttl: ttl,
      ), isFalse);
    });

    test('does not reuse cache when prior identity is missing', () {
      expect(shouldReuseNetworkProbeCache(
        force: false,
        currentIdentity: 'network-a',
        cachedIdentity: null,
        checkedAt: checkedAt,
        now: now,
        ttl: ttl,
      ), isFalse);
    });

    test('does not reuse expired cache or cache from a future clock time', () {
      expect(shouldReuseNetworkProbeCache(
        force: false,
        currentIdentity: 'network-a',
        cachedIdentity: 'network-a',
        checkedAt: checkedAt,
        now: checkedAt.add(const Duration(minutes: 3)),
        ttl: ttl,
      ), isFalse);
      expect(shouldReuseNetworkProbeCache(
        force: false,
        currentIdentity: 'network-a',
        cachedIdentity: 'network-a',
        checkedAt: now,
        now: checkedAt,
        ttl: ttl,
      ), isFalse);
    });

    test('force always bypasses the cache', () {
      expect(shouldReuseNetworkProbeCache(
        force: true,
        currentIdentity: 'network-a',
        cachedIdentity: 'network-a',
        checkedAt: checkedAt,
        now: now,
        ttl: ttl,
      ), isFalse);
    });
  });


  group('probe evidence freshness', () {
    final checkedAt = DateTime.utc(2026, 11, 22, 7);

    test('accepts evidence strictly inside the two-minute TTL', () {
      expect(isNetworkProbeEvidenceFresh(
        checkedAt: checkedAt,
        now: checkedAt.add(const Duration(minutes: 1, seconds: 59)),
        ttl: const Duration(minutes: 2),
      ), isTrue);
    });

    test('rejects expired, future, missing and non-positive-TTL evidence', () {
      expect(isNetworkProbeEvidenceFresh(
        checkedAt: checkedAt,
        now: checkedAt.add(const Duration(minutes: 2)),
        ttl: const Duration(minutes: 2),
      ), isFalse);
      expect(isNetworkProbeEvidenceFresh(
        checkedAt: checkedAt.add(const Duration(seconds: 1)),
        now: checkedAt,
        ttl: const Duration(minutes: 2),
      ), isFalse);
      expect(isNetworkProbeEvidenceFresh(
        checkedAt: null,
        now: checkedAt,
        ttl: const Duration(minutes: 2),
      ), isFalse);
      expect(isNetworkProbeEvidenceFresh(
        checkedAt: checkedAt,
        now: checkedAt,
        ttl: Duration.zero,
      ), isFalse);
    });
  });

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

    test('labels domestic and global reachability without implying IP-family dual stack', () {
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
      expect(evidence.mode, DetectedNetworkMode.dualReachable);
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

    test('preserves strategy when latency difference is insignificant', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.healthy,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 2,
        globalSuccesses: 2,
        domesticLatencyMs: 180,
        globalLatencyMs: 200,
        domesticTlsReachabilityVerified: true,
        globalTlsReachabilityVerified: true,
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


    test('does not switch on inconsistent healthy labels without TLS quorum', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 1,
        globalSuccesses: 0,
        domesticTlsReachabilityVerified: false,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.preserve);
    });

    test('does not confirm a route when success counters exceed sampled probes', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.healthy,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 99,
        globalSuccesses: 99,
        domesticTlsReachabilityVerified: true,
        globalTlsReachabilityVerified: true,
      );
      expect(evidence.domesticConfirmed, isFalse);
      expect(evidence.globalConfirmed, isFalse);
      expect(evidence.mode, DetectedNetworkMode.unknown);
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.preserve);
    });

    test('confidence never counts more successes than available samples', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.healthy,
        domesticSamples: 1,
        globalSamples: 1,
        domesticSuccesses: 99,
        globalSuccesses: 99,
      );
      expect(evidence.confidence, closeTo(0.55 * 2 / 6, 0.0001));
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
        domesticSuccesses: 0,
        globalSuccesses: 0,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.offline);
    });
  });
  group('network probe snapshot integrity', () {
    test('accepts only matching, non-empty before and after identities', () {
      expect(sameKnownNetworkProbeIdentity('wifi-a', 'wifi-a'), isTrue);
      expect(sameKnownNetworkProbeIdentity('wifi-a', 'mobile-b'), isFalse);
      expect(sameKnownNetworkProbeIdentity('', ''), isFalse);
      expect(sameKnownNetworkProbeIdentity('wifi-a', ''), isFalse);
    });

    test('does not promote an inconsistent healthy label without TLS quorum', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 1,
        globalSuccesses: 0,
        domesticTlsReachabilityVerified: false,
      );
      expect(evidence.mode, DetectedNetworkMode.unknown);
      expect(evidence.acceptsTlsReachability(nationalOnly: true), isFalse);
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.preserve);
    });

    test('does not infer offline from zero or insufficient failed samples', () {
      const noSamples = NetworkEvidence(
        domestic: LinkHealth.unreachable,
        global: LinkHealth.unreachable,
      );
      const oneEach = NetworkEvidence(
        domestic: LinkHealth.unreachable,
        global: LinkHealth.unreachable,
        domesticSamples: 1,
        globalSamples: 1,
      );
      expect(noSamples.mode, DetectedNetworkMode.unknown);
      expect(oneEach.mode, DetectedNetworkMode.unknown);
      expect(choosePilotNetworkStrategy(noSamples), PilotNetworkStrategy.preserve);
    });

    test('mode and strategy share the same verified quorum', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 3,
        domesticSuccesses: 2,
        globalSuccesses: 0,
        domesticTlsReachabilityVerified: true,
      );
      expect(evidence.mode, DetectedNetworkMode.domesticOnly);
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.domestic);
    });

    test('TLS flag without matching sample quorum adds no confidence bonus', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.degraded,
        global: LinkHealth.unknown,
        domesticSamples: 1,
        globalSamples: 0,
        domesticSuccesses: 1,
        domesticTlsReachabilityVerified: true,
      );
      expect(evidence.confidence, closeTo(0.55 / 6, 0.0001));
    });
  });


  group('route-scoped Pilot learning and domestic ordering', () {
    test('protocol profile keys cannot cross-contaminate domestic and global modes', () {
      expect(
        networkScopedProfileKey('operator|vless|ws', nationalMode: true),
        'domestic|operator|vless|ws',
      );
      expect(
        networkScopedProfileKey('operator|vless|ws', nationalMode: false),
        'global|operator|vless|ws',
      );
      expect(
        networkScopedProfileKey('operator|vless|ws', nationalMode: true),
        isNot(networkScopedProfileKey('operator|vless|ws', nationalMode: false)),
      );
    });

    test('Pilot domestic ordering needs an enabled national route and verified evidence', () {
      expect(shouldPreferDomesticCandidates(
        legacyDiagnosisPrefersDomestic: false,
        localPilotEnabled: true,
        nationalMode: true,
        pilotDomesticConfirmed: true,
      ), isTrue);
      expect(shouldPreferDomesticCandidates(
        legacyDiagnosisPrefersDomestic: false,
        localPilotEnabled: true,
        nationalMode: true,
        pilotDomesticConfirmed: false,
      ), isFalse);
      expect(shouldPreferDomesticCandidates(
        legacyDiagnosisPrefersDomestic: false,
        localPilotEnabled: true,
        nationalMode: false,
        pilotDomesticConfirmed: true,
      ), isFalse);
      expect(shouldPreferDomesticCandidates(
        legacyDiagnosisPrefersDomestic: true,
        localPilotEnabled: false,
        nationalMode: false,
        pilotDomesticConfirmed: false,
      ), isTrue);
    });
  });


}
