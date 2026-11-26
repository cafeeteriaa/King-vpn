from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class WireGuardIntegrationGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.main = (ROOT / "lib/main.dart").read_text(encoding="utf-8")
        cls.bridge = (ROOT / "lib/king_wireguard_core.dart").read_text(encoding="utf-8")
        cls.native = (ROOT / "android_src/KingWireGuardCore.kt").read_text(encoding="utf-8")
        cls.activity = (ROOT / "android_src/MainActivity.kt").read_text(encoding="utf-8")
        cls.prepare = (ROOT / "prepare_android.py").read_text(encoding="utf-8")

    def test_wg_quick_profile_is_parsed_as_a_distinct_protocol(self):
        self.assertIn("link.toLowerCase().startsWith('[interface]')", self.main)
        self.assertIn("link.toLowerCase().contains('[peer]')", self.main)
        self.assertIn("server.wireGuard = true", self.main)
        self.assertIn("wireguard:$host:$port", self.main)
        self.assertIn("c.wireGuard = s.wireGuard", self.main)

    def test_complete_multiline_profile_is_imported_as_one_entry(self):
        self.assertIn("rawInput.toLowerCase().startsWith('[interface]')", self.main)
        self.assertIn("_mineList().where((server) => server.wireGuard)", self.main)

    def test_wireguard_dispatch_never_uses_xray_config_builder(self):
        self.assertIn("if (s.wireGuard)", self.main)
        self.assertIn("_kingWireGuardCore.connect(s.link)", self.main)
        self.assertIn("row == 'f:wireguard'", self.main)
        self.assertIn("if (!s.personal && !s.wireGuard) _resAdd(s)", self.main)

    def test_native_engine_uses_official_wireguard_backend_and_parser(self):
        self.assertIn("GoBackend(appContext)", self.native)
        self.assertIn("Config.parse(it)", self.native)
        self.assertIn("backend.setState(tunnel, Tunnel.State.UP, config)", self.native)
        self.assertIn("backend.setState(tunnel, Tunnel.State.DOWN, null)", self.native)

    def test_native_channel_handles_permission_and_own_lifecycle(self):
        self.assertIn('"king/wireguard"', self.activity)
        self.assertIn("VpnService.prepare(this)", self.activity)
        self.assertIn("startActivityForResult(permissionIntent, wireGuardPermissionRequest)", self.activity)
        self.assertIn('"disconnect", "status"', self.activity)

    def test_bridge_keeps_a_separate_method_channel(self):
        self.assertIn("MethodChannel('king/wireguard')", self.bridge)
        self.assertIn("'connect'", self.bridge)
        self.assertIn("'disconnect'", self.bridge)
        self.assertIn("'status'", self.bridge)

    def test_android_build_embeds_official_tunnel_artifact(self):
        self.assertIn("com.wireguard.android:tunnel:1.0.20260102", self.prepare)
        self.assertIn("coreLibraryDesugaring", self.prepare)
        self.assertIn("isCoreLibraryDesugaringEnabled", self.prepare)


if __name__ == "__main__":
    unittest.main()
