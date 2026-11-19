import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'king_local_ai.dart';

const String _taskName = 'kingAiCiRepair';
const String _uniqueName = 'king-ai-ci-repair-periodic';
const String _initialUniqueName = 'king-ai-ci-repair-initial';
const String _tag = 'king-ai-ci-repair';

const String _researchTaskName = 'kingAiOfficialResearch';
const String _researchUniqueName = 'king-ai-official-research-periodic';
const String _researchInitialName = 'king-ai-official-research-initial';
const String _researchTag = 'king-ai-official-research';
const String _researchQuery =
    'Android VPNService Flutter WorkManager DNS connectivity diagnostics '
    'network security official documentation';

/// WorkManager entry point. The model is loaded only from a foreground-verified
/// local file; this worker never downloads the 1.1 GB model in the background.
@pragma('vm:entry-point')
void kingAiBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (task != _taskName && task != _researchTaskName) return true;

    final ai = KingLocalAi.instance;
    try {
      if (task == _researchTaskName) {
        // Passive learning only: this worker stores short excerpts from the
        // official-source allowlist. It never loads the 1.1 GB model, reads
        // private project files, changes source code, or needs a GitHub token.
        await ai.researchGoogle(_researchQuery, maxResults: 2)
            .timeout(const Duration(seconds: 55));
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
        // No silent model download in background. The user can reopen the app,
        // install/verify the model, and explicitly enable the supervisor again.
        return true;
      }

      final result = await ai.repairFromFailedCi(
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

  static Future<void> initialize() async {
    await Workmanager().initialize(kingAiBackgroundDispatcher);
    await _scheduleOfficialResearch();
  }

  /// Best-effort background research, scheduled automatically on app startup.
  /// WorkManager enforces network and battery constraints and may defer work
  /// according to Android power policy; this is not an exact timer.
  static Future<void> _scheduleOfficialResearch() async {
    final constraints = Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    );
    await Workmanager().registerPeriodicTask(
      _researchUniqueName,
      _researchTaskName,
      frequency: const Duration(hours: 12),
      constraints: constraints,
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
    if (pullNumber < 1) throw ArgumentError.value(pullNumber, 'pullNumber');
    await KingLocalAi.instance.setBackgroundAutoDiscovery(false);
    await KingLocalAi.instance.setBackgroundRepairPullNumber(pullNumber);
    await _scheduleSupervisor();
  }

  static Future<void> enableAutomaticDiscovery() async {
    await KingLocalAi.instance.setBackgroundAutoDiscovery(true);
    await KingLocalAi.instance.clearBackgroundRepairPullNumber();
    await _scheduleSupervisor();
  }

  static Future<void> disable() async {
    await Workmanager().cancelByTag(_tag);
    await KingLocalAi.instance.clearBackgroundRepairPullNumber();
    await KingLocalAi.instance.setBackgroundAutoDiscovery(false);
  }
}
