import 'dart:async';
import 'dart:collection';

/// KING Fusion Engine foundation.
///
/// This module defines an honest adapter boundary for multi-engine routing.
/// It does not claim that an engine is bundled merely because it has a descriptor.
/// Only adapters explicitly injected by the application can be executed.
enum KingEngineFamily { xray, singBox, wireGuard, amneziaWG, psiphon, tor, custom }

enum KingEngineAvailability {
  /// A native adapter is installed and supplied to the fusion engine.
  integrated,
  /// The engine is known, but its native runtime/adapter is not installed.
  adapterRequired,
}

class KingEngineDescriptor {
  final String id;
  final String title;
  final KingEngineFamily family;
  final KingEngineAvailability availability;
  final Set<String> supportedTransports;
  final bool supportsMultiHop;

  const KingEngineDescriptor({
    required this.id,
    required this.title,
    required this.family,
    required this.availability,
    this.supportedTransports = const <String>{},
    this.supportsMultiHop = false,
  });
}

class KingFusionHop {
  /// Stable adapter id. Configuration is intentionally opaque to this layer.
  final String engineId;
  final String configuration;
  /// Optional explicit transport requirement; never inferred from opaque config.
  final String? requiredTransport;

  const KingFusionHop({
    required this.engineId,
    required this.configuration,
    this.requiredTransport,
  });
}

class KingFusionPlan {
  final List<KingFusionHop> hops;
  /// Require a real data-plane probe after every native hop has started.
  final bool requireTrafficVerification;

  KingFusionPlan(
    Iterable<KingFusionHop> hops, {
    this.requireTrafficVerification = false,
  }) : hops = List<KingFusionHop>.unmodifiable(hops);
}

/// Verifies traffic through the resulting route, not merely native start state.
abstract interface class KingFusionTrafficVerifier {
  Future<bool> verify(KingFusionPlan plan);
}

/// Optional cancellation contract for verifiers that own sockets, probes or
/// other resources. Implementations should make cancel idempotent.
abstract interface class KingFusionCancellableTrafficVerifier
    implements KingFusionTrafficVerifier {
  Future<void> cancel();
}

class KingEngineStartResult {
  final bool connected;
  /// Opaque native handle; never serialize or log it.
  final Object? handle;
  final String? failureCode;

  const KingEngineStartResult.connected([this.handle])
      : connected = true,
        failureCode = null;

  const KingEngineStartResult.failed(this.failureCode)
      : connected = false,
        handle = null;
}

/// Optional cancellation contract for adapters whose native start can block.
/// cancelPendingStart() must be idempotent and cause the outstanding start()
/// future to settle; a successful late start is still stopped by the engine.
abstract interface class KingFusionCancellableEngineAdapter
    implements KingEngineAdapter {
  Future<void> cancelPendingStart();
}

abstract interface class KingEngineAdapter {
  KingEngineDescriptor get descriptor;

  /// Start this hop over the preceding hop, when supplied.
  Future<KingEngineStartResult> start({
    required String configuration,
    Object? upstreamHandle,
  });

  /// Must tolerate retry after timeout or an earlier failed cleanup attempt.
  Future<void> stop(Object? handle);

  /// Explicit compatibility contract; false by default in adapters.
  ///
  /// This is called during preflight and must be side-effect-free. Exceptions
  /// are converted into a stable validation failure before any adapter starts.
  bool canChainTo(KingEngineAdapter next);
}

enum KingFusionState { idle, starting, connected, stopping, failed }

enum KingFusionEventType {
  stateChanged,
  connectStarted,
  validationRejected,
  hopStarting,
  hopStarted,
  hopFailed,
  verificationStarted,
  verificationPassed,
  verificationFailed,
  rollbackStarted,
  hopStopped,
  cleanupFailed,
  disconnectRequested,
  operationCancelled,
  disconnectCompleted,
}

/// Safe lifecycle telemetry. Never contains configuration text or native handles.
class KingFusionEvent {
  final int sequence;
  final DateTime timestamp;
  final KingFusionEventType type;
  final KingFusionState state;
  final String? engineId;
  final String? failureCode;
  final int activeHopCount;

