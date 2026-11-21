import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class TunnelTrafficVerificationTests(unittest.TestCase):
    def test_proxy_mode_does_not_bypass_real_core_traffic_check(self):
        source = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
        start = source.index("Future<bool> _tunnelTrafficOk() async {")
        end = source.index("Future<bool> _stableTunnelTrafficOk(", start)
        body = source[start:end]
        self.assertNotIn("if (proxyMode) return true", body)
        self.assertIn("_siteOpens(u, viaCore: true)", body)
        self.assertIn("if (ok) return true", body)
