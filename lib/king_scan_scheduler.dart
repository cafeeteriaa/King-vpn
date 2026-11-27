/// Serial, cancellation-aware orchestration for background scanner phases.
typedef KingScanGate = bool Function();
typedef KingScanTask = Future<void> Function();

class KingScanScheduler {
  bool _running = false;
  bool _rerunRequested = false;

  bool get isRunning => _running;

  /// Runs DNS before IP. Overlapping timer requests coalesce into one follow-up
  /// cycle instead of creating parallel scanner workers.
  Future<void> requestCycle({
    required KingScanGate canRun,
    required KingScanTask runDns,
    required KingScanTask runIp,
  }) async {
    if (_running) {
      _rerunRequested = true;
      return;
    }
    _running = true;
    try {
      do {
        _rerunRequested = false;
        if (!canRun()) return;
        await runDns();
        if (!canRun()) return;
        await runIp();
      } while (_rerunRequested && canRun());
    } finally {
      _running = false;
    }
  }
}