  const KingFusionEvent({
    required this.sequence,
    required this.timestamp,
    required this.type,
    required this.state,
    required this.engineId,
    required this.failureCode,
    required this.activeHopCount,
  });
}

typedef KingFusionEventListener = void Function(KingFusionEvent event);

/// Immutable, secret-free view of the coordinator's current lifecycle.
class KingFusionSnapshot {
  final KingFusionState state;
  final bool isBusy;
  final bool disconnectRequested;
  final List<String> activeEngineIds;
  final List<String> cleanupPendingEngineIds;
  /// Bounded, immutable lifecycle history retained by the coordinator.
  final List<KingFusionEvent> recentEvents;
  final int eventSequence;

  KingFusionSnapshot({
    required this.state,
    required this.isBusy,
    required this.disconnectRequested,
    required Iterable<String> activeEngineIds,
    required Iterable<String> cleanupPendingEngineIds,
    required Iterable<KingFusionEvent> recentEvents,
    required this.eventSequence,
  })  : activeEngineIds = List<String>.unmodifiable(activeEngineIds),
        cleanupPendingEngineIds =
            List<String>.unmodifiable(cleanupPendingEngineIds),
        recentEvents = List<KingFusionEvent>.unmodifiable(recentEvents);
}

/// Adapter-provided failure strings cross a public API boundary. Keep only
/// stable machine-readable codes; never let arbitrary adapter text (which may
/// accidentally contain configuration fragments or credentials) escape.
bool _isSafeEngineIdentifier(String value) {
  if (value.isEmpty || value.length > 64) return false;
  for (final unit in value.codeUnits) {
    final upper = unit >= 65 && unit <= 90;
    final lower = unit >= 97 && unit <= 122;
    final digit = unit >= 48 && unit <= 57;
    if (!upper && !lower && !digit && unit != 95 && unit != 45 && unit != 46) {
      return false;
    }
  }
  return true;
}

String? _safeEngineIdentifier(String? value) {
  if (value == null) return null;
  final id = value.trim();
  return _isSafeEngineIdentifier(id) ? id : null;
}

String _safeAdapterFailureCode(String? value) {
  if (value == null) return 'E-FUSION-START';
  final code = value.trim();
  if (code.isEmpty || code.length > 64) {
    return 'E-FUSION-ADAPTER-START';
  }
  final first = code.codeUnitAt(0);
  if (first < 65 || first > 90) return 'E-FUSION-ADAPTER-START';
  for (final unit in code.codeUnits.skip(1)) {
    final isUpper = unit >= 65 && unit <= 90;
    final isDigit = unit >= 48 && unit <= 57;
    if (!isUpper && !isDigit && unit != 95 && unit != 45) {
      return 'E-FUSION-ADAPTER-START';
    }
  }
  return code;
}

class _KingFusionVerificationTimeout implements Exception {}

class _KingFusionCancelled implements Exception {}

class KingFusionResult {
  /// All adapters accepted their start calls; this is not end-to-end traffic proof.
  final bool connected;
  /// True only when the plan requested and passed a traffic verifier.
  final bool trafficVerified;
  final String? failedEngineId;
  final String? failureCode;
  final int startedHops;
  /// Engines whose native stop operation failed and still need cleanup.
  final List<String> cleanupFailedEngineIds;

  const KingFusionResult._({
    required this.connected,
    required this.trafficVerified,
    required this.failedEngineId,
    required this.failureCode,
    required this.startedHops,
    this.cleanupFailedEngineIds = const <String>[],
  });

  const KingFusionResult.success(
    int startedHops, {
    bool trafficVerified = false,
  }) : this._(
          connected: true,
          trafficVerified: trafficVerified,
          failedEngineId: null,
          failureCode: null,
          startedHops: startedHops,
        );

  KingFusionResult.failure({
    required String? failedEngineId,
    required String? failureCode,
    required int startedHops,
    Iterable<String> cleanupFailedEngineIds = const <String>[],
  }) : this._(
          connected: false,
          trafficVerified: false,
          failedEngineId: failedEngineId,
          failureCode: failureCode,
          startedHops: startedHops,
          cleanupFailedEngineIds:
              List<String>.unmodifiable(cleanupFailedEngineIds),
        );
}

