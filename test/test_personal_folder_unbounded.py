from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PersonalFolderUnboundedInventoryTests(unittest.TestCase):
    def test_inventory_has_no_fixed_count_caps(self):
        source = (ROOT / "lib" / "personal_folder.dart").read_text(encoding="utf-8")
        self.assertNotIn("kPersonalFolderCap", source)
        self.assertNotIn("kPersonalShowCap", source)
        self.assertNotIn("length >=", source)
        self.assertIn("personal_servers.jsonl", source)
        self.assertIn("سقف تعداد", source)

    def test_journal_supports_incremental_add_remove_and_legacy_migration(self):
        source = (ROOT / "lib" / "personal_folder.dart").read_text(encoding="utf-8")
        self.assertIn("file.open(mode: FileMode.append)", source)
        self.assertIn("FileLock.exclusive", source)
        self.assertIn("decoded['op']", source)
        self.assertIn("op == 'add'", source)
        self.assertIn("op == 'remove'", source)
        self.assertIn("p.remove(_kPersonalFolderPref)", source)
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



    def test_personal_ping_and_failover_cover_every_entry(self):
        source = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
        self.assertIn("gen != _personalPingGen || AutoTestEngine.autoTestAbortRequested", source)
        self.assertIn("doneCount % 128 == 0 || doneCount == list.length", source)
        self.assertIn("for (var index = i; index < _personalRanked.length; index++)", source)
        self.assertNotIn("_personalConnectAt(i + 1)", source)

    def test_personal_inventory_is_not_duplicated_in_preferences(self):
        source = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
        self.assertNotIn("setStringList('personal_shown_v1'", source)
        self.assertIn("p.remove('personal_shown_v1')", source)
        self.assertIn("rowSaved == 'p:personal'", source)

    def test_busy_wrapper_has_no_global_operation_deadline(self):
        source = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
        self.assertNotIn("hardLimit", source)
        self.assertNotIn("idle-or-hard-cap", source)

    def test_auto_test_has_a_separate_personal_server_stage(self):
        source = (ROOT / "lib" / "auto_test.dart").read_text(encoding="utf-8")
        self.assertIn("Future<void> _atItemPersonal()", source)
        self.assertIn("(_atItemNames[11], _atItemPersonal)", source)
        self.assertIn("connRow == 'p:personal'", source)

if __name__ == "__main__":
    unittest.main()
