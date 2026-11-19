import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class KingVpnSourceGuardTests(unittest.TestCase):
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

    def test_ci_pipelines_propagate_failures_through_tee(self):
        workflow = (ROOT / '.github' / 'workflows' / 'build.yml').read_text(encoding='utf-8')
        self.assertGreaterEqual(workflow.count('set -o pipefail'), 3)


    def test_home_screen_exposes_one_unified_pilot_action(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        pilot_ui = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        self.assertIn("'شروع خلبان هوشمند'", main)
        self.assertIn('await startLocalPilot();', main)
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
        self.assertLess(tick.index('await _pilotDetectNetworkMode();'), tick.index('unawaited(autoTuneNow());'))
        detect_start = pilot.index('Future<NatNetworkClass> _pilotDetectNetworkMode()')
        detect_end = pilot.index('void ensureLocalPilotRunning()', detect_start)
        detect = pilot[detect_start:detect_end]
        self.assertIn('NatNetworkDiagnosis.refresh(force: true)', detect)

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
