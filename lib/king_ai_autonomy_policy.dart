/// Guardrails for King's autonomous maintenance lifecycle.
///
/// Passive observation, evidence collection and official-document research may
/// run without owner interaction. Source mutations and release operations must
/// pass the separate owner-authentication and CI gates.
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
}

bool kingAiRequiresOwnerAuthorization(KingAiAutonomyOperation operation) =>
    switch (operation) {
      KingAiAutonomyOperation.applySourceChanges ||
      KingAiAutonomyOperation.changeDependencies ||
      KingAiAutonomyOperation.modifyVpnCoreOrNativeService ||
      KingAiAutonomyOperation.changeOwnerSecurityPolicy ||
      KingAiAutonomyOperation.publishRelease => true,
      _ => false,
    };

bool kingAiMayRunInBackground({
  required bool networkAvailable,
  required bool batteryNotLow,
  required bool userPaused,
}) => networkAvailable && batteryNotLow && !userPaused;

/// WorkManager periodic jobs are best-effort; Android may defer them.
const Duration kingAiOfficialResearchInterval = Duration(hours: 12);
const int kingAiBackgroundResearchMaxResults = 2;
