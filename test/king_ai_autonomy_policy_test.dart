import 'package:flutter_test/flutter_test.dart';
import '../lib/king_ai_autonomy_policy.dart';

void main() {
  group('King AI autonomy guardrails', () {
    test('permits passive learning and isolated candidates without owner prompt', () {
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

    test('requires owner authorization for source and release mutations', () {
      for (final operation in <KingAiAutonomyOperation>[
        KingAiAutonomyOperation.applySourceChanges,
        KingAiAutonomyOperation.changeDependencies,
        KingAiAutonomyOperation.modifyVpnCoreOrNativeService,
        KingAiAutonomyOperation.changeOwnerSecurityPolicy,
        KingAiAutonomyOperation.publishRelease,
      ]) {
        expect(kingAiRequiresOwnerAuthorization(operation), isTrue);
      }
    });

    test('background research respects network, battery and pause gates', () {
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

    test('keeps the research cadence bounded', () {
      expect(kingAiOfficialResearchInterval, const Duration(hours: 12));
      expect(kingAiBackgroundResearchMaxResults, 2);
    });
  });
}
