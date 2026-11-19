import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'king_local_ai.dart';

const String _researchTaskName = 'kingAiOfficialResearch';
const String _researchUniqueName = 'king-ai-official-research-periodic';
const String _researchInitialName = 'king-ai-official-research-initial';
const String _researchTag = 'king-ai-official-research';
const String _researchQuery =
    'Android VPNService Flutter WorkManager DNS connectivity diagnostics '
    'network security official documentation';

/// Low-cost background research only. This worker never downloads/loads the
/// coding model, reads source files, accesses GitHub tokens, or mutates code.
@pragma('vm:entry-point')
void kingAiBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (task != _researchTaskName) return true;

    final ai = KingLocalAi.instance;
    try {
      await ai.researchGoogle(_researchQuery, maxResults: 2)
          .timeout(const Duration(seconds: 55));
      return true;
    } catch (_) {
      // A restricted network is not a crash. WorkManager retries later.
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

  /// Android WorkManager is best-effort and may defer jobs under power policy.
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
}
