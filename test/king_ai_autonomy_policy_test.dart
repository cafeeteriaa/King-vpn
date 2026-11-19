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

    test('keeps official research on a bounded six-hour cadence', () {
      expect(kingAiOfficialResearchInterval, const Duration(hours: 6));
      expect(kingAiBackgroundResearchMaxResults, 2);
    });

    test('does not tune runtime from a single or unverified sample', () {
      final plan = evaluateKingAiMaintenance(const KingAiMaintenanceEvidence(
        enabled: true, networkAvailable: true, batteryNotLow: true,
        userPaused: false, domesticSamples: 1, globalSamples: 0,
        successfulConnections: 1, rollbackSnapshotAvailable: true,
      ));
      expect(plan.runPassiveCycle, isTrue);
      expect(plan.mayTuneRuntime, isFalse);
      expect(plan.needsMoreEvidence, isTrue);
    });

    test('allows bounded runtime tuning only with evidence and rollback', () {
      final evidence = KingAiMaintenanceEvidence(
        enabled: true, networkAvailable: true, batteryNotLow: true,
        userPaused: false, domesticSamples: 2, globalSamples: 2,
        successfulConnections: 3, failedConnections: 1,
        rollbackSnapshotAvailable: true,
      );
      expect(evaluateKingAiMaintenance(evidence).mayTuneRuntime, isTrue);
      expect(evaluateKingAiMaintenance(KingAiMaintenanceEvidence(
        enabled: true, networkAvailable: true, batteryNotLow: true,
        userPaused: false, domesticSamples: 2, globalSamples: 2,
        successfulConnections: 3, failedConnections: 1,
      )).mayTuneRuntime, isFalse);
    });

    test('can prepare an isolated candidate automatically after reproducible evidence', () {
      final plan = evaluateKingAiMaintenance(const KingAiMaintenanceEvidence(
        enabled: true, networkAvailable: true, batteryNotLow: true,
        userPaused: false, domesticSamples: 4, globalSamples: 4,
        successfulConnections: 5, failedConnections: 3,
        reproducibleIssue: true,
      ));
      expect(plan.mayPrepareCodeCandidate, isTrue);
      expect(plan.mayApplySourceChanges, isFalse);
      expect(plan.mayPublishRelease, isFalse);
    });

    test('requires owner authentication and green CI before source changes', () {
      final noOwner = evaluateKingAiMaintenance(const KingAiMaintenanceEvidence(
        enabled: true, networkAvailable: true, batteryNotLow: true,
        userPaused: false, candidatePrepared: true, ciPassed: true,
      ));
      expect(noOwner.mayApplySourceChanges, isFalse);
      final noCi = evaluateKingAiMaintenance(const KingAiMaintenanceEvidence(
        enabled: true, networkAvailable: true, batteryNotLow: true,
        userPaused: false, candidatePrepared: true, ownerAuthenticated: true,
      ));
      expect(noCi.mayApplySourceChanges, isFalse);
      final approved = evaluateKingAiMaintenance(const KingAiMaintenanceEvidence(
        enabled: true, networkAvailable: true, batteryNotLow: true,
        userPaused: false, candidatePrepared: true, ownerAuthenticated: true,
        ciPassed: true,
      ));
      expect(approved.mayApplySourceChanges, isTrue);
      expect(approved.mayPublishRelease, isFalse);
    });

    test('domestic-only samples cannot stand in for global-route evidence', () {
      final plan = evaluateKingAiMaintenance(const KingAiMaintenanceEvidence(
        enabled: true, networkAvailable: true, batteryNotLow: true,
        userPaused: false, domesticSamples: 12, globalSamples: 0,
        successfulConnections: 8, failedConnections: 1,
        reproducibleIssue: true, rollbackSnapshotAvailable: true,
      ));
      expect(plan.mayTuneRuntime, isFalse);
      expect(plan.mayPrepareCodeCandidate, isFalse);
      expect(plan.needsMoreEvidence, isTrue);
    });

    test('publishing requires all source gates plus release validation', () {
      final plan = evaluateKingAiMaintenance(const KingAiMaintenanceEvidence(
        enabled: true, networkAvailable: true, batteryNotLow: true,
        userPaused: false, candidatePrepared: true, ownerAuthenticated: true,
        ciPassed: true, releaseValidated: true,
      ));
      expect(plan.mayApplySourceChanges, isTrue);
      expect(plan.mayPublishRelease, isTrue);
    });

    test('paused or unavailable background work cannot tune or prepare candidates', () {
      final plan = evaluateKingAiMaintenance(const KingAiMaintenanceEvidence(
        enabled: true, networkAvailable: false, batteryNotLow: true,
        userPaused: false, domesticSamples: 8, globalSamples: 8,
        successfulConnections: 8, reproducibleIssue: true,
        rollbackSnapshotAvailable: true,
      ));
      expect(plan.runPassiveCycle, isFalse);
      expect(plan.mayTuneRuntime, isFalse);
      expect(plan.mayPrepareCodeCandidate, isFalse);
    });
  });
}
