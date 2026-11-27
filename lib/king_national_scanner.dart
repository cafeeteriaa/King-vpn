import 'dart:async';

/// The National Net scanner is intentionally separate from the global scanner.
/// It coordinates discovery phases; connection-time config adaptation and
/// tunnel verification remain owned by the existing national connect ladder.
enum KingNationalScanPhase {
  networkDiagnosis,
  dnsDiscovery,
  configuredEndpointDiscovery,
  configuredRangeDiscovery,
}

enum KingNationalScanStatus { completed, failed, cancelled, skipped }

typedef KingNationalScanGate = bool Function();
typedef KingNationalScanAction = Future<void> Function();
typedef KingNationalScanObserver = void Function(
  KingNationalScanPhase phase,
  KingNationalScanStatus status,
);

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

  /// Error text is diagnostic only; callers must not treat a failed phase as
  /// evidence that a target or a tunnel is healthy.
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
      results.any((result) => result.status == KingNationalScanStatus.cancelled);

  bool get hasFailures =>
      results.any((result) => result.status == KingNationalScanStatus.failed);

  bool get completed =>
      cyclesCompleted > 0 && !cancelled && !hasFailures;
}

/// Serial, national-mode-only discovery coordinator.
///
/// The engine deliberately receives concrete scanner callbacks from the app.
/// This keeps DNS, endpoint and IP implementations in their existing owners,
/// while providing one cancellation-aware execution order and one lock.
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
    KingNationalScanObserver? onPhase,
  }) {
    final active = _active;
    if (active != null) {
      // Timer ticks that arrive during a scan request exactly one sequential
      // follow-up; they never create parallel DNS/IP workers.
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
      onPhase: onPhase,
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
    KingNationalScanObserver? onPhase,
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
        await _runPhase(
          results,
          cycle: cycles,
          phase: KingNationalScanPhase.networkDiagnosis,
          action: diagnoseNetwork,
          isNationalMode: isNationalMode,
          canRun: canRun,
          shouldStop: shouldStop,
          onPhase: onPhase,
        );
        await _runPhase(
          results,
          cycle: cycles,
          phase: KingNationalScanPhase.dnsDiscovery,
          action: scanDns,
          isNationalMode: isNationalMode,
          canRun: canRun,
          shouldStop: shouldStop,
          onPhase: onPhase,
        );
        await _runPhase(
          results,
          cycle: cycles,
          phase: KingNationalScanPhase.configuredEndpointDiscovery,
          action: scanConfiguredEndpoints,
          isNationalMode: isNationalMode,
          canRun: canRun,
          shouldStop: shouldStop,
          onPhase: onPhase,
        );
        await _runPhase(
          results,
          cycle: cycles,
          phase: KingNationalScanPhase.configuredRangeDiscovery,
          action: scanConfiguredRanges,
          isNationalMode: isNationalMode,
          canRun: canRun,
          shouldStop: shouldStop,
          onPhase: onPhase,
        );
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
    KingNationalScanObserver? onPhase,
  }) async {
    if (!isNationalMode() || !canRun() || shouldStop()) {
      results.add(KingNationalScanPhaseResult(
        cycle: cycle,
        phase: phase,
        status: KingNationalScanStatus.cancelled,
        elapsed: Duration.zero,
      ));
      onPhase?.call(phase, KingNationalScanStatus.cancelled);
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

    // A mode switch or connection request during an awaited phase invalidates
    // the remainder of this cycle. Completed partial work is not re-labelled
    // as a complete scan.
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
    onPhase?.call(phase, status);
  }
}
