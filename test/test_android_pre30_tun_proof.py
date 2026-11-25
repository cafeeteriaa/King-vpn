import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class AndroidPre30VpnOwnershipTests(unittest.TestCase):
    def test_pre30_requires_active_vpn_transport_and_this_apps_vpn_grant(self):
        source = (ROOT / "android_src" / "MainActivity.kt").read_text(encoding="utf-8")
        start = source.index('"kingVpnTransportOwnedByApp" -> {')
        end = source.index('"back" -> {', start)
        block = source[start:end]
        self.assertIn("Build.VERSION.SDK_INT < Build.VERSION_CODES.R", block)
        self.assertIn("NetworkCapabilities.TRANSPORT_VPN", block)
        self.assertIn("android.net.VpnService.prepare(this) == null", block)
        self.assertIn("result.success(isVpnTransport && vpnPermissionGranted)", block)
        self.assertIn("capabilities?.ownerUid == applicationInfo.uid", block)

    def test_vpn_grant_fallback_does_not_change_minimum_sdk_or_start_ui(self):
        prepare = (ROOT / "prepare_android.py").read_text(encoding="utf-8")
        self.assertIn("minSdk = 24", prepare)
        self.assertNotIn("startActivity(android.net.VpnService.prepare", prepare)
        self.assertNotIn("startActivity(VpnService.prepare", prepare)

    def test_dart_acceptance_still_requires_a_live_vpn_transport(self):
        source = (ROOT / "lib" / "nnie_core.dart").read_text(encoding="utf-8")
        start = source.index("bool? androidVpnTunnelEvidence(")
        end = source.index("/// Coalesces concurrent requests", start)
        block = source[start:end]
        self.assertIn("activeVpnTransport == false", block)
        self.assertIn("activeVpnTransport == true && activeVpnOwnedByApp == true", block)

    def test_existing_policy_tests_cover_owner_match_and_competing_vpn_rejection(self):
        tests = (ROOT / "test" / "nnie_core_test.dart").read_text(encoding="utf-8")
        self.assertIn("accepts an active VPN owned by this app", tests)
        self.assertIn("another VPN owner is rejected", tests)


if __name__ == "__main__":
    unittest.main()
