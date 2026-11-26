import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class PublicSingBoxProtocolsSourceGuard(unittest.TestCase):
    def test_hysteria2_and_tuic_links_are_discovered_and_parsed(self):
        main = (ROOT / "lib" / "main.dart").read_text()
        feeds = (ROOT / "lib" / "npv_am_extras.dart").read_text()
        self.assertIn("hysteria2|hy2|tuic", main)
        self.assertIn("sv.singBox = true", main)
        self.assertIn("hysteria2.txt", feeds)
        self.assertIn("tuic.txt", feeds)
        self.assertIn("hysteria2|hy2|tuic", feeds)

    def test_libbox_is_the_execution_path_and_not_xray_config_generation(self):
        main = (ROOT / "lib" / "main.dart").read_text()
        core = (ROOT / "lib" / "king_sing_box_core.dart").read_text()
        self.assertIn("KingSingBoxCore.instance.connect(s.link)", main)
        self.assertIn("KingSingBoxCore.instance.disconnect()", main)
        self.assertIn("bool get isConnected", core)
        self.assertIn("if (s.singBox) {", main)
        self.assertIn("final badCfg = s.singBox ? null : coreUnsupportedReason(s.link);", main)
        self.assertIn("if (!s.isXray || !nationalMode) return false;", main)

    def test_libbox_is_stopped_before_another_tun_engine_starts(self):
        main = (ROOT / "lib" / "main.dart").read_text()
        start = main.index("Future<void> _stopCoreInner()")
        end = main.index("// ---------- cache ----------", start)
        stop = main[start:end]
        self.assertIn("final wasSingBoxUp = _kingSingBoxActive;", stop)
        self.assertIn("await KingSingBoxCore.instance.disconnect();", stop)
        self.assertIn("wasWireGuardUp || wasSingBoxUp || !wasUp", stop)

    def test_udp_protocols_are_not_dropped_by_tcp_prefilter_or_xray_delay_api(self):
        main = (ROOT / "lib" / "main.dart").read_text()
        self.assertIn("if (s.singBox) {\n        alive.add(s);", main)
        self.assertIn("final singBoxBatch = batch.where((s) => s.singBox).toList();", main)
        self.assertIn("final tunnelMode = s.singBox || (viaVpn && row != 'r:ai');", main)
        self.assertIn("await _testBatchSeq(singBoxPending, enough, keepUp: false, row: row);", main)
        self.assertIn("viaCore && !_kingWireGuardActive && !_kingSingBoxActive", main)
        self.assertIn("(viaCore || !direct) && !_kingWireGuardActive && !_kingSingBoxActive", main)
        self.assertIn("if (_kingWireGuardActive || _kingSingBoxActive)", main)


if __name__ == "__main__":
    unittest.main()