/// Coordinates only adapters that the host application has actually installed.
///
/// Multi-hop is opt-in at every edge. A missing adapter, duplicate hop, or
/// unsupported chain is rejected before any native engine is started. If a
/// later hop fails, previously started hops are stopped in reverse order.
class KingFusionEngine {
  final Map<String, KingEngineAdapter> _adapters;
  late final Map<String, KingEngineDescriptor> _descriptors;
  late final Map<KingEngineAdapter, String> _idByAdapter;
  final KingFusionTrafficVerifier? _trafficVerifier;
  final Duration trafficVerificationTimeout;
  /// Upper bound for each native stop attempt; timed-out handles remain tracked.
  final Duration nativeStopTimeout;
  final KingFusionEventListener? _eventListener;
  /// Maximum number of secret-free lifecycle events retained for diagnostics.
  final int eventHistoryLimit;
  final List<KingFusionEvent> _eventHistory = <KingFusionEvent>[];
  int _eventSequence = 0;
  final List<({KingEngineAdapter adapter, Object? handle})> _active = [];
  // Future.timeout does not cancel a native stop. Keep the in-flight future
  // so repeated disconnects cannot issue overlapping stop calls.
  final Map<KingEngineAdapter, Future<void>> _stopOperations =
      HashMap<KingEngineAdapter, Future<void>>.identity();
  KingFusionCancellableTrafficVerifier? _activeVerifier;
  KingFusionCancellableEngineAdapter? _startingAdapter;
  Completer<void>? _disconnectSignal;

  KingFusionState _state = KingFusionState.idle;
  KingFusionState get state => _state;
  bool _busy = false;
  bool _disconnectRequested = false;
  Completer<void>? _operationDone;

  KingFusionEngine(
    Iterable<KingEngineAdapter> adapters, {
    KingFusionTrafficVerifier? trafficVerifier,
    this.trafficVerificationTimeout = const Duration(seconds: 12),
    this.nativeStopTimeout = const Duration(seconds: 8),
    this.eventHistoryLimit = 256,
    KingFusionEventListener? onEvent,
  })  : _adapters = _indexAdapters(adapters),
        _trafficVerifier = trafficVerifier,
        _eventListener = onEvent {
    final descriptorSnapshots = <String, KingEngineDescriptor>{};
    final adapterIds = HashMap<KingEngineAdapter, String>.identity();
    for (final entry in _adapters.entries) {
      final source = entry.value.descriptor;
      descriptorSnapshots[entry.key] = KingEngineDescriptor(
        id: entry.key,
        title: source.title,
        family: source.family,
        availability: source.availability,
        supportedTransports: Set<String>.unmodifiable(
          source.supportedTransports.map((transport) => transport.trim().toLowerCase()),
        ),
        supportsMultiHop: source.supportsMultiHop,
      );
      adapterIds[entry.value] = entry.key;
    }
    _descriptors = Map<String, KingEngineDescriptor>.unmodifiable(
      descriptorSnapshots,
    );
    _idByAdapter = adapterIds;
    if (eventHistoryLimit <= 0) {
      throw ArgumentError.value(
        eventHistoryLimit,
        'eventHistoryLimit',
        'Must be positive',
      );
    }
    if (nativeStopTimeout <= Duration.zero) {
      throw ArgumentError.value(
        nativeStopTimeout,
        'nativeStopTimeout',
        'Must be positive',
      );
    }
    if (trafficVerificationTimeout <= Duration.zero) {
      throw ArgumentError.value(
        trafficVerificationTimeout,
        'trafficVerificationTimeout',
        'Must be positive',
      );
    }
  }

  static Map<String, KingEngineAdapter> _indexAdapters(
    Iterable<KingEngineAdapter> adapters,
  ) {
    final result = <String, KingEngineAdapter>{};
    for (final adapter in adapters) {
      final id = adapter.descriptor.id.trim();
      if (id.isEmpty) {
        throw ArgumentError('Engine adapter id must not be empty');
      }
      if (!_isSafeEngineIdentifier(id)) {
        throw ArgumentError('Engine adapter id contains unsupported characters');
      }
      if (result.containsKey(id)) {
        throw ArgumentError('Duplicate engine adapter: $id');
      }
      result[id] = adapter;
    }
    return Map<String, KingEngineAdapter>.unmodifiable(result);
  }

