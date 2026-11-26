import ast, pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]

class WireGuardCoreSourceGuardTests(unittest.TestCase):
    def test_native_engine_uses_official_independent_backend(self):
        core = (ROOT / "android_src" / "KingWireGuardCore.kt").read_text()
        self.assertIn("GoBackend(appContext)", core)
        self.assertIn("Config.parse(it)", core)
        self.assertIn("Tunnel.State.UP", core)
        self.assertIn("Tunnel.State.DOWN", core)
        self.assertNotIn("V2ray", core)
        self.assertNotIn("buildCoreConfig", core)

    def test_flutter_bridge_has_dedicated_channel_and_profile_validation(self):
        bridge = (ROOT / "lib" / "king_wireguard_core.dart").read_text()
        native = (ROOT / "android_src" / "MainActivity.kt").read_text()
        self.assertIn("MethodChannel('king/wireguard')", bridge)
        self.assertIn('"king/wireguard"', native)
        self.assertIn("[Interface]", bridge)
        self.assertIn("[Peer]", bridge)

    def test_android_build_packages_wireguard_runtime_and_desugaring(self):
        script = (ROOT / "prepare_android.py").read_text()
        self.assertIn("com.wireguard.android:tunnel:1.0.20260102", script)
        self.assertIn("coreLibraryDesugaring", script)
        self.assertIn("KingWireGuardCore.kt", script)
        page = (ROOT / "lib" / "king_wireguard_page.dart").read_text()
        app = (ROOT / "lib" / "main.dart").read_text()
        native = (ROOT / "android_src" / "MainActivity.kt").read_text()
        self.assertIn("KingWireGuardPage", page)
        self.assertIn("value: 'wireguard'", app)
        self.assertIn("VpnService.prepare(this)", native)
        self.assertIn("onActivityResult", native)

    def test_native_ownership_check_uses_a_valid_kotlin_check_lambda(self):
        core = (ROOT / "android_src" / "KingWireGuardCore.kt").read_text()
        self.assertRegex(
            core,
            r'check\(KingVpnEngineCoordinator\.acquire\("wireguard", 30_000L\)\)\s*\{\s*"Another KING VPN engine did not release the Android VPN slot"\s*\}',
        )
        self.assertLess(
            core.index('check(KingVpnEngineCoordinator.acquire("wireguard", 30_000L))'),
            core.index("backend.setState(tunnel, Tunnel.State.UP, config)"),
        )
