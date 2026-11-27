import 'dart:async';

typedef ScanMaintenanceErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Runs independent background scanners in a single, fair sequence.
///
/// The scheduler does not promise execution while Android has suspended or
/// killed the app process. Each scanner remains responsible for its own
/// persisted cadence, network-mode isolation, and transactional result writes.
class KingScanMaintenanceScheduler {
  KingScanMaintenanceScheduler({
    required this.shouldRun,
    required this.runDns,
    required this.runIp,
    this.onError,
    this.interval = const Duration(minutes: 15),
  }) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval');
    }
  }

  final bool Function() shouldRun;
  final Future<void> Function() runDns;
  final Future<void> Function() runIp;
  final ScanMaintenanceErrorHandler? onError;
  final Duration interval;

  Timer? _timer;
  Future<void>? _flight;
  int _generation = 0;
  bool _disposed = false;

  bool get isRunning => _flight != null;
  bool get isScheduled => _timer?.isActive ?? false;

  void start({bool runImmediately = true}) {
    if (_disposed) {
      throw StateError('Scan maintenance scheduler has been disposed');
    }
    _timer ??= Timer.periodic(interval, (_) {
      unawaited(runOnce());
    });
    if (runImmediately) unawaited(runOnce());
  }

  /// Coalesces overlapping requests and always runs DNS before IP.
  Future<void> runOnce() {
    if (_disposed || !shouldRun()) return Future<void>.value();
    final pending = _flight;
    if (pending != null) return pending;

    final generation = ++_generation;
    late final Future<void> tracked;
    tracked = _run(generation).whenComplete(() {
      if (identical(_flight, tracked)) _flight = null;
    });
    _flight = tracked;
    return tracked;
  }

  Future<void> _run(int generation) async {
    try {
      await runDns();
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    }

    if (!_mayContinue(generation)) return;

    try {
      await runIp();
    } catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  bool _mayContinue(int generation) {
    if (_disposed || generation != _generation) return false;
    try {
      return shouldRun();
    } catch (error, stackTrace) {
      _report(error, stackTrace);
      return false;
    }
  }

  void _report(Object error, StackTrace stackTrace) {
    try {
      onError?.call(error, stackTrace);
    } catch (_) {
      // An observer must never break scanner serialization or cleanup.
    }
  }

  /// Stops future ticks and prevents an in-flight DNS stage from starting IP.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _generation++;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
  }
}