  List<KingEngineDescriptor> get availableEngines =>
      List<KingEngineDescriptor>.unmodifiable(_descriptors.values);

  /// Adapter IDs still tracked because native cleanup has not succeeded.
  List<String> get cleanupPendingEngineIds {
    // Active handles are not cleanup failures while the route is healthy or
    // while a normal disconnect is still in progress. Expose only retained
    // handles after rollback has completed with a failure.
    if (_state != KingFusionState.failed) return const <String>[];
    return List<String>.unmodifiable(
      _active.map((item) => _idByAdapter[item.adapter]!),
    );
  }

  bool get isBusy => _busy;

  /// Immutable copy of the most recent lifecycle events, even without a listener.
  List<KingFusionEvent> get recentEvents =>
      List<KingFusionEvent>.unmodifiable(_eventHistory);

  KingFusionSnapshot get snapshot => KingFusionSnapshot(
        state: _state,
        isBusy: _busy,
        // Include the published shared operation so observers and snapshots
        // see the disconnect transition before native cleanup begins.
        disconnectRequested: _disconnectRequested || _disconnectOperation != null,
        activeEngineIds: _active.map((item) => _idByAdapter[item.adapter]!),
        cleanupPendingEngineIds: cleanupPendingEngineIds,
        recentEvents: _eventHistory,
        eventSequence: _eventSequence,
      );

  void _setState(KingFusionState next, {String? engineId, String? failureCode}) {
    if (_state == next) return;
    _state = next;
    _emit(
      KingFusionEventType.stateChanged,
      engineId: engineId,
      failureCode: failureCode,
    );
  }

  void _emit(
    KingFusionEventType type, {
    String? engineId,
    String? failureCode,
  }) {
    // Sequence numbers describe coordinator activity, not observer delivery.
    // Keep snapshots meaningful even when telemetry is not configured.
    final sequence = ++_eventSequence;
    final event = KingFusionEvent(
      sequence: sequence,
      timestamp: DateTime.now(),
      type: type,
      state: _state,
      engineId: _safeEngineIdentifier(engineId),
      failureCode: failureCode == null
          ? null
          : _safeAdapterFailureCode(failureCode),
      activeHopCount: _active.length,
    );
    _eventHistory.add(event);
    if (_eventHistory.length > eventHistoryLimit) {
      _eventHistory.removeRange(0, _eventHistory.length - eventHistoryLimit);
    }
    final listener = _eventListener;
    if (listener == null) return;
    try {
      listener(event);
    } catch (_) {
      // Telemetry is observational and must never alter connection behavior.
    }
  }

  void _finishPreflight() {
    _busy = false;
    _disconnectSignal = null;
    _operationDone?.complete();
    _operationDone = null;
  }

