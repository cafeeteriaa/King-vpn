from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeFailoverDurabilityTests(unittest.TestCase):
    def test_no_fixed_backup_count_cap_remains(self):
        native = (ROOT / "android_src" / "KingVpnService.java").read_text(encoding="utf-8")
        dart = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
        self.assertNotIn("MAX_BACKUPS", native)
        self.assertNotIn("out.size() <", native)
        self.assertNotIn("out.length >= 8", dart)
        self.assertIn("for (int i = 0; i < arr.length(); i++)", native)

    def test_native_failover_state_is_durable_jsonl(self):
        native = (ROOT / "android_src" / "KingVpnService.java").read_text(encoding="utf-8")
        self.assertIn("king_failover_state.jsonl", native)
        self.assertIn("BufferedWriter", native)
        self.assertIn("writer.newLine()", native)
        self.assertIn("stream.getFD().sync()", native)
        self.assertIn("Os.rename(temp.getAbsolutePath(), target.getAbsolutePath())", native)

    def test_legacy_state_migrates_and_corrupt_rows_are_isolated(self):
        native = (ROOT / "android_src" / "KingVpnService.java").read_text(encoding="utf-8")
        self.assertIn("One-time migration from the legacy JSON array", native)
        self.assertIn('sp.getString("list", "")', native)
        self.assertIn("skipping malformed failover state row", native)
        self.assertIn('sp.edit().putInt("idx", currentIdx)', native)

    def test_explicit_stop_clears_durable_failover_state(self):
        native = (ROOT / "android_src" / "KingVpnService.java").read_text(encoding="utf-8")
        self.assertIn('getSharedPreferences(PREFS, MODE_PRIVATE).edit().clear().commit()', native)
        self.assertIn('File state = failoverStateFile()', native)
        self.assertIn('if (state.exists() && !state.delete())', native)


if __name__ == "__main__":
    unittest.main()
