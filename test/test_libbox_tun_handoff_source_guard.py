import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]

class LibboxNativeHandoffGuard(unittest.TestCase):
    def test_coordinator_waits_for_native_stopped_state(self):
        source = (ROOT / "android_src" / "KingVpnEngineCoordinator.kt").read_text()
        self.assertIn("ServiceState.Listener", source)
        self.assertIn("ServiceStatus.Stopped", source)
        self.assertIn("stopLibboxAndRelease", source)
        self.assertIn("CountDownLatch", source)

    def test_engine_handoffs_use_native_release(self):
        for path in ("MainActivity.kt", "KingVpnService.java", "KingWireGuardCore.kt"):
            self.assertIn("stopLibboxAndRelease", (ROOT / "android_src" / path).read_text())

    def test_build_exposes_service_state_api(self):
        source = (ROOT / "tools" / "patch_sing_box_gradle.py").read_text()
        self.assertIn("ServiceState.kt", source)
        self.assertIn("internal enum class ServiceStatus", source)
        self.assertIn("internal data class ServiceSnapshot", source)
        self.assertIn("internal object ServiceState", source)

if __name__ == "__main__":
    unittest.main()