  Future<KingFusionResult> connect(KingFusionPlan plan) async {
    // disconnect() publishes its shared future before observer callbacks run.
    // Reject a reentrant connect from disconnectRequested rather than allowing
    // a new native start to race the teardown that is about to begin.
    if (_disconnectOperation != null || _disconnectRequested) {
      return KingFusionResult.failure(
        failedEngineId: null,
        failureCode: 'E-FUSION-DISCONNECT-PENDING',
        startedHops: 0,
      );
    }
    if (_busy) {
      return KingFusionResult.failure(
        failedEngineId: null,
        failureCode: 'E-FUSION-BUSY',
        startedHops: 0,
      );
    }
    if (state == KingFusionState.connected) {
      return KingFusionResult.failure(
        failedEngineId: null,
        failureCode: 'E-FUSION-ALREADY-ACTIVE',
        startedHops: 0,
      );
    }
    if (_active.isNotEmpty) {
      return KingFusionResult.failure(
        failedEngineId: null,
        failureCode: 'E-FUSION-CLEANUP-PENDING',
        startedHops: 0,
      );
    }

    // Reserve the operation slot before preflight. Validation emits
    // synchronous observer events and adapter compatibility callbacks; neither
    // may re-enter connect() and start a second plan before this one is settled.
    _busy = true;
    _disconnectRequested = false;
    _operationDone = Completer<void>();
    _disconnectSignal = Completer<void>();

    (String, String)? validationError;
    try {
      validationError = _validate(plan);
    } catch (_) {
      _emit(
        KingFusionEventType.validationRejected,
        failureCode: 'E-FUSION-VALIDATION-EXCEPTION',
      );
      _setState(KingFusionState.failed);
      _finishPreflight();
      return KingFusionResult.failure(
        failedEngineId: null,
        failureCode: 'E-FUSION-VALIDATION-EXCEPTION',
        startedHops: 0,
      );
    }
    if (validationError != null) {
      _emit(
        KingFusionEventType.validationRejected,
        engineId: validationError.$1,
        failureCode: validationError.$2,
      );
      _setState(KingFusionState.failed);
      _finishPreflight();
      return KingFusionResult.failure(
        failedEngineId: validationError.$1,
        failureCode: validationError.$2,
        startedHops: 0,
      );
    }

    _setState(KingFusionState.starting);
    String? currentEngineId;
    Object? upstreamHandle;
    var verificationInProgress = false;
    try {
      for (final hop in plan.hops) {
        if (_disconnectRequested) {
          final startedCount = _active.length;
          final cleanupFailures = await _rollback();
          _setState(KingFusionState.failed);
          return KingFusionResult.failure(
            failedEngineId: null,
            failureCode: 'E-FUSION-CANCELLED',
            startedHops: startedCount,
            cleanupFailedEngineIds: cleanupFailures,
          );
        }
        currentEngineId = hop.engineId.trim();
        final adapter = _adapters[currentEngineId]!;
        _emit(KingFusionEventType.hopStarting, engineId: currentEngineId);
        // A synchronous lifecycle observer may request disconnect here.
        // Re-check before crossing the native boundary to avoid starting a
        // hop after cancellation has already been committed.
        if (_disconnectRequested) {
          final startedCount = _active.length;
          final cleanupFailures = await _rollback();
          _setState(KingFusionState.failed);
          return KingFusionResult.failure(
            failedEngineId: currentEngineId,
            failureCode: 'E-FUSION-CANCELLED',
            startedHops: startedCount,
            cleanupFailedEngineIds: cleanupFailures,
          );
        }
        KingEngineStartResult result;
        try {
          if (adapter is KingFusionCancellableEngineAdapter) {
            _startingAdapter = adapter;
          }
          result = await adapter.start(
            configuration: hop.configuration,
            upstreamHandle: upstreamHandle,
          );
        } finally {
          if (identical(_startingAdapter, adapter)) {
            _startingAdapter = null;
          }
        }
        if (!result.connected) {
          _emit(
            KingFusionEventType.hopFailed,
            engineId: currentEngineId,
            failureCode: _safeAdapterFailureCode(result.failureCode),
          );
          if (_disconnectRequested) {
            final startedCount = _active.length;
            final cleanupFailures = await _rollback();
            _setState(KingFusionState.failed);
            return KingFusionResult.failure(
              failedEngineId: currentEngineId,
              failureCode: 'E-FUSION-CANCELLED',
              startedHops: startedCount,
              cleanupFailedEngineIds: cleanupFailures,
            );
          }
          final startedCount = _active.length;
          final cleanupFailures = await _rollback();
          _setState(KingFusionState.failed);
          return KingFusionResult.failure(
            failedEngineId: currentEngineId,
            failureCode: _safeAdapterFailureCode(result.failureCode),
            startedHops: startedCount,
            cleanupFailedEngineIds: cleanupFailures,
          );
        }
        _active.add((adapter: adapter, handle: result.handle));
        _emit(KingFusionEventType.hopStarted, engineId: currentEngineId);
        upstreamHandle = result.handle;
        if (_disconnectRequested) {
          final startedCount = _active.length;
          final cleanupFailures = await _rollback();
          _setState(KingFusionState.failed);
          return KingFusionResult.failure(
            failedEngineId: currentEngineId,
            failureCode: 'E-FUSION-CANCELLED',
            startedHops: startedCount,
            cleanupFailedEngineIds: cleanupFailures,
          );
        }
      }
      if (plan.requireTrafficVerification) {
        verificationInProgress = true;
        _emit(KingFusionEventType.verificationStarted);
        // The event listener is synchronous and may commit disconnect.
        // Do not start a verifier (which may allocate sockets or probes)
        // after cancellation has already been accepted.
        if (_disconnectRequested) {
          final startedCount = _active.length;
          final cleanupFailures = await _rollback();
          _setState(KingFusionState.failed);
          return KingFusionResult.failure(
            failedEngineId: null,
            failureCode: 'E-FUSION-CANCELLED',
            startedHops: startedCount,
            cleanupFailedEngineIds: cleanupFailures,
          );
        }
        final verifier = _trafficVerifier;
        if (verifier == null) {
          final startedCount = _active.length;
          final cleanupFailures = await _rollback();
          _setState(KingFusionState.failed);
          return KingFusionResult.failure(
            failedEngineId: null,
            failureCode: 'E-FUSION-VERIFIER-MISSING',
            startedHops: startedCount,
            cleanupFailedEngineIds: cleanupFailures,
          );
        }
        if (verifier is KingFusionCancellableTrafficVerifier) {
          _activeVerifier = verifier;
        }
        final verified = await Future.any<bool>([
          verifier.verify(plan).timeout(
            trafficVerificationTimeout,
            onTimeout: () => throw _KingFusionVerificationTimeout(),
          ),
          _disconnectSignal!.future.then<bool>(
            (_) => throw _KingFusionCancelled(),
          ),
        ]);
        verificationInProgress = false;
        if (_disconnectRequested) {
          final startedCount = _active.length;
          final cleanupFailures = await _rollback();
          _setState(KingFusionState.failed);
          return KingFusionResult.failure(
            failedEngineId: null,
            failureCode: 'E-FUSION-CANCELLED',
            startedHops: startedCount,
            cleanupFailedEngineIds: cleanupFailures,
          );
        }
        if (!verified) {
          _emit(KingFusionEventType.verificationFailed,
              failureCode: 'E-FUSION-TRAFFIC-UNVERIFIED');
          final startedCount = _active.length;
          final cleanupFailures = await _rollback();
          _setState(KingFusionState.failed);
          return KingFusionResult.failure(
            failedEngineId: null,
            failureCode: 'E-FUSION-TRAFFIC-UNVERIFIED',
            startedHops: startedCount,
            cleanupFailedEngineIds: cleanupFailures,
          );
        }
      }
      _setState(KingFusionState.connected);
      if (plan.requireTrafficVerification) {
        _emit(KingFusionEventType.verificationPassed);
      }
      // A synchronous observer can request disconnect from the final
      // stateChanged/verificationPassed event. Do not report a successful
      // connect after that teardown has already been committed.
      if (_disconnectRequested) {
        final startedCount = _active.length;
        final cleanupFailures = await _rollback();
        _setState(KingFusionState.failed);
        return KingFusionResult.failure(
          failedEngineId: null,
          failureCode: 'E-FUSION-CANCELLED',
          startedHops: startedCount,
          cleanupFailedEngineIds: cleanupFailures,
        );
      }
      return KingFusionResult.success(
        _active.length,
        trafficVerified: plan.requireTrafficVerification,
      );
    } on _KingFusionCancelled {
      _emit(KingFusionEventType.operationCancelled,
          engineId: currentEngineId, failureCode: 'E-FUSION-CANCELLED');
      final startedCount = _active.length;
      final cleanupFailures = await _rollback();
      _setState(KingFusionState.failed);
      return KingFusionResult.failure(
        failedEngineId: currentEngineId,
        failureCode: 'E-FUSION-CANCELLED',
        startedHops: startedCount,
        cleanupFailedEngineIds: cleanupFailures,
      );
    } on _KingFusionVerificationTimeout {
      _emit(KingFusionEventType.verificationFailed,
          failureCode: 'E-FUSION-VERIFY-TIMEOUT');
      final verifier = _activeVerifier;
      if (verifier != null) {
        unawaited(_requestVerifierCancellation(verifier));
      }
      final startedCount = _active.length;
      final cleanupFailures = await _rollback();
      _setState(KingFusionState.failed);
      return KingFusionResult.failure(
        failedEngineId: currentEngineId,
        failureCode: 'E-FUSION-VERIFY-TIMEOUT',
        startedHops: startedCount,
        cleanupFailedEngineIds: cleanupFailures,
      );
    } catch (_) {
      final failureCode = _disconnectRequested
          ? 'E-FUSION-CANCELLED'
          : verificationInProgress
              ? 'E-FUSION-VERIFY-EXCEPTION'
              : 'E-FUSION-EXCEPTION';
      _emit(
        verificationInProgress
            ? KingFusionEventType.verificationFailed
            : KingFusionEventType.hopFailed,
        engineId: verificationInProgress ? null : currentEngineId,
        failureCode: failureCode,
      );
      final startedCount = _active.length;
      final cleanupFailures = await _rollback();
      _setState(KingFusionState.failed);
      return KingFusionResult.failure(
        failedEngineId: currentEngineId,
        failureCode: failureCode,
        startedHops: startedCount,
        cleanupFailedEngineIds: cleanupFailures,
      );
    } finally {
      _busy = false;
      _activeVerifier = null;
      _startingAdapter = null;
      _disconnectSignal = null;
      // Keep the cancellation latch raised until the waiting disconnect()
      // acquires the operation slot; otherwise a new connect could slip into
      // the microtask gap between completing this operation and its waiter.
      _operationDone?.complete();
      _operationDone = null;
    }
  }

