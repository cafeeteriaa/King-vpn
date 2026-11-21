import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'king_local_ai.dart';
import 'king_ai_autonomy_policy.dart';
import 'king_ai_owner_auth.dart';
import 'king_ai_provider_pilot.dart';

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
const String _researchQuery =
    'Iran mobile internet domestic routing national network DNS IPv4 IPv6 '
    'Android VPNService network changes DoH TLS SNI Xray V2Ray sing-box '
    'Cloudflare tunnel DNS security Flutter Dart performance official docs';

/// WorkManager entry point. Background jobs use configured cloud helpers and
/// never download or load the optional 1.1 GB local model.
@pragma('vm:entry-point')
void kingAiBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
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
        // Cloud-first maintenance uses configured free API helpers. Never
        // download or load the optional 1.1 GB local model in a background job.
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
      if (!ai.isLoaded) {
        final pilot = KingAiProviderPilot.instance;
        if (!await pilot.cloudEnabled) return true;
        final configured = await pilot.configuredProviders();
        final hasFreeHelper = configured[KingAiProvider.gemini] == true ||
            configured[KingAiProvider.groq] == true ||
            configured[KingAiProvider.openRouter] == true;
        if (!hasFreeHelper) return true;
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

      // CI repair proposals use King's private cloud-first helper route
      // when no optional local model is installed. No model download/load here.
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

class KingAiBackgroundSupervisor {
  KingAiBackgroundSupervisor._();

  static void _requireOwnerSession() {
    if (!KingAiOwnerAuth.instance.hasActiveSession) {
      throw StateError('Owner authentication is required to manage background repair.');
    }
  }

  static Future<void> initialize() async {
    await Workmanager().initialize(kingAiBackgroundDispatcher);
    await _scheduleOfficialResearch();
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
    final ai = KingLocalAi.instance;
    if (!await ai.hasGitHubToken()) {
      throw StateError('GitHub owner token must be configured first.');
    }
    // WorkManager executes in a separate isolate/process lifecycle; an
    // in-memory foreground model is not available there. Require a configured
    // free cloud helper for scheduled work instead of waking up to no-op.
    final pilot = KingAiProviderPilot.instance;
    if (!await pilot.cloudEnabled) {
      throw StateError('Enable King AI cloud helpers before scheduling background repair.');
    }
    final configured = await pilot.configuredProviders();
    if (configured[KingAiProvider.gemini] != true &&
        configured[KingAiProvider.groq] != true &&
        configured[KingAiProvider.openRouter] != true) {
      throw StateError('Configure at least one approved free-tier coding helper first.');
    }
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
    final ai = KingLocalAi.instance;
    if (!await ai.hasGitHubToken()) {
      throw StateError('GitHub owner token must be configured first.');
    }
    final pilot = KingAiProviderPilot.instance;
    if (!await pilot.cloudEnabled) {
      throw StateError('Enable King AI cloud helpers before starting low-resource autonomous maintenance.');
    }
    final configured = await pilot.configuredProviders();
    final hasFreeHelper = configured[KingAiProvider.gemini] == true ||
        configured[KingAiProvider.groq] == true ||
        configured[KingAiProvider.openRouter] == true;
    if (!hasFreeHelper) {
      throw StateError('Configure at least one approved free-tier King AI helper first.');
    }
    await ai.setBackgroundAutoDiscovery(true);
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
