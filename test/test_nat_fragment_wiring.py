import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class NatFragmentWiringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / "lib" / "nat_ultra.dart").read_text(encoding="utf-8")

    def test_fragment_is_attached_to_freedom_and_proxy_outbound(self):
        start = self.source.index("String _natFrag(")
        end = self.source.index("String _natMux(", start)
        body = self.source[start:end]
        self.assertIn("'protocol': 'freedom'", body)
        self.assertIn("'fragment': {", body)
        self.assertIn("'packets': p[2]", body)
        self.assertIn("'length': lengthRange", body)
        self.assertIn("'interval': intervalRange", body)
        self.assertIn("so['dialerProxy'] = 'frag-out'", body)
        self.assertIn("st['sockopt'] = so", body)

    def test_fragment_rejects_non_tls_transport_security(self):
        start = self.source.index("String _natFrag(")
        end = self.source.index("String _natMux(", start)
        body = self.source[start:end]
        self.assertIn("if (sec != 'tls' && sec != 'reality') return cfg;", body)
        self.assertIn("if (proxy == null) return cfg;", body)
        self.assertIn("if (st is! Map) return cfg;", body)

    def test_fragment_jitter_is_repeatable_from_supplied_seed(self):
        start = self.source.index("String _natFrag(")
        end = self.source.index("String _natMux(", start)
        body = self.source[start:end]
        self.assertIn("Random(seed ^ (fi << 8) ^ (noiseK << 16))", body)
        self.assertIn("final lengthRange = jitter(p[0], 6)", body)
        self.assertIn("final intervalRange = jitter(p[1], 3)", body)

    def test_fragment_specs_are_only_applied_to_secure_servers(self):
        start = self.source.index("bool _natAppliesF")
        end = self.source.index("bool _natChangesAddr", start)
        body = self.source[start:end]
        self.assertIn("(x.fp != null || x.alpn != null || x.frag != null || x.noise)", body)
        self.assertIn("!f.sec", body)