  (String, String)? _validate(KingFusionPlan plan) {
    if (plan.hops.isEmpty) return ('', 'E-FUSION-EMPTY-PLAN');
    if (plan.requireTrafficVerification && _trafficVerifier == null) {
      return ('', 'E-FUSION-VERIFIER-MISSING');
    }
    final seen = <String>{};
    final resolved = <KingEngineAdapter>[];
    for (final hop in plan.hops) {
      final id = hop.engineId.trim();
      if (!seen.add(id)) return (id, 'E-FUSION-DUPLICATE-HOP');
      final adapter = _adapters[id];
      if (adapter == null) return (id, 'E-FUSION-ADAPTER-MISSING');
      final descriptor = _descriptors[id]!;
      if (descriptor.availability != KingEngineAvailability.integrated) {
        return (id, 'E-FUSION-ADAPTER-NOT-INTEGRATED');
      }
      if (hop.configuration.trim().isEmpty) {
        return (id, 'E-FUSION-CONFIG-EMPTY');
      }
      final requiredTransport = hop.requiredTransport?.trim().toLowerCase();
      if (requiredTransport != null) {
        if (!_isSafeEngineIdentifier(requiredTransport)) {
          return (id, 'E-FUSION-TRANSPORT-INVALID');
        }
        final supported = descriptor.supportedTransports;
        if (!supported.contains(requiredTransport)) {
          return (id, 'E-FUSION-TRANSPORT-UNSUPPORTED');
        }
      }
      resolved.add(adapter);
    }
    for (var i = 0; i + 1 < resolved.length; i++) {
      final current = resolved[i];
      final next = resolved[i + 1];
      final currentId = _idByAdapter[current]!;
      final currentDescriptor = _descriptors[currentId]!;
      if (!currentDescriptor.supportsMultiHop ||
          !current.canChainTo(next)) {
        return (currentDescriptor.id, 'E-FUSION-CHAIN-UNSUPPORTED');
      }
    }
    return null;
  }

