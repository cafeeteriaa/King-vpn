import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/king_ai_autonomy_policy.dart';

void main() {
  group('King AI autonomy guardrails', () {
    test('passive learning and isolated candidates do not require owner prompt', () {
      for (final operation in <KingAiAutonomyOperation>[
        KingAiAutonomyOperation.observeNetwork,
        KingAiAutonomyOperation.learnFromConnectionEvidence,
        KingAiAutonomyOperation.tuneReversibleRuntimeSettings,
        KingAiAutonomyOperation.researchOfficialDocumentation,
        KingAiAutonomyOperation.prepareIsolatedCodeCandidate,
      ]) {
        expect(kingAiRequiresOwnerAuthorization(operation), isFalse);
      }
    });

    test('source changes, protected surfaces and release operations are owner-gated', () {
      for (final operation in <KingAiAutonomyOperation>[
        KingAiAutonomyOperation.applySourceChanges,
        KingAiAutonomyOperation.changeDependencies,
        KingAiAutonomyOperation.modifyVpnCoreOrNativeService,
        KingAiAutonomyOperation.changeOwnerSecurityPolicy,
        KingAiAutonomyOperation.publishRelease,
        KingAiAutonomyOperation.mergeOrPublishRelease,
      ]) {
        expect(kingAiRequiresOwnerAuthorization(operation), isTrue);
      }
    });

    test('background work respects network, battery and pause gates', () {
      expect(kingAiMayRunInBackground(
        networkAvailable: true, batteryNotLow: true, userPaused: false,
      ), isTrue);
      expect(kingAiMayRunInBackground(
        networkAvailable: false, batteryNotLow: true, userPaused: false,
      ), isFalse);
      expect(kingAiMayRunInBackground(
        networkAvailable: true, batteryNotLow: false, userPaused: false,
      ), isFalse);
      expect(kingAiMayRunInBackground(
        networkAvailable: true, batteryNotLow: true, userPaused: true,
      ), isFalse);
    });

    test('research cadence and result budget stay bounded', () {
      expect(kingAiOfficialResearchInterval, const Duration(hours: 6));
      expect(kingAiCiRepairInterval, const Duration(minutes: 15));
      expect(kingAiBackgroundResearchMaxResults, 2);
    });
  });
}
