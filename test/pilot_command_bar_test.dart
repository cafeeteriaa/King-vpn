import 'package:flutter_test/flutter_test.dart';
import '../lib/network_health.dart';

void main() {
  group('Smart Pilot network strategy', () {
    test('selects domestic routing only with repeated domestic evidence', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.unreachable,
        domesticSamples: 2,
        globalSamples: 2,
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

    test('prefers global routing when global reachability is confirmed', () {
      const evidence = NetworkEvidence(
        domestic: LinkHealth.healthy,
        global: LinkHealth.healthy,
        domesticSamples: 2,
        globalSamples: 2,
      );
      expect(choosePilotNetworkStrategy(evidence), PilotNetworkStrategy.global);
    });
  });
}
