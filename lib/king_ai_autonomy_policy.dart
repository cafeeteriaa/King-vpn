/// Explicit safety boundary for King's autonomous maintenance lifecycle.
enum KingAiAutonomyOperation {
  observeNetwork,
  learnFromConnectionEvidence,
  researchOfficialDocumentation,
  tuneReversibleRuntimeSettings,
  prepareIsolatedCodeCandidate,
  applySourceChanges,
  changeDependencies,
  modifyVpnCoreOrNativeService,
  changeOwnerSecurityPolicy,
  mergeOrPublishRelease,
}

/// Background observation, local learning and allowlisted research are
/// read-only. Code proposals may be prepared only after the owner has enabled
/// the autonomous maintenance supervisor. Applying or publishing remains
/// owner-gated and CI-gated.
bool kingAiRequiresOwnerAuthorization(KingAiAutonomyOperation operation) =>
    switch (operation) {
      KingAiAutonomyOperation.applySourceChanges ||
      KingAiAutonomyOperation.changeDependencies ||
      KingAiAutonomyOperation.modifyVpnCoreOrNativeService ||
      KingAiAutonomyOperation.changeOwnerSecurityPolicy ||
      KingAiAutonomyOperation.mergeOrPublishRelease => true,
      _ => false,
    };

bool kingAiMayRunInBackground({
  required bool networkAvailable,
  required bool batteryNotLow,
  required bool userPaused,
}) => networkAvailable && batteryNotLow && !userPaused;

/// Android WorkManager is best-effort; it may defer work under power policy.
const Duration kingAiOfficialResearchInterval = Duration(hours: 6);
const Duration kingAiCiRepairInterval = Duration(minutes: 15);
const int kingAiBackgroundResearchMaxResults = 2;
