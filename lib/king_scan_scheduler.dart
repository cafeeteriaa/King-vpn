import 'dart:async';

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

/// National-mode-only scan phases. Global scanning keeps its existing path.
enum KingNationalScanPhase {
  networkDiagnosis,
  dnsDiscovery,
  configuredEndpointDiscovery,
  configuredRangeDiscovery,
}

enum KingNationalScanStatus { completed, failed, cancelled, skipped }

typedef KingNationalScanGate = bool Function();
typedef KingNationalScanAction = Future<void> Function();

class KingNationalScanPhaseResult {
  const KingNationalScanPhaseResult({
    required this.cycle,
    required this.phase,
    required this.status,
    required this.elapsed,
    this.error,
  });

  final int cycle;
  final KingNationalScanPhase phase;
  final KingNationalScanStatus status;
  final Duration elapsed;
  final String? error;
}

class KingNationalScanReport {
  const KingNationalScanReport({
    required this.startedAt,
    required this.finishedAt,
    required this.cyclesCompleted,
    required this.results,
  });

  final DateTime startedAt;
  final DateTime finishedAt;
  final int cyclesCompleted;
  final List<KingNationalScanPhaseResult> results;

  bool get cancelled =>
      results.any((r) => r.status == KingNationalScanStatus.cancelled);
  bool get hasFailures =>
      results.any((r) => r.status == KingNationalScanStatus.failed);
  bool get completed =>
      cyclesCompleted > 0 && !cancelled && !hasFailures;
}

/// One serialized coordinator for national idle discovery. It does not own
/// network probes: existing DNS, configured-endpoint and Rust/Dart range
/// scanners are injected, preserving their established validation and stores.
class KingNationalScannerEngine {
  Future<KingNationalScanReport>? _active;
  bool _rerunRequested = false;

  bool get isRunning => _active != null;

  Future<KingNationalScanReport> runDiscoveryCycle({
    required KingNationalScanGate isNationalMode,
    required KingNationalScanGate canRun,
    required KingNationalScanGate shouldStop,
    required KingNationalScanAction diagnoseNetwork,
    required KingNationalScanAction scanDns,
    required KingNationalScanAction scanConfiguredEndpoints,
    required KingNationalScanAction scanConfiguredRanges,
  }) {
    final active = _active;
    if (active != null) {
      _rerunRequested = true;
      return active;
    }

    final completer = Completer<KingNationalScanReport>();
    _active = completer.future;
    unawaited(_drain(
      completer,
      isNationalMode: isNationalMode,
      canRun: canRun,
      shouldStop: shouldStop,
      diagnoseNetwork: diagnoseNetwork,
      scanDns: scanDns,
      scanConfiguredEndpoints: scanConfiguredEndpoints,
      scanConfiguredRanges: scanConfiguredRanges,
    ));
    return completer.future;
  }

  Future<void> _drain(
    Completer<KingNationalScanReport> completer, {
    required KingNationalScanGate isNationalMode,
    required KingNationalScanGate canRun,
    required KingNationalScanGate shouldStop,
    required KingNationalScanAction diagnoseNetwork,
    required KingNationalScanAction scanDns,
    required KingNationalScanAction scanConfiguredEndpoints,
    required KingNationalScanAction scanConfiguredRanges,
  }) async {
    final startedAt = DateTime.now();
    final results = <KingNationalScanPhaseResult>[];
    var cycles = 0;
    try {
      do {
        _rerunRequested = false;
        if (!isNationalMode() || !canRun() || shouldStop()) {
          if (cycles == 0) {
            results.add(KingNationalScanPhaseResult(
              cycle: 1,
              phase: KingNationalScanPhase.networkDiagnosis,
              status: KingNationalScanStatus.skipped,
              elapsed: Duration.zero,
            ));
          }
          break;
        }
        cycles++;
        await _runPhase(results, cycle: cycles,
            phase: KingNationalScanPhase.networkDiagnosis,
            action: diagnoseNetwork, isNationalMode: isNationalMode,
            canRun: canRun, shouldStop: shouldStop);
        await _runPhase(results, cycle: cycles,
            phase: KingNationalScanPhase.dnsDiscovery,
            action: scanDns, isNationalMode: isNationalMode,
            canRun: canRun, shouldStop: shouldStop);
        await _runPhase(results, cycle: cycles,
            phase: KingNationalScanPhase.configuredEndpointDiscovery,
            action: scanConfiguredEndpoints, isNationalMode: isNationalMode,
            canRun: canRun, shouldStop: shouldStop);
        await _runPhase(results, cycle: cycles,
            phase: KingNationalScanPhase.configuredRangeDiscovery,
            action: scanConfiguredRanges, isNationalMode: isNationalMode,
            canRun: canRun, shouldStop: shouldStop);
      } while (_rerunRequested &&
          isNationalMode() &&
          canRun() &&
          !shouldStop());

      completer.complete(KingNationalScanReport(
        startedAt: startedAt,
        finishedAt: DateTime.now(),
        cyclesCompleted: cycles,
        results: List<KingNationalScanPhaseResult>.unmodifiable(results),
      ));
    } catch (error, stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    } finally {
      _rerunRequested = false;
      _active = null;
    }
  }

  Future<void> _runPhase(
    List<KingNationalScanPhaseResult> results, {
    required int cycle,
    required KingNationalScanPhase phase,
    required KingNationalScanAction action,
    required KingNationalScanGate isNationalMode,
    required KingNationalScanGate canRun,
    required KingNationalScanGate shouldStop,
  }) async {
    if (!isNationalMode() || !canRun() || shouldStop()) {
      results.add(KingNationalScanPhaseResult(
        cycle: cycle,
        phase: phase,
        status: KingNationalScanStatus.cancelled,
        elapsed: Duration.zero,
      ));
      return;
    }
    final watch = Stopwatch()..start();
    var status = KingNationalScanStatus.completed;
    String? errorText;
    try {
      await action();
    } catch (error) {
      status = KingNationalScanStatus.failed;
      errorText = error.runtimeType.toString();
    } finally {
      watch.stop();
    }
    if (!isNationalMode() || !canRun() || shouldStop()) {
      status = KingNationalScanStatus.cancelled;
    }
    results.add(KingNationalScanPhaseResult(
      cycle: cycle,
      phase: phase,
      status: status,
      elapsed: watch.elapsed,
      error: errorText,
    ));
  }
}

/// Shared single-flight coordinator used by the national idle scanner.
final KingNationalScannerEngine kingNationalScanner =
    KingNationalScannerEngine();
