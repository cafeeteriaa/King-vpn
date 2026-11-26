from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class KingHealDurableLearningTests(unittest.TestCase):
    def test_heal_learning_is_persisted_as_an_append_only_journal(self):
        source = (ROOT / "lib" / "king_heal.dart").read_text(encoding="utf-8")
        memory = source.split("class _HealMemory {", 1)[1].split(
            "final _healMem =", 1
        )[0]
        self.assertIn("king_heal_learning.jsonl", memory)
        self.assertIn("FileMode.append", memory)
        self.assertIn("FileLock.exclusive", memory)
        self.assertIn("_knownActions.contains(action)", memory)
        self.assertIn("file.openRead()", memory)
        self.assertIn("await for (final line in", memory)
        self.assertNotIn("readAsLines", memory)
        self.assertNotIn("recent.length >", memory)

    def test_learning_uses_verified_data_plane_result_not_action_return(self):
        source = (ROOT / "lib" / "king_heal.dart").read_text(encoding="utf-8")
        action = source.index("ok = await _healAct")
        verified = source.index("final fixed = dataPlaneOk")
        learned = source.index("await _healMem.remember(plan.$1, fixed)")
        self.assertLess(action, verified)
        self.assertLess(verified, learned)
        self.assertNotIn("_healMem.remember(plan.$1, ok)", source)

    def test_learning_restore_runs_before_self_heal_planning(self):
        source = (ROOT / "lib" / "king_heal.dart").read_text(encoding="utf-8")
        restore = source.index("await _healMem.load();")
        sense = source.index("final signals = await _healSense();")
        plan = source.index("final plan = _healPlan(top);")
        self.assertLess(restore, sense)
        self.assertLess(sense, plan)


if __name__ == "__main__":
    unittest.main()
