import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class VpnEngineOwnershipSourceGuard(unittest.TestCase):
    def test_coordinator_serializes_owners_and_notifies_waiters(self):
        source = (ROOT / "android_src" / "KingVpnEngineCoordinator.kt").read_text()
        self.assertIn("while (activeOwner != null && activeOwner != engine)", source)
        self.assertIn("released.awaitNanos(remaining)", source)
        self.assertIn("released.signalAll()", source)
        self.assertIn("if (activeOwner == engine)", source)

    def test_wireguard_acquires_before_start_and_releases_only_after_down(self):
        source = (ROOT / "android_src" / "KingWireGuardCore.kt").read_text()
        acquire = source.index('KingVpnEngineCoordinator.acquire("wireguard"')
        start = source.index("backend.setState(tunnel, Tunnel.State.UP, config)")
        self.assertLess(acquire, start)
        self.assertIn('KingVpnEngineCoordinator.release("wireguard")', source)
        self.assertIn("KingVpnService.instance?.stopForEngineHandoff()", source)
        self.assertIn("backend.getState(tunnel) == Tunnel.State.DOWN", source)
        self.assertIn("getOrNull() == Tunnel.State.DOWN", source)
        self.assertNotIn("getOrNull() != Tunnel.State.UP", source)

    def test_xray_acquires_before_establish_and_releases_after_stop(self):
        source = (ROOT / "android_src" / "KingVpnService.java").read_text()
        acquire = source.index("if (!acquireEngineOwnership(myAttempt))")
        establish = source.index("ParcelFileDescriptor fd = establish(cfg)")
        self.assertLess(acquire, establish)
        self.assertIn('KingVpnEngineCoordinator.release("xray")', source)
        self.assertIn('KingWireGuardCore.Companion.shared(this).disconnect()', source)
        self.assertIn("engineReleasePending", source)
        self.assertIn("if (!isCurrent(myAttempt)) return false;", source)
        self.assertIn("while (engineReleasePending)", source)

    def test_android_prepare_copies_the_coordinator_into_the_generated_host(self):
        source = (ROOT / "prepare_android.py").read_text()
        self.assertIn("shutil.copy('android_src/KingVpnEngineCoordinator.kt'", source)

    def test_handoff_does_not_clear_user_failover_state(self):
        source = (ROOT / "android_src" / "KingVpnService.java").read_text()
        start = source.index("public void stopForEngineHandoff()")
        end = source.index("\n    }", start)
        method = source[start:end]
        self.assertIn("requestStop(false)", method)
        self.assertNotIn("requestStop(true)", method)



class SingBoxIntegrationSourceGuard(unittest.TestCase):
    def test_dependency_is_pinned_and_build_scripts_are_invoked(self):
        workflow = (ROOT / ".github" / "workflows" / "build.yml").read_text()
        dep = (ROOT / "tools" / "configure_sing_box_dependency.py").read_text()
        self.assertIn("72f76fb714e07637a560774a7f2fdd3ae11884c4", dep)
        self.assertIn("configure_sing_box_dependency.py", workflow)
        self.assertIn("patch_sing_box_gradle.py", workflow)

    def test_three_engine_handoff_is_wired(self):
        activity = (ROOT / "android_src" / "MainActivity.kt").read_text()
        xray = (ROOT / "android_src" / "KingVpnService.java").read_text()
        wgsrc = (ROOT / "android_src" / "KingWireGuardCore.kt").read_text()
        dart = (ROOT / "lib" / "king_sing_box_core.dart").read_text()
        self.assertIn('"king/vpn_engine_owner"', activity)
        self.assertIn("SingBoxVpnService", xray)
        self.assertIn("SingBoxVpnService", wgsrc)
        self.assertIn("'engine': 'libbox'", dart)
        self.assertIn("waitForStatus", dart)

    def test_libbox_page_is_reachable(self):
        source = (ROOT / "lib" / "main.dart").read_text()
        self.assertIn("king_sing_box_page.dart", source)
        self.assertIn("KingSingBoxPage()", source)
        self.assertIn("value: 'libbox'", source)


if __name__ == "__main__":
    unittest.main()
