import 'package:flutter_test/flutter_test.dart';
import '../lib/network_health.dart';

void main() {
  group('Smart Pilot network strategy', () {
    test('selects domestic routing only with a confirmed domestic quorum', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 3,
        globalSamples: 2,
        domesticSuccesses: 2,
        domesticTlsReachabilityVerified: true,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.domestic);
    });

    test('preserves the current strategy when evidence is incomplete', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.unknown,
        global: LinkHealth.unknown,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.preserve);
    });

    test('selects global routing only when global quorum and domestic failure are confirmed', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.unreachable,
        global: LinkHealth.healthy,
        domesticSamples: 2,
        globalSamples: 3,
        globalSuccesses: 2,
        globalTlsReachabilityVerified: true,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.global);
    });
  });
}
