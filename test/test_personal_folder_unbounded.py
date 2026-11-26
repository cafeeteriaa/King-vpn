from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PersonalFolderUnboundedInventoryTests(unittest.TestCase):
    def test_inventory_has_no_fixed_count_caps(self):
        source = (ROOT / "lib" / "personal_folder.dart").read_text(encoding="utf-8")
        self.assertNotIn("kPersonalFolderCap", source)
        self.assertNotIn("kPersonalShowCap", source)
        self.assertNotIn("length >=", source)
        self.assertIn("append-only", source)
        self.assertIn("personal_folder.jsonl", source)

    def test_journal_supports_incremental_add_remove_and_legacy_migration(self):
        source = (ROOT / "lib" / "personal_folder.dart").read_text(encoding="utf-8")
        self.assertIn("FileMode.append", source)
        self.assertIn("row['op'] == 'add'", source)
        self.assertIn("row['op'] == 'remove'", source)
        self.assertIn("prefs.remove(_kPersonalFolderPref)", source)
        self.assertIn("LineSplitter()", source)

    def test_main_path_uses_entire_personal_folder(self):
        source = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
        self.assertIn("List<Server> personalFolderServers()", source)
        self.assertNotIn("personalFolderServers(max:", source)
        self.assertNotIn("personalFolderServers({int max", source)
        self.assertIn("final nW = max(1, _delayGate.max);", source)
        self.assertIn("if (failed.isNotEmpty)", source)
        self.assertNotIn("failed.length < list.length", source)

    def test_personal_servers_remain_excluded_from_shared_healthy_inventory(self):
        source = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
        self.assertIn("Never mix its entries into the personal-server folder", source)
        self.assertIn("_purgePersonalLeaks()", source)
        self.assertIn("server.personal = true", source)


if __name__ == "__main__":
    unittest.main()
