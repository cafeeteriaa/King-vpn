from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HealthyFolderPolicyTest(unittest.TestCase):
    def test_capacity_is_fifty_thousand(self):
        source = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
        self.assertIn("static const int _resMax = 50000;", source)

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


if __name__ == "__main__":
    unittest.main()
