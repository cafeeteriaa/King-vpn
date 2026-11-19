/// Guardrails for King's autonomous maintenance lifecycle.
///
/// Observation, evidence learning and bounded official-document research can
/// run without owner interaction. The local AI may prepare an isolated source
/// candidate when a reproducible issue is supported by enough measurements.
/// Applying source changes, changing dependencies/native VPN code, changing
/// owner security, or publishing a release always requires owner authorization.
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

/// Minimum evidence before autonomous tuning or code-candidate preparation.
/// These are deliberately conservative; a single successful connection never
/// means the whole Iranian network has been characterized.
const int kingAiMinimumSamplesForRuntimeTuning = 4;
const int kingAiMinimumSamplesForCodeCandidate = 8;

/// WorkManager is best-effort and Android may defer work. Six hours is the
/// research cadence, not a promise of exact execution time.
const Duration kingAiOfficialResearchInterval = Duration(hours: 6);
const int kingAiBackgroundResearchMaxResults = 2;

class KingAiMaintenanceEvidence {
  const KingAiMaintenanceEvidence({
    required this.enabled,
    required this.networkAvailable,
    required this.batteryNotLow,
    required this.userPaused,
    this.domesticSamples = 0,
    this.globalSamples = 0,
    this.successfulConnections = 0,
    this.failedConnections = 0,
    this.reproducibleIssue = false,
    this.rollbackSnapshotAvailable = false,
    this.candidatePrepared = false,
    this.ciPassed = false,
    this.releaseValidated = false,
    this.ownerAuthenticated = false,
    this.ownerCommandAuthorizedForCandidate = false,
    this.releaseAuthorized = false,
  });

  final bool enabled;
  final bool networkAvailable;
  final bool batteryNotLow;
  final bool userPaused;
  final int domesticSamples;
  final int globalSamples;
  final int successfulConnections;
  final int failedConnections;
  final bool reproducibleIssue;
  final bool rollbackSnapshotAvailable;
  final bool candidatePrepared;
  final bool ciPassed;
  final bool releaseValidated;
  final bool ownerAuthenticated;
  /// Short-lived, explicit owner command scoped to this exact candidate.
  final bool ownerCommandAuthorizedForCandidate;
  /// Separate owner authorization is required to publish a release.
  final bool releaseAuthorized;

  int get boundedNetworkSamples =>
      domesticSamples.clamp(0, 100000).toInt() +
      globalSamples.clamp(0, 100000).toInt();

  int get boundedConnectionSamples =>
      successfulConnections.clamp(0, 100000).toInt() +
      failedConnections.clamp(0, 100000).toInt();
}

class KingAiMaintenancePlan {
  const KingAiMaintenancePlan({
    required this.runPassiveCycle,
    required this.mayTuneRuntime,
    required this.mayPrepareCodeCandidate,
    required this.mayApplySourceChanges,
    required this.mayPublishRelease,
    required this.needsMoreEvidence,
  });

  final bool runPassiveCycle;
  final bool mayTuneRuntime;
  final bool mayPrepareCodeCandidate;
  final bool mayApplySourceChanges;
  final bool mayPublishRelease;
  final bool needsMoreEvidence;
}

/// Decides what the autonomous supervisor may do from measured evidence.
///
/// Preparing a candidate is not the same as applying it: source writes require
/// a live owner session and green CI. A release additionally needs explicit
/// release validation. No model-generated confidence score can bypass gates.
KingAiMaintenancePlan evaluateKingAiMaintenance(
  KingAiMaintenanceEvidence evidence,
) {
  final runPassive = evidence.enabled && kingAiMayRunInBackground(
    networkAvailable: evidence.networkAvailable,
    batteryNotLow: evidence.batteryNotLow,
    userPaused: evidence.userPaused,
  );
  final enoughNetworkEvidence =
      evidence.domesticSamples.clamp(0, 100000).toInt() >= 2 &&
      evidence.globalSamples.clamp(0, 100000).toInt() >= 2;
  final enoughCandidateNetworkEvidence =
      evidence.domesticSamples.clamp(0, 100000).toInt() >= 4 &&
      evidence.globalSamples.clamp(0, 100000).toInt() >= 4;
  final enoughConnectionEvidence =
      evidence.boundedConnectionSamples >= kingAiMinimumSamplesForRuntimeTuning;
  final mayTune = runPassive &&
      enoughNetworkEvidence &&
      enoughConnectionEvidence &&
      evidence.rollbackSnapshotAvailable;
  final mayPrepare = runPassive &&
      enoughCandidateNetworkEvidence &&
      evidence.boundedConnectionSamples >= kingAiMinimumSamplesForCodeCandidate &&
      evidence.reproducibleIssue;
  final mayApply = evidence.candidatePrepared &&
      evidence.ownerAuthenticated &&
      evidence.ownerCommandAuthorizedForCandidate &&
      evidence.ciPassed;
  final mayPublish = mayApply &&
      evidence.releaseValidated &&
      evidence.releaseAuthorized;

  return KingAiMaintenancePlan(
    runPassiveCycle: runPassive,
    mayTuneRuntime: mayTune,
    mayPrepareCodeCandidate: mayPrepare,
    mayApplySourceChanges: mayApply,
    mayPublishRelease: mayPublish,
    needsMoreEvidence: runPassive &&
        (!enoughNetworkEvidence ||
         evidence.boundedConnectionSamples < kingAiMinimumSamplesForRuntimeTuning),
  );
}