  Future<void>? _disconnectOperation;

  /// Concurrent callers join the same native cleanup operation.
  Future<void> disconnect() {
    final existing = _disconnectOperation;
    if (existing != null) {
      // Do not re-emit disconnectRequested for joiners. An observer may
      // synchronously call disconnect() from that event; emitting it again
      // would recursively re-enter the same observer before unwinding.
      _requestDisconnectCancellation();
      return existing;
    }
    final completer = Completer<void>();
    final operation = completer.future;
    // Publish the shared operation before notifying observers. Reentrant
    // disconnect() calls now join this future instead of starting a second
    // teardown or recursively dispatching disconnectRequested.
    _disconnectOperation = operation;
    _emit(KingFusionEventType.disconnectRequested);
    unawaited(
      _performDisconnect().then<void>(
        (_) {
          if (identical(_disconnectOperation, operation)) {
            _disconnectOperation = null;
          }
          completer.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (identical(_disconnectOperation, operation)) {
            _disconnectOperation = null;
          }
          completer.completeError(error, stackTrace);
        },
      ),
    );
    return operation;
  }

  void _requestDisconnectCancellation() {
    // The first caller owns the cancellation transition. Additional callers
    // join the same disconnect future and must not invoke native cancellation
    // hooks repeatedly while startup or verification is unwinding.
    if (!_busy || _state == KingFusionState.stopping || _disconnectRequested) {
      return;
    }
    _disconnectRequested = true;
    final signal = _disconnectSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
    final verifier = _activeVerifier;
    if (verifier != null) {
      unawaited(_requestVerifierCancellation(verifier));
    }
    final startingAdapter = _startingAdapter;
    if (startingAdapter != null) {
      unawaited(_requestStartCancellation(startingAdapter));
    }
  }

