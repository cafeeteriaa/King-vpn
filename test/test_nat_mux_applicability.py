import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NatMuxApplicabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / "lib" / "nat_ultra.dart").read_text(encoding="utf-8")

    def test_mux_is_not_globally_disabled_and_is_protocol_gated(self):
        facts_start = self.source.index("class _NatFacts")
        facts_end = self.source.index("const Set<String> _natRetiredNames", facts_start)
        facts = self.source[facts_start:facts_end]
        self.assertIn("vless,", facts)
        self.assertIn("trojan,", facts)
        self.assertIn("vless = s.link.toLowerCase().startsWith('vless://')", facts)
        self.assertIn("trojan = s.link.toLowerCase().startsWith('trojan://')", facts)

        applies_start = self.source.index("bool _natAppliesF")
        applies_end = self.source.index("bool _natChangesAddr", applies_start)
        applies = self.source[applies_start:applies_end]
        self.assertNotIn("if (x.mux) return false;", applies)
        self.assertIn("f.ss || f.vmess || f.vless || f.trojan", applies)
        self.assertIn("f.grpc || f.xh || f.reality", applies)

    def test_mux_builder_preserves_worker_xtls_and_transport_guards(self):
        start = self.source.index("String _natMux(")
        end = self.source.index("// V7-DNS:", start)
        body = self.source[start:end]
        self.assertIn("_isWorkerOutbound(o)", body)
        self.assertIn('RegExp(r\'"flow"\\s*:\\s*"xtls\')', body)
        self.assertIn("network == 'grpc'", body)
        self.assertIn("network == 'xhttp'", body)
        self.assertIn("network == 'splithttp'", body)
        self.assertIn("'mux': {'enabled': true", body)

    def test_mux_winner_can_be_reused_but_is_not_a_speed_variant(self):
        start = self.source.index("int natVarFor(")
        end = self.source.index("bool natIsHeavy", start)
        nat_var_for = self.source[start:end]
        self.assertNotIn("x.mux", nat_var_for)
        self.assertIn("if (x.noise) return 0;", nat_var_for)
        self.assertIn("_natAppliesF(_NatFacts(s), v)", nat_var_for)

        heavy_start = self.source.index("bool natIsHeavy(")
        heavy_end = self.source.index("int? natSpeedVariant", heavy_start)
        heavy = self.source[heavy_start:heavy_end]
        self.assertIn("x.mux", heavy)

    def test_mux_is_deferred_in_normal_mode(self):
        start = self.source.index("bool _natIsSlowHeavy(")
        end = self.source.index("List<int> _natOrder", start)
        body = self.source[start:end]
        self.assertIn("return x.mux ||", body)
