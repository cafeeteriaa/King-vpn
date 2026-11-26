import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class VpnEngineOwnershipSourceGuard(unittest.TestCase):
    def test_coordinator_serializes_owners_and_notifies_waiters(self):
        source = (ROOT / "android_src" / "KingVpnEngineCoordinator.kt").read_text()
        self.assertIn("while (activeOwner != null && activeOwner != engine)", source)
        self.assertIn("monitor.wait(waitMs)", source)
        self.assertIn("monitor.notifyAll()", source)
        self.assertIn("if (activeOwner == engine)", source)

    def test_wireguard_acquires_before_start_and_releases_only_after_down(self):
        source = (ROOT / "android_src" / "KingWireGuardCore.kt").read_text()
        acquire = source.index('KingVpnEngineCoordinator.acquire("wireguard"')
        start = source.index("backend.setState(tunnel, Tunnel.State.UP, config)")
        self.assertLess(acquire, start)
        self.assertIn('KingVpnEngineCoordinator.release("wireguard")', source)
        self.assertIn("KingVpnService.instance?.stopForEngineHandoff()", source)
        self.assertIn("backend.getState(tunnel) == Tunnel.State.DOWN", source)

    def test_xray_acquires_before_establish_and_releases_after_stop(self):
        source = (ROOT / "android_src" / "KingVpnService.java").read_text()
        acquire = source.index("if (!acquireEngineOwnership())")
        establish = source.index("ParcelFileDescriptor fd = establish(cfg)")
        self.assertLess(acquire, establish)
        self.assertIn('KingVpnEngineCoordinator.release("xray")', source)
        self.assertIn('KingWireGuardCore.Companion.shared(this).disconnect()', source)
        self.assertIn("engineReleasePending", source)

    def test_handoff_does_not_clear_user_failover_state(self):
        source = (ROOT / "android_src" / "KingVpnService.java").read_text()
        start = source.index("public void stopForEngineHandoff()")
        end = source.index("\n    }", start)
        method = source[start:end]
        self.assertIn("requestStop(false)", method)
        self.assertNotIn("requestStop(true)", method)


if __name__ == "__main__":
    unittest.main()
