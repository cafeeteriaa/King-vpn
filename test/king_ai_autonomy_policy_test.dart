import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/king_ai_autonomy_policy.dart';

void main() {
  test('passive learning and isolated proposals do not require a live owner session', () {
    expect(kingAiRequiresOwnerAuthorization(KingAiAutonomyOperation.observeNetwork), isFalse);
    expect(kingAiRequiresOwnerAuthorization(KingAiAutonomyOperation.learnFromConnectionEvidence), isFalse);
    expect(kingAiRequiresOwnerAuthorization(KingAiAutonomyOperation.researchOfficialDocumentation), isFalse);
    expect(kingAiRequiresOwnerAuthorization(KingAiAutonomyOperation.prepareIsolatedCodeCandidate), isFalse);
  });

  test('applying code, changing protected surfaces and publishing are owner-gated', () {
    for (final operation in [
      KingAiAutonomyOperation.applySourceChanges,
      KingAiAutonomyOperation.changeDependencies,
      KingAiAutonomyOperation.modifyVpnCoreOrNativeService,
      KingAiAutonomyOperation.changeOwnerSecurityPolicy,
      KingAiAutonomyOperation.mergeOrPublishRelease,
    ]) {
      expect(kingAiRequiresOwnerAuthorization(operation), isTrue);
    }
  });

  test('background work respects connectivity, battery and pause state', () {
    expect(kingAiMayRunInBackground(networkAvailable: true, batteryNotLow: true, userPaused: false), isTrue);
    expect(kingAiMayRunInBackground(networkAvailable: false, batteryNotLow: true, userPaused: false), isFalse);
    expect(kingAiMayRunInBackground(networkAvailable: true, batteryNotLow: false, userPaused: false), isFalse);
    expect(kingAiMayRunInBackground(networkAvailable: true, batteryNotLow: true, userPaused: true), isFalse);
  });
}