  Future<void> _performDisconnect() async {
    if (_busy) {
      _requestDisconnectCancellation();
      final pending = _operationDone?.future;
      if (pending != null) await pending;
    }
    if (_busy) {
      final pending = _operationDone?.future;
      if (pending != null) await pending;
    }
    _busy = true;
    _disconnectRequested = false;
    _operationDone = Completer<void>();
    _setState(KingFusionState.stopping);
    try {
      await _rollback();
      _setState(_active.isEmpty ? KingFusionState.idle : KingFusionState.failed);
      _emit(
        KingFusionEventType.disconnectCompleted,
        failureCode: _active.isEmpty ? null : 'E-FUSION-CLEANUP-PENDING',
      );
    } finally {
      _busy = false;
      _operationDone?.complete();
      _operationDone = null;
    }
  }

  Future<void> _requestStartCancellation(
    KingFusionCancellableEngineAdapter adapter,
  ) async {
    try {
      await adapter.cancelPendingStart();
    } catch (_) {
      // Adapter start failure will be mapped by connect(); do not lose the
      // disconnect request if the cancellation hook itself fails.
    }
  }

  Future<void> _requestVerifierCancellation(
    KingFusionCancellableTrafficVerifier verifier,
  ) async {
    try {
      await verifier.cancel();
    } catch (_) {
      // The disconnect signal still releases the coordinator; late verifier
      // results are ignored even if the adapter cannot cancel its own work.
    }
  }

  /// Failed or timed-out stops remain tracked so a later disconnect can retry.
  /// Cleanup halts at the first reverse-order failure to keep upstream hops
  /// alive while a downstream hop may still depend on them.
  Future<List<String>> _rollback() async {
    if (_active.isNotEmpty) _emit(KingFusionEventType.rollbackStarted);
    final failed = <({KingEngineAdapter adapter, Object? handle})>[];
    final reverseOrder = _active.reversed.toList(growable: false);
    for (var index = 0; index < reverseOrder.length; index++) {
      final item = reverseOrder[index];
      try {
        var stopOperation = _stopOperations[item.adapter];
        if (stopOperation == null) {
          stopOperation = item.adapter.stop(item.handle);
          _stopOperations[item.adapter] = stopOperation;
          final trackedOperation = stopOperation;
          unawaited(
            trackedOperation.then<void>(
              (_) {
                if (identical(
                  _stopOperations[item.adapter],
                  trackedOperation,
                )) {
                  _stopOperations.remove(item.adapter);
                }
              },
              onError: (Object _, StackTrace __) {
                if (identical(
                  _stopOperations[item.adapter],
                  trackedOperation,
                )) {
                  _stopOperations.remove(item.adapter);
                }
              },
            ),
          );
        }
        await stopOperation.timeout(nativeStopTimeout);
        _emit(KingFusionEventType.hopStopped,
            engineId: _idByAdapter[item.adapter]!);
      } catch (_) {
        // A downstream hop must be stopped before its upstream dependency.
        // Retain this hop and every earlier hop; do not tear down underneath it.
        _emit(KingFusionEventType.cleanupFailed,
            engineId: _idByAdapter[item.adapter]!,
            failureCode: 'E-FUSION-CLEANUP');
        failed.addAll(reverseOrder.skip(index));
        break;
      }
    }
    _active
      ..clear()
      ..addAll(failed.reversed);
    // A fixed-length list is still element-mutable. Results cross the
    // coordinator boundary, so publish a genuinely immutable cleanup report.
    return List<String>.unmodifiable(
      failed.map((item) => _idByAdapter[item.adapter]!),
    );
  }

}
