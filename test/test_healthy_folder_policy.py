from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HealthyFolderPolicyTest(unittest.TestCase):
    def test_healthy_folder_has_no_fixed_count_ceiling_or_eviction(self):
        source = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
        start = source.index("void _resAdd(Server srv)")
        end = source.index("// SRCSPLIT:", start)
        block = source[start:end]
        self.assertNotIn("_resMax", source)
        self.assertNotIn("_resMap.length >=", block)
        self.assertNotIn("oldest", block.lower())
        self.assertIn("_resMap[srv.key] = e;", block)

    def test_healthy_folder_uses_app_private_file_snapshot(self):
        source = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
        start = source.index("Future<File> _resDataFile()")
        end = source.index("// a server passed a real test", start)
        block = source[start:end]
        self.assertIn("KingVPN/HealthyServers", block)
        self.assertIn("await temp.writeAsString(jsonEncode(_resSnapshot()), flush: true)", block)
        self.assertIn("await temp.rename(file.path)", block)
        self.assertIn("One-time migration from the previous SharedPreferences snapshot", block)

    def test_48_hour_recheck_is_not_gated_by_national_mode(self):
        source = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
        start = source.index("Future<void> _resDaily({bool force = false}) async {")
        end = source.index("String _resAgo(", start)
        body = source[start:end]
        self.assertIn("Duration(hours: 48)", source)
        self.assertNotIn("!nationalMode", body)
        self.assertIn("if (netDead)", body)
        self.assertIn("nothing is deleted when the whole network is down", body)

    def test_small_inventory_outage_does_not_prune_all_entries(self):
        source = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
        start = source.index("Future<void> _resDaily({bool force = false}) async {")
        end = source.index("String _resAgo(", start)
        body = source[start:end]
        self.assertIn("if (tested > 0 && passed == 0)", body)
        self.assertNotIn("tested >= 5 && passed == 0", body)
        self.assertIn("for (final e in dead)", body)


if __name__ == "__main__":
    unittest.main()
