import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ReliableVpnDnsPolicyTests(unittest.TestCase):
    def test_reliable_config_preserves_dns_policy_from_shared_builder(self):
        source = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
        start = source.index("String _reliableVpnCfg(String cfg)")
        end = source.index("// completes when the VPN tunnel reports CONNECTED", start)
        body = source[start:end]
        self.assertIn("cfg = withNpvAmCore(cfg);", body)
        self.assertIn("if (nationalMode)", body)
        self.assertNotIn("else if (secureDns && !ultraMode && !indestructibleMode)", body)
        self.assertNotIn("d['servers'] = <dynamic>[", body)

    def test_shared_builder_keeps_custom_and_auto_provider_order(self):
        source = (ROOT / "lib" / "npv_am_extras.dart").read_text(encoding="utf-8")
        start = source.index("String withNpvAmCore(String cfg)")
        end = source.index("List<Widget> npvAmSettingsItems(", start)
        body = source[start:end]
        self.assertIn("customDnsList() ??", body)
        self.assertIn("effectiveDnsProv()", body)
        self.assertIn("d['servers'] = servers;", body)

    def test_national_mode_does_not_append_global_or_imported_dns_servers(self):
        source = (ROOT / "lib" / "npv_am_extras.dart").read_text(encoding="utf-8")
        start = source.index("String withNpvAmCore(String cfg)")
        end = source.index("List<Widget> npvAmSettingsItems(", start)
        body = source[start:end]
        self.assertIn("..._dnsUrls['shecan']!", body)
        self.assertIn("..._dnsUrls['electro']!", body)
        self.assertIn("..._dnsUrls['radar']!", body)
        self.assertIn("if (!nationalMode)", body)
        self.assertIn("final existingServers = d['servers'];", body)

    def test_selected_doh_keeps_priority_over_ip_fallbacks(self):
        source = (ROOT / "lib" / "npv_am_extras.dart").read_text(encoding="utf-8")
        start = source.index("String withNpvAmCore(String cfg)")
        end = source.index("List<Widget> npvAmSettingsItems(", start)
        body = source[start:end]
        self.assertIn("final servers = <dynamic>[];", body)
        self.assertIn("if (!servers.contains(value)) servers.add(value);", body)
        self.assertIn("d['servers'] = servers;", body)
        self.assertNotIn("final ips = <dynamic>[];", body)
        self.assertNotIn("final doh = <dynamic>[];", body)
