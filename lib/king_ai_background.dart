part of 'main.dart';

const String _taskName = 'kingAiCiRepair';
const String _uniqueName = 'king-ai-ci-repair-periodic';
const String _initialUniqueName = 'king-ai-ci-repair-initial';
const String _tag = 'king-ai-ci-repair';

const String _researchTaskName = 'kingAiIranNetworkResearch';
const String _researchUniqueName = 'king-ai-iran-network-research-periodic';
const String _researchInitialName = 'king-ai-iran-network-research-initial';
const String _researchTag = 'king-ai-iran-network-research';

const String _auditTaskName = 'kingAiIranNetworkAudit';
const String _auditUniqueName = 'king-ai-iran-network-audit-periodic';
const String _auditInitialName = 'king-ai-iran-network-audit-initial';
const String _auditTag = 'king-ai-iran-network-audit';

const String _nationalScannerTaskName = 'kingNationalNetworkScan';
const String _nationalScannerUniqueName = 'king-national-network-scan-daily';
const String _nationalScannerInitialName = 'king-national-network-scan-initial';
const String _nationalScannerTag = 'king-national-network-scan';
bool _kingBackgroundWorkmanagerInitialized = false;
const String _researchQuery =
    'Iran mobile internet domestic routing national network DNS IPv4 IPv6 '
    'Android VPNService network changes DoH TLS SNI Xray V2Ray sing-box '
    'Cloudflare tunnel DNS security Flutter Dart performance official docs';

/// WorkManager entry point. The model is loaded only from a foreground-verified
/// local file; this worker never downloads the 1.1 GB model in the background.
@pragma('vm:entry-point')
void kingAiBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    ui.DartPluginRegistrant.ensureInitialized();
    if (task == _nationalScannerTaskName) {
      return _runKingNationalScannerBackgroundTask();
    }
    if (task != _taskName &&
        task != _researchTaskName &&
        task != _auditTaskName) return true;

    final ai = KingLocalAi.instance;
    try {
      if (task == _researchTaskName) {
        // Passive, bounded research. Only allowlisted official sources are
        // retained by researchGoogle; this never edits code or needs a token.
        await ai.researchGoogle(
          _researchQuery,
          maxResults: kingAiBackgroundResearchMaxResults,
        )
            .timeout(const Duration(seconds: 55));
        return true;
      }
      if (task == _auditTaskName) {
        // Re-check the persisted owner opt-in inside the worker itself. A
        // scheduled/stale task must never create source proposals after the
        // owner has disabled autonomous maintenance.
        if (!await ai.isBackgroundAutoDiscoveryEnabled()) return true;
        if (!await ai.hasGitHubToken()) return true;
        final loaded = await ai.loadInstalledModelForBackground();
        if (!loaded) return true;
        await ai.createAutonomousMaintenanceProposal(
          owner: 'cafeeteriaa',
          repository: 'King-vpn',
        );
        return true;
      }
      if (!await ai.hasGitHubToken()) {
        await Workmanager().cancelByTag(_tag);
        await ai.clearBackgroundRepairPullNumber();
        await ai.setBackgroundAutoDiscovery(false);
        return true;
      }

      final autoDiscovery = await ai.isBackgroundAutoDiscoveryEnabled();
      var pullNumber = await ai.getBackgroundRepairPullNumber();
      if (pullNumber == null && autoDiscovery) {
        pullNumber = await ai.findOpenPullRequestWithCiFailures(
          owner: 'cafeeteriaa',
          repository: 'King-vpn',
          maxPullRequests: 10,
        );
        if (pullNumber != null) {
          await ai.setBackgroundRepairPullNumber(pullNumber);
        }
      }
      if (pullNumber == null) return true;

      final report = await ai.inspectPullRequestCi(
        owner: 'cafeeteriaa',
        repository: 'King-vpn',
        pullNumber: pullNumber,
      );
      if (report['state'] != 'open') {
        final parentBranch = report['baseBranch']?.toString() ?? 'main';
        final parentPull = await ai.findOpenPullRequestForHeadBranch(
          owner: 'cafeeteriaa',
          repository: 'King-vpn',
          branch: parentBranch,
        );
        if (parentPull != null) {
          // A child repair PR was merged/closed. Resume monitoring its parent.
          await ai.setBackgroundRepairPullNumber(parentPull);
          return true;
        }
        await ai.clearBackgroundRepairPullNumber();
        if (!autoDiscovery) {
          await Workmanager().cancelByTag(_tag);
          return true;
        }
        return true;
      }
      if (report['hasFailures'] != true) return true;

      final loaded = await ai.loadInstalledModelForBackground();
      if (!loaded) {
        // No silent model download and no repeated 15-minute wakeups when the
        // installed model is missing or fails integrity verification. Stop the
        // schedule; the owner can reinstall/verify the model and re-enable it.
        await Workmanager().cancelByTag(_tag);
        await ai.clearBackgroundRepairPullNumber();
        await ai.setBackgroundAutoDiscovery(false);
        return true;
      }

      final result = await ai.repairFromFailedCiAutonomous(
        owner: 'cafeeteriaa',
        repository: 'King-vpn',
        pullNumber: pullNumber,
      );
      final status = result['status']?.toString();
      if (status == 'repair_limit_reached' ||
          status == 'duplicate_patch_blocked') {
        // Stop rather than waking the device every 15 minutes when this root
        // cannot make safe progress without new evidence or human intervention.
        await Workmanager().cancelByTag(_tag);
        await ai.clearBackgroundRepairPullNumber();
        return true;
      }
      final url = result['url'];
      if (url is String) {
        final nextPull = int.tryParse(Uri.parse(url).pathSegments.last);
        if (nextPull != null && nextPull > 0) {
          await ai.setBackgroundRepairPullNumber(nextPull);
        }
      }
      return true;
    } catch (_) {
      // WorkManager applies its own retry policy; the app's repair engine also
      // enforces per-root exponential cooldown and duplicate-patch protection.
      return false;
    } finally {
      await ai.dispose();
    }
  });
}

