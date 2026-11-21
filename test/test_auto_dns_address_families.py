import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class AutoDnsAddressFamilyTests(unittest.TestCase):
    def test_global_auto_dns_probes_known_ipv4_and_ipv6_resolvers(self):
        source = (ROOT / "lib" / "npv_am_extras.dart").read_text(encoding="utf-8")
        start = source.index("Future<String> pickBestDns(")
        end = source.index("const _lanCidrs", start)
        body = source[start:end]
        for address in (
            "1.1.1.1", "2606:4700:4700::1111",
            "8.8.8.8", "2001:4860:4860::8888",
            "9.9.9.9", "2620:fe::fe",
            "208.67.222.222", "2620:119:35::35",
            "94.140.14.14", "2a10:50c0::ad1:ff",
        ):
            self.assertIn(address, body)
        self.assertIn("e.value.map(_probeDnsIp)", body)

    def test_national_auto_dns_keeps_domestic_resolver_scope(self):
        source = (ROOT / "lib" / "npv_am_extras.dart").read_text(encoding="utf-8")
        start = source.index("Future<String> pickBestDns(")
        end = source.index("const _lanCidrs", start)
        body = source[start:end]
        national = body[body.index("final selectedIpProbes"):body.index("await Future.wait")]
        self.assertIn("'shecan': ['178.22.122.100']", national)
        self.assertNotIn("2606:4700:4700::1111", national)
