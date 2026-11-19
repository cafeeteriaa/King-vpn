/// Guardrails for King's autonomous maintenance lifecycle.
///
/// Passive observation, evidence collection and official-document research may
/// run without owner interaction. Isolated code candidates may be prepared only
/// after the owner has enabled the maintenance supervisor. Source mutations,
/// protected-surface changes and release operations remain owner-gated.
enum KingAiAutonomyOperation {
  observeNetwork,
  learnFromConnectionEvidence,
  tuneReversibleRuntimeSettings,
  researchOfficialDocumentation,
  prepareIsolatedCodeCandidate,
  applySourceChanges,
  changeDependencies,
  modifyVpnCoreOrNativeService,
  changeOwnerSecurityPolicy,
  publishRelease,
  mergeOrPublishRelease,
}

bool kingAiRequiresOwnerAuthorization(KingAiAutonomyOperation operation) =>
    switch (operation) {
      KingAiAutonomyOperation.applySourceChanges ||
      KingAiAutonomyOperation.changeDependencies ||
      KingAiAutonomyOperation.modifyVpnCoreOrNativeService ||
      KingAiAutonomyOperation.changeOwnerSecurityPolicy ||
      KingAiAutonomyOperation.publishRelease ||
      KingAiAutonomyOperation.mergeOrPublishRelease => true,
      _ => false,
    };

bool kingAiMayRunInBackground({
  required bool networkAvailable,
  required bool batteryNotLow,
  required bool userPaused,
}) => networkAvailable && batteryNotLow && !userPaused;

/// Android WorkManager is best-effort; Android may defer jobs under power policy.
const Duration kingAiOfficialResearchInterval = Duration(hours: 6);
const Duration kingAiCiRepairInterval = Duration(minutes: 15);
const int kingAiBackgroundResearchMaxResults = 2;
