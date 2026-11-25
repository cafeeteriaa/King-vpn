/// Retry scheduling for a failover deferred by another active operation.
///
/// The retry count is not a retry ceiling. It saturates only the backoff stage,
/// so recovery continues indefinitely while the user still wants the VPN.
int nextFailoverRetryStage(int currentStage) {
  if (currentStage < 0) return 1;
  return currentStage >= 4 ? 4 : currentStage + 1;
}

/// Bounded exponential delay: 10s, 20s, 40s, then 60s for all later retries.
Duration failoverBusyRetryDelay(int stage) {
  final normalized = stage < 1 ? 1 : (stage > 4 ? 4 : stage);
  switch (normalized) {
    case 1:
      return const Duration(seconds: 10);
    case 2:
      return const Duration(seconds: 20);
    case 3:
      return const Duration(seconds: 40);
    default:
      return const Duration(seconds: 60);
  }
}

/// Cooldown used by the failover loop breaker before recovery resumes.
const Duration failoverLoopCooldown = Duration(minutes: 3);
