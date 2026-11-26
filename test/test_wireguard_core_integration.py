import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class WireGuardCoreIntegrationTests(unittest.TestCase):
    def test_native_engine_uses_real_wireguard_backend_and_config_parser(self):
        source = (ROOT / "android_src" / "KingWireGuardCore.kt").read_text(encoding="utf-8")
        self.assertIn("GoBackend(appContext)", source)
        self.assertIn("Config.parse(it)", source)
        self.assertIn("Tunnel.State.UP", source)
        self.assertIn("Tunnel.State.DOWN", source)
        self.assertNotIn("V2rayCoreManager", source)
        self.assertNotIn("flutter_v2ray", source)

    def test_native_channel_exposes_independent_lifecycle(self):
        source = (ROOT / "android_src" / "MainActivity.kt").read_text(encoding="utf-8")
        self.assertIn('"king/wireguard"', source)
        self.assertIn('"connect"', source)
        self.assertIn('"disconnect"', source)
        self.assertIn('"status"', source)
        self.assertIn("KingWireGuardCore.shared(applicationContext)", source)

    def test_build_pipeline_includes_and_copies_wireguard_runtime(self):
        source = (ROOT / "prepare_android.py").read_text(encoding="utf-8")
        self.assertIn("com.wireguard.android:tunnel:1.0.20260102", source)
        self.assertIn("KingWireGuardCore.kt", source)
        self.assertIn("coreLibraryDesugaring", source)

    def test_dart_bridge_keeps_wireguard_config_out_of_xray(self):
        source = (ROOT / "lib" / "king_wireguard_core.dart").read_text(encoding="utf-8")
        self.assertIn("MethodChannel('king/wireguard')", source)
        self.assertIn("'connect'", source)
        self.assertIn("'disconnect'", source)
        self.assertIn("'status'", source)
        self.assertIn("[Interface]", source)
        self.assertIn("[Peer]", source)


if __name__ == "__main__":
    unittest.main()
