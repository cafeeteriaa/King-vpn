import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class KingVpnSourceGuardTests(unittest.TestCase):
    def test_smart_pilot_never_forwards_user_code_requests_to_local_coder(self):
        pilot = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        start = pilot.index('Future<String> _runPilotCommand(String raw)')
        end = pilot.index('void ensureLocalPilotRunning()', start)
        dispatcher = pilot[start:end]
        self.assertIn('این کادر فقط امکانات موجود King VPN', dispatcher)
        self.assertIn("'کدنویسی کن'", dispatcher)
        self.assertIn("'add feature'", dispatcher)
        self.assertIn("'توسعه بده'", dispatcher)
        self.assertIn("'write a function'", dispatcher)
        self.assertIn("q.contains('قابلیت')", dispatcher)
        self.assertIn("q.contains('ویژگی')", dispatcher)
        self.assertNotIn('generateCode(', dispatcher)
        self.assertNotIn('repairFromFailedCi(', dispatcher)

    def test_command_help_mentions_king_address(self):
        pilot = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        start = pilot.index('if (hasAny([\'راهنما\'')
        end = pilot.index("if (hasAny(['وضعیت'", start)
        help_text = pilot[start:end]
        self.assertIn('ابتدای فرمان «کینگ»', help_text)
        self.assertIn('«کینگ خلبان خاموش»', help_text)
        self.assertIn('«کینگ نت ملی وصل شو»', help_text)
        self.assertIn('«کینگ نت جهانی وصل شو»', help_text)

    def test_king_address_is_removed_before_smart_pilot_command_dispatch(self):
        pilot = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        start = pilot.index('String _normalizePilotText(String raw)')
        end = pilot.index('Future<String> _runPilotCommand(String raw)', start)
        normalizer = pilot[start:end]
        self.assertIn("(?:کینگ|king)", normalizer)
        self.assertIn("(?:سلام|هی)", normalizer)
        self.assertIn("return normalized.replaceFirst(", normalizer)

    def test_no_additional_engine_scaffolding_remains(self):
        self.assertFalse((ROOT / 'lib' / 'engine_registry.dart').exists())
        self.assertFalse((ROOT / 'lib' / 'singbox_core.dart').exists())
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertNotIn("import 'engine_registry.dart';", main)

    def test_automatic_scan_is_not_a_subnet_or_all_port_sweep(self):
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        start = nat.index('List<String> natSeedBlocks(')
        end = nat.index('\nint natMemQueued', start)
        seed_block = nat[start:end]
        self.assertIn("'${parsed.address}/32'", seed_block)
        domain_start = nat.index('Future<List<String>> _natDomainFirst(')
        domain_end = nat.index('\nFuture<List<String>> natDeviceHosts()', domain_start)
        domain_scan = nat[domain_start:domain_end]
        self.assertNotIn('natIrDomains', domain_scan)
        self.assertNotIn('for (var p = 1; p < 65536; p++)', domain_scan)

    def test_connect_path_uses_mode_aware_tunnel_probe(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn('networkAware: true', main)
        self.assertIn('final urls = nationalMode ? _tunnelTestUrlsNational', main)

    def test_king_voice_commands_are_persian_on_device_and_user_confirmed(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        workflow = (ROOT / '.github' / 'workflows' / 'build.yml').read_text(encoding='utf-8')
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        self.assertIn("import 'package:speech_to_text/speech_to_text.dart' as stt;", main)
        start = main.index('Future<void> _toggleSmartCommandSpeech()')
        end = main.index('Future<void> _loadSmartCommandFilters()', start)
        voice = main[start:end]
        self.assertIn('Permission.microphone.request()', voice)
        self.assertIn("startsWith('fa')", voice)
        self.assertIn('onDevice: true', voice)
        self.assertIn('if (s != AppLifecycleState.resumed && _smartSpeech.isListening)', main)
        self.assertIn('_smartCommandController.value = TextEditingValue(', voice)
        self.assertNotIn('_runSmartCommand(', voice)
        self.assertIn('speech_to_text:^7.4.0', workflow)
        self.assertIn('android.permission.RECORD_AUDIO', prepare)
        self.assertIn("if 'android.permission.RECORD_AUDIO' not in m:", prepare)
        self.assertIn('android.speech.RecognitionService', prepare)
        self.assertIn("if 'android.speech.RecognitionService' not in m:", prepare)
        self.assertIn("if '<queries>' in m:", prepare)
        self.assertIn("m.replace('<queries>', '<queries>' + speech_intent, 1)", prepare)

    def test_ci_pipelines_propagate_failures_through_tee(self):
        workflow = (ROOT / '.github' / 'workflows' / 'build.yml').read_text(encoding='utf-8')
        self.assertGreaterEqual(workflow.count('set -o pipefail'), 3)


    def test_home_screen_exposes_one_unified_pilot_action(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        pilot_ui = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        self.assertIn('_smartCommandPanel()', main)
        self.assertIn('اتصال خلبان', main)
        self.assertIn('await startLocalPilot();', main)
        # Command-only home: the legacy hero connect control is intentionally absent.
        self.assertIn('UiHero(', main)
        self.assertIn('onTap: null,', main)
        self.assertNotIn("label: const Text('جستجوی سرور با نت ملی')", main)
        ai_bar = pilot_ui[pilot_ui.index('Widget aiBar()'):pilot_ui.index('void aiSheet()')]
        self.assertNotIn('startGrokPilot', ai_bar)
        self.assertNotIn('startLocalPilot', ai_bar)
        self.assertNotIn('pickEngineThenStart(startGrokPilot', pilot_ui)

    def test_local_pilot_rechecks_network_after_link_changes(self):
        pilot = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        tick_start = pilot.index('Future<void> localPilotTick(')
        tick_end = pilot.index('void _localReschedule()', tick_start)
        tick = pilot[tick_start:tick_end]
        self.assertIn('if (!connected)', tick)
        self.assertIn('await _pilotDetectNetworkMode();', tick)
        detect_start = pilot.index('Future<NatNetworkClass> _pilotDetectNetworkMode()')
        detect_end = pilot.index('void ensureLocalPilotRunning()', detect_start)
        detect = pilot[detect_start:detect_end]
        self.assertIn('PilotNetworkProbe.refresh()', detect)
        self.assertNotIn('PilotNetworkProbe.refresh(force: true)', detect)
        self.assertNotIn('NatNetworkDiagnosis.refresh', detect)
        self.assertNotIn('autoTuneNow()', tick)


    def test_pilot_scanner_and_ip_ranges_are_isolated_from_general_scanners(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        pilot = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        national = (ROOT / 'lib' / 'national_engine.dart').read_text(encoding='utf-8')
        self.assertIn('class PilotNetworkProbe', national)
        self.assertIn('domesticTargets', national)
        self.assertIn('globalTargets', national)
        self.assertIn('SecureSocket.connect(host, 443', national)
        self.assertIn("command.contains('بازه') && command.contains('خلبان')", main)
        self.assertIn("command.contains('اسکن') && command.contains('خلبان')", main)
        self.assertNotIn("label: const Text('بازه‌های IP اختصاصی خلبان')", main)
        self.assertNotIn("label: const Text('پویش IP اختصاصی خلبان')", main)
        self.assertIn('_smartCommandPanel()', main)
        self.assertIn('مرکز فرمان هوشمند', main)
        self.assertIn('_runSmartCommand', main)
        self.assertIn("king_pilot_ip_ranges_v1", main)
        self.assertIn("_pilotRangesValid(c.text)", main)
        self.assertIn("bool _pilotRangesValid(String raw)", main)
        self.assertIn("king_pilot_scan_results_v1", main)
        self.assertIn('bool _pilotRangeCancelRequested = false;', main)
        command_start = main.index('Future<void> _runSmartCommand')
        command_end = main.index('Widget _smartCommandPanel()', command_start)
        command_parser = main[command_start:command_end]
        self.assertIn('_pilotRangeCancelRequested = true;', command_parser)
        self.assertLess(command_parser.index('_pilotRangeCancelRequested = true;'),
                        command_parser.index('if (command.isEmpty || _smartCommandRunning) return;'))
        pilot_scan_start = main.index('Future<void> _pilotScanOnly()')
        pilot_scan_end = main.index('// اسکن IP بدون تغییر تنظیمات دیگر', pilot_scan_start)
        pilot_scan = main[pilot_scan_start:pilot_scan_end]
        self.assertNotIn('natRangeScanStep', pilot_scan)
        self.assertNotIn('natRanges', pilot_scan)
        self.assertNotIn('abort', pilot_scan)
        self.assertIn('_pilotRangeCancelRequested', pilot_scan)
        self.assertIn('Socket.connect(host, 443', pilot_scan)
        self.assertIn('_pilotRangesDialog(context)', main)
        self.assertIn('_pilotScanOnly()', main)
        self.assertIn('_smartCountryCode(command)', main)
        self.assertIn("'germany': 'DE'", main)
        self.assertNotIn('label: Text(selCountry == null', main)
        self.assertNotIn("for (final pr in ['all', 'vmess'", main)
        self.assertNotIn('pickEngineThenStart(() => connect(s, gid)', main)
        self.assertEqual(main.count('extension ProjectNatSweep on _HomePageState'), 1)
        self.assertNotIn('_natRangesDialog(context)', main[main.index('Future<void> _pilotScanOnly()'):main.index('// اسکن IP بدون تغییر تنظیمات دیگر')])
        self.assertNotIn('UiTools(items: [', main[main.index('Widget build(BuildContext context)', main.index('class _HomePageState')):])
        keep_start = main.index('Future<void> _natKeep()')
        keep_end = main.index('void _natRangesDialog', keep_start)
        keep = main[keep_start:keep_end]
        self.assertIn('localPilotOn', keep)
        self.assertIn('if (localPilotOn && cpuHot == 0', keep)
        detect_start = pilot.index('Future<NatNetworkClass> _pilotDetectNetworkMode()')
        detect_end = pilot.index('void ensureLocalPilotRunning()', detect_start)
        self.assertNotIn('NatNetworkDiagnosis', pilot[detect_start:detect_end])
        self.assertIn('PilotNetworkProbe.refresh()', pilot[detect_start:detect_end])
        self.assertNotIn('PilotNetworkProbe.refresh(force: true)', pilot[detect_start:detect_end])
        self.assertIn('checks.where((ok) => ok).length >= 2', pilot)
        self.assertIn('_pilotPendingPositiveSamples >= 2', pilot)
        self.assertIn("'switch_best' => snap.connected", pilot)
        self.assertIn("'connect' => !_pilotPendingWasConnected && snap.connected", pilot)
        self.assertIn('Duration(seconds: 10)', pilot)
        self.assertIn('_pilotExperienceOperatorKey(s.operatorKey)', pilot)
        self.assertIn("'domestic' : 'global'", pilot)
        self.assertIn('total >= 5', pilot)
        self.assertIn('winRate >= 0.75', pilot)
        self.assertIn('king_pilot_experience_v1', pilot)
        self.assertIn('_pilotReconcileExperience(snap)', pilot)
        self.assertIn('_pilotSaveExperience()', pilot)
        self.assertNotIn("_localOpWins[k] = (_localOpWins[k] ?? 0) + 1;", pilot)
        nat_detect_start = main.index('Future<void> _natDetect()')
        nat_detect_end = main.index('DateTime? _checkSavedAt', nat_detect_start)
        nat_detect = main[nat_detect_start:nat_detect_end]
        self.assertIn('PilotNetworkProbe.refresh()', nat_detect)
        self.assertNotIn('dnsxAutoPick(', nat_detect)
        self.assertNotIn('ipAutoBackground(', nat_detect)
        connect_start = main.index('Future<void> _doConnect(')
        connect_end = main.index('void _cancelNow()', connect_start)
        connect = main[connect_start:connect_end]
        self.assertIn('if (localPilotOn)', connect)
        self.assertIn('PilotNetworkProbe.refresh()', connect)
        self.assertLess(connect.index('if (localPilotOn)'), connect.index('NatNetworkDiagnosis.refresh()'))

    def test_local_ai_research_updates_pilot_brain_and_repairs_are_review_gated(self):
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        self.assertIn('Duration(hours: 24)', ai)
        self.assertIn('_relevantResearchMemory(safePrompt)', ai)
        self.assertIn('notes.take(2)', ai)
        self.assertIn('not live telemetry', ai)
        self.assertIn("'draft': true", ai)
        self.assertIn('repairUntilGreen', ai)
        self.assertIn('No automatic merge or release is performed.', ai)
        self.assertIn('This updates research memory, not model weights.', ai)

    def test_flutter_artifact_path_matches_non_split_apk_build(self):
        workflow = (ROOT / '.github' / 'workflows' / 'build.yml').read_text(encoding='utf-8')
        self.assertIn('flutter build apk --debug --target-platform android-arm64', workflow)
        self.assertIn('build_app/build/app/outputs/flutter-apk/app-debug.apk', workflow)
        self.assertNotIn('app-arm64-v8a-debug.apk', workflow)
        self.assertIn('king-vpn-full-source-${{ github.run_number }}.zip', workflow)
        self.assertIn('build_app/android/local.properties', workflow)
        self.assertIn('Upload complete project ZIP', workflow)
        self.assertIn('${{ runner.temp }}', workflow)

    def test_plugin_dart_parser_hardening_is_part_of_build_patch(self):
        patch = (ROOT / 'patch_plugin.py').read_text(encoding='utf-8')
        for name in ('patch_url_dart', 'patch_vmess_dart', 'patch_vless_dart',
                     'patch_trojan_dart', 'patch_shadowsocks_dart'):
            self.assertIn(name, patch)
        parser_base = (ROOT / 'plugin_source_reference' / 'dart' / 'lib' / 'url' / 'url.dart').read_text(encoding='utf-8')
        self.assertIn('String fallbackSni(', parser_base)


if __name__ == '__main__':
    unittest.main()
