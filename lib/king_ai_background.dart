import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'king_local_ai.dart';

const String _taskName = 'kingAiCiRepair';
const String _uniqueName = 'king-ai-ci-repair-periodic';
const String _tag = 'king-ai-ci-repair';

/// WorkManager entry point. The model is loaded only from a foreground-verified
/// local file; this worker never downloads the 1.1 GB model in the background.
@pragma('vm:entry-point')
void kingAiBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (task != _taskName) return true;

    final ai = KingLocalAi.instance;
    try {
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
  }

  /// Android WorkManager periodic work is best-effort, not an exact timer.
  /// It requires connectivity and a battery that is not currently low.
  static Future<void> enable(int pullNumber) async {
    if (pullNumber < 1) throw ArgumentError.value(pullNumber, 'pullNumber');
    await KingLocalAi.instance.setBackgroundAutoDiscovery(false);
    await KingLocalAi.instance.setBackgroundRepairPullNumber(pullNumber);
    await Workmanager().registerPeriodicTask(
      _uniqueName,
      _taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      tag: _tag,
    );
  }

  static Future<void> enableAutomaticDiscovery() async {
    await KingLocalAi.instance.setBackgroundAutoDiscovery(true);
    await KingLocalAi.instance.clearBackgroundRepairPullNumber();
    await Workmanager().registerPeriodicTask(
      _uniqueName,
      _taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      tag: _tag,
    );
  }

  static Future<void> disable() async {
    await Workmanager().cancelByTag(_tag);
    await KingLocalAi.instance.clearBackgroundRepairPullNumber();
    await KingLocalAi.instance.setBackgroundAutoDiscovery(false);
  }
}
