import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class AndroidTunDnsPatchTests(unittest.TestCase):
    def test_plugin_utilities_is_patched_for_dns_hijacking(self):
        source = (ROOT / "patch_plugin.py").read_text(encoding="utf-8")
        self.assertIn("utils = find_java('Utilities.java')", source)
        self.assertIn('"protocol", "dns"', source)
        self.assertIn('"king-dns-hijack"', source)
        self.assertIn('"outboundTag", dnsOutboundTag', source)
        self.assertIn('startsWith("king-dns-hijack")', source)
        self.assertIn("boolean hasDnsRoute = false;", source)
        self.assertIn("if (!hasDnsRoute)", source)

    def test_android_dns_packets_are_not_routed_direct_by_patch(self):
        source = (ROOT / "patch_plugin.py").read_text(encoding="utf-8")
        start = source.index("# P1-DNS:")
        end = source.index("# 4a)", start)
        patch = source[start:end]
        self.assertIn('.put("port", "53")', patch)
        self.assertNotIn('.put("port", "53,853")\n                        .put("outboundTag", "direct")', patch)
        self.assertIn("'P1-DNS route Android TUN DNS through Xray DNS outbound'", patch)

    def test_plugin_default_dns_strategy_preserves_dual_stack(self):
        source = (ROOT / "patch_plugin.py").read_text(encoding="utf-8")
        start = source.index("# P1-DNS:")
        end = source.index("# 4a)", start)
        patch = source[start:end]
        self.assertIn('dns.put("queryStrategy", "UseIPv4")', patch)
        self.assertIn('dns.put("queryStrategy", "UseIP")', patch)
