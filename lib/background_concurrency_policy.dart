/// Computes the number of background core probes without allowing a hot
/// application process to compete aggressively with the active VPN data plane.
///
/// The requested setting is preserved when the process is cool. CPU pressure
/// temporarily lowers concurrency and never changes the user's saved setting.
int adaptiveBackgroundConcurrency({
  required int requestedWorkers,
  required int cpuHeat,
  required bool nationalMode,
  int nationalWorkers = 3,
  int maxWorkers = 32,
}) {
  final requested = nationalMode ? nationalWorkers : requestedWorkers;
  final safeMaximum = maxWorkers < 1 ? 1 : maxWorkers;
  final normalized = requested.clamp(1, safeMaximum);
  if (cpuHeat >= 2) return 1;
  if (cpuHeat == 1) return normalized.clamp(1, 2);
  return normalized;
}
