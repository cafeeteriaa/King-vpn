import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class AmneziaWgIntegrationSourceGuard(unittest.TestCase):
    def test_jni_declarations_match_upstream_android_abi(self):
        source = (ROOT / "android_src" / "AmneziaWgNative.java").read_text()
        self.assertIn("package org.amnezia.awg;", source)
        for method in (
            "awgGetConfig(int handle)",
            "awgGetSocketV4(int handle)",
            "awgGetSocketV6(int handle)",
            "awgTurnOff(int handle)",
            "awgTurnOn(String ifName, int tunFd, String settings)",
            "awgVersion()",
        ):
            self.assertIn(method, source)
        self.assertIn('System.loadLibrary("awg-go")', source)

    def test_adapter_uses_shared_tun_and_does_not_start_upstream_vpn_service(self):
        source = (ROOT / "android_src" / "KingAmneziaWgCore.kt").read_text()
        self.assertIn("establishTun: () -> ParcelFileDescriptor?", source)
        self.assertIn("GoBackend.awgTurnOn(INTERFACE_NAME, activeDescriptor.fd, userspaceSettings)", source)
        self.assertIn("check(started >= 0)", source)
        self.assertIn("GoBackend.awgGetSocketV4(started)", source)
        self.assertIn("GoBackend.awgGetSocketV6(started)", source)
        self.assertIn("service.protect(socket4)", source)
        self.assertIn("service.protect(socket6)", source)
        self.assertNotIn("GoBackend.VpnService", source)

    def test_native_stop_is_a_hard_ownership_barrier(self):
        source = (ROOT / "android_src" / "KingAmneziaWgCore.kt").read_text()
        stop = source.index("GoBackend.awgTurnOff(handle)")
        close = source.index("tunDescriptor?.close()", stop)
        release = source.index('KingVpnEngineCoordinator.release(ENGINE_ID)', close)
        self.assertLess(stop, close)
        self.assertLess(close, release)
        self.assertIn("STOP_UNCONFIRMED", source)
        self.assertIn("tunDescriptor = descriptor", source)

    def test_all_existing_engines_handoff_to_amneziawg(self):
        xray = (ROOT / "android_src" / "KingVpnService.java").read_text()
        wireguard = (ROOT / "android_src" / "KingWireGuardCore.kt").read_text()
        activity = (ROOT / "android_src" / "MainActivity.kt").read_text()
        self.assertIn('KingAmneziaWgCore.shared().disconnect()', xray)
        self.assertIn('KingAmneziaWgCore.shared().disconnect()', wireguard)
        self.assertIn('"amneziawg" -> KingAmneziaWgCore.shared().disconnect()', activity)

    def test_generated_android_host_receives_both_adapter_files(self):
        prepare = (ROOT / "prepare_android.py").read_text()
        self.assertIn("KingAmneziaWgCore.kt", prepare)
        self.assertIn("AmneziaWgNative.java", prepare)


if __name__ == "__main__":
    unittest.main()