Future<bool> _kingHasVpnInterface() async {
  try {
    final interfaces = await NetworkInterface.list(includeLoopback: false);
    return interfaces.any((interface) =>
        KingNetworkFingerprint.isVpnInterfaceName(interface.name));
  } catch (e, st) {
    logError(e, st);
    // Fail closed if the interface state cannot be inspected.
    return true;
  }
}

Future<bool> _runKingNationalScannerBackgroundTask() async {
  Timer? networkMonitor;
  KingNetworkScanGuard? networkGuard;
  String? scheduledContinuationName;
  var observation = Future<void>.value();
  try {
    if (await _kingHasVpnInterface()) return false;
    final initialFingerprint = await KingNetworkFingerprint.capture();
    final guard = KingNetworkScanGuard(
      initialFingerprint: initialFingerprint,
    );
    networkGuard = guard;
    if (guard.shouldCancel) return false;
    Future<void> observeNetwork() {
      // Serialize timer and pre/post-scheduling checks so a slow interface
      // read cannot arrive out of order and overwrite a newer observation.
      final next = observation.then((_) async {
        if (guard.shouldCancel) return;
        try {
          final vpnActive = await _kingHasVpnInterface();
          final fingerprint = await KingNetworkFingerprint.capture();
          guard.observe(
            vpnInterfaceActive: vpnActive,
            currentFingerprint: fingerprint,
          );
        } catch (e, st) {
          logError(e, st);
          guard.observe(
            vpnInterfaceActive: true,
            currentFingerprint: '',
          );
        }
      });
      observation = next;
      return next;
    }

    networkMonitor = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!guard.shouldCancel) unawaited(observeNetwork());
    });

    await natLoadPersisted();
    if (guard.shouldCancel) return false;
    final detectedMode = await KingNationalScannerEngine.detectNationalMode();
    // Ambiguous evidence is not a completed scan; let WorkManager retry.
    if (detectedMode == null) return false;
    nationalMode = detectedMode;
    final seeds = await natHotNext(80, fetch: false);
    final report = await KingNationalScannerEngine.runPreflight(
      knownServers: seeds,
      onStatus: (_) {},
      sliceBudget: const Duration(minutes: 8),
      cancelled: () => guard.shouldCancel,
      addDiscovered: natIpMemMergeHits,
      // The WorkManager wrapper owns its single continuation decision below.
      scheduleContinuation: false,
    );
    await observeNetwork();
    if (guard.shouldCancel) return false;
    final needsContinuation = report.sliceYielded ||
        report.warnings.contains('ip_inventory_cursor_preserved_for_next_slice');
    if (needsContinuation) {
      final constraints = Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      );
      final continuationName =
          'king-national-scan-resume-${DateTime.now().microsecondsSinceEpoch}';
      scheduledContinuationName = continuationName;
      await observeNetwork();
      if (guard.shouldCancel) return false;
      await Workmanager().registerOneOffTask(
        continuationName,
        _nationalScannerTaskName,
        initialDelay: const Duration(minutes: 2),
        constraints: constraints,
        existingWorkPolicy: ExistingWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 2),
        tag: _nationalScannerTag,
      );
      // A handover can happen while the native scheduler call is in flight.
      // Cancel that exact unique work item if the post-registration check sees it.
      await observeNetwork();
      if (guard.shouldCancel) {
        await Workmanager().cancelByUniqueName(continuationName);
        return false;
      }
      return true;
    }
    return report.completed;
  } catch (e, st) {
    logError(e, st);
    return false;
  } finally {
    networkMonitor?.cancel();
    try {
      // Drain any poll already queued before shutting down the monitor.
      await observation;
    } catch (e, st) {
      logError(e, st);
    }
    if (networkGuard?.shouldCancel == true &&
        scheduledContinuationName != null) {
      try {
        await Workmanager().cancelByUniqueName(scheduledContinuationName!);
      } catch (e, st) {
        logError(e, st);
      }
    }
  }
}


class KingAiBackgroundSupervisor {
  KingAiBackgroundSupervisor._();

  static void _requireOwnerSession() {
    if (!KingAiOwnerAuth.instance.hasActiveSession) {
      throw StateError('Owner authentication is required to manage background repair.');
    }
  }

  static Future<void> initialize() async {
    await Workmanager().initialize(kingAiBackgroundDispatcher);
    _kingBackgroundWorkmanagerInitialized = true;
    await _scheduleOfficialResearch();
    await _scheduleNationalScanner();
  }

  /// Called when a foreground scan yields at its safe time slice. The durable
  /// cursor remains authoritative; this only asks Android to resume later.
  static Future<void> scheduleNationalScannerContinuation({
    bool Function()? cancelled,
  }) async {
    if (!_kingBackgroundWorkmanagerInitialized) return;
    bool isCancelled() {
      try {
        return cancelled?.call() ?? false;
      } catch (_) {
        return true;
      }
    }
    if (isCancelled()) return;
    final constraints = Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    );
    final uniqueName =
        'king-national-scan-resume-${DateTime.now().microsecondsSinceEpoch}';
    if (isCancelled()) return;
    await Workmanager().registerOneOffTask(
      uniqueName,
      _nationalScannerTaskName,
      initialDelay: const Duration(minutes: 2),
      constraints: constraints,
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 2),
      tag: _nationalScannerTag,
    );
    // Foreground scans can also hand over networks while the native schedule
    // request is in flight. Cancel the exact continuation if that raced.
    if (isCancelled()) {
      await Workmanager().cancelByUniqueName(uniqueName);
    }
  }

  /// Daily, network-constrained scanner maintenance. WorkManager is
  /// best-effort (Doze/OEM policy may defer it); bounded one-off continuations
  /// resume the durable journal until the configured inventory pass completes.
  static Future<void> _scheduleNationalScanner() async {
    final constraints = Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    );
    await Workmanager().registerPeriodicTask(
      _nationalScannerUniqueName,
      _nationalScannerTaskName,
      frequency: const Duration(hours: 24),
      constraints: constraints,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      tag: _nationalScannerTag,
    );
    await Workmanager().registerOneOffTask(
      _nationalScannerInitialName,
      _nationalScannerTaskName,
      initialDelay: const Duration(minutes: 5),
      constraints: constraints,
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
      tag: _nationalScannerTag,
    );
  }

  /// Research runs automatically without an owner session because it is
  /// read-only and stores only short excerpts from the official-source
  /// allowlist. Android may defer this best-effort background work.
  static Future<void> _scheduleOfficialResearch() async {
    final constraints = Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    );
    await Workmanager().registerPeriodicTask(
      _researchUniqueName,
      _researchTaskName,
      frequency: kingAiOfficialResearchInterval,
      constraints: constraints,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      tag: _researchTag,
    );
    await Workmanager().registerOneOffTask(
      _researchInitialName,
      _researchTaskName,
      initialDelay: Duration.zero,
      constraints: constraints,
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 30),
      tag: _researchTag,
    );
  }

  /// Android WorkManager periodic work is best-effort, not an exact timer.
  /// Schedule a one-shot first pass as well, so enabling the supervisor does
  /// not leave the first check waiting for the next periodic maintenance window.
  /// The periodic task remains the low-frequency recovery/safety net.
  static Future<void> _scheduleSupervisor() async {
    final constraints = Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    );
    await Workmanager().registerPeriodicTask(
      _uniqueName,
      _taskName,
      frequency: const Duration(minutes: 15),
      constraints: constraints,
      tag: _tag,
    );
    await Workmanager().registerOneOffTask(
      _initialUniqueName,
      _taskName,
      initialDelay: Duration.zero,
      constraints: constraints,
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
      tag: _tag,
    );
  }

  static Future<void> enable(int pullNumber) async {
    _requireOwnerSession();
    if (pullNumber < 1) throw ArgumentError.value(pullNumber, 'pullNumber');
    await KingLocalAi.instance.setBackgroundAutoDiscovery(false);
    await KingLocalAi.instance.setBackgroundRepairPullNumber(pullNumber);
    await _scheduleSupervisor();
  }

  /// A daily source audit is deliberately low frequency and resource-bounded.
  static Future<void> _scheduleAutonomousAudit() async {
    final constraints = Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    );
    await Workmanager().registerPeriodicTask(
      _auditUniqueName,
      _auditTaskName,
      frequency: const Duration(hours: 24),
      constraints: constraints,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      tag: _auditTag,
    );
    await Workmanager().registerOneOffTask(
      _auditInitialName,
      _auditTaskName,
      initialDelay: Duration.zero,
      constraints: constraints,
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 30),
      tag: _auditTag,
    );
  }

  /// One-time owner opt-in starts the continuous maintenance loop. It
  /// researches official network guidance automatically and creates isolated
  /// CI-repair PRs when evidence supports a fix. It never merges or publishes.
  static Future<void> enableAutonomousMaintenance() async {
    _requireOwnerSession();
    if (!await KingLocalAi.instance.hasGitHubToken() ||
        !KingLocalAi.instance.isLoaded) {
      throw StateError('GitHub token and the verified local model must be ready first.');
    }
    await KingLocalAi.instance.setBackgroundAutoDiscovery(true);
    await KingLocalAi.instance.clearBackgroundRepairPullNumber();
    await _scheduleSupervisor();
    await _scheduleAutonomousAudit();
  }

  /// Backwards-compatible name for the owner console.
  static Future<void> enableAutomaticDiscovery() =>
      enableAutonomousMaintenance();

  static Future<void> disable() async {
    _requireOwnerSession();
    await Workmanager().cancelByTag(_tag);
    await Workmanager().cancelByTag(_auditTag);
    await KingLocalAi.instance.clearBackgroundRepairPullNumber();
    await KingLocalAi.instance.setBackgroundAutoDiscovery(false);
  }
}
