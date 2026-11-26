from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "lib" / "auto_test.dart").read_text(encoding="utf-8")


class AutoTestFullCoverageTests(unittest.TestCase):
    def test_no_global_wall_clock_cutoff(self):
        for marker in (
            "_testDuration",
            "_atSearchCap",
            "_atMatrixCap",
            "_atSubstBudget",
            "_endT",
        ):
            self.assertNotIn(marker, SOURCE)
        self.assertIn("توقف دستی", SOURCE)

    def test_all_existing_connection_paths_are_in_the_run_plan(self):
        plan = SOURCE.split("final steps = <(String, Future<void> Function())>[", 1)[1].split(
            "];", 1
        )[0]
        for marker in (
            "_atItemGlobal",
            "_atItemFolder",
            "_atItemNational",
            "_atItemNatModes",
            "_atItemOffline",
            "_atItemOnline",
            "_atItemProto(5, 'vmess')",
            "_atItemProto(6, 'vless')",
            "_atItemProto(7, 'trojan')",
            "_atItemProto(8, 'ss')",
            "_atItemCountry(9)",
            "_atItemAiPilot(10)",
            "_atItemSubst",
            "_atScenarioReconnectStorm",
            "_atScenarioMidConnectAbort",
            "_atScenarioServerSwap",
            "_atScenarioLongStable",
        ):
            self.assertIn(marker, plan)

    def test_report_lists_all_existing_paths(self):
        active = SOURCE.split("static List<String> get _atActiveNames", 1)[1].split(
            "static const String _atSearchName", 1
        )[0]
        for index in range(11):
            self.assertIn(f"_atItemNames[{index}]", active)
        self.assertIn("_atSubstName", active)

    def test_national_discovery_runs_until_real_queue_exhaustion(self):
        method = SOURCE.split("Future<void> _atItemNational()", 1)[1].split(
            "Future<void> _atItemNatModes()", 1
        )[0]
        self.assertIn("natRound >= 2 && pending.isEmpty && !searching && !busy", method)
        self.assertIn("lastIdleRestart", method)
        self.assertNotIn("testDuration", method)
        self.assertNotIn("elapsed >", method)

    def test_every_defined_matrix_level_is_attempted_without_time_cutoff(self):
        method = SOURCE.split("Future<void> _atItemNatModes()", 1)[1].split(
            "Future<void> _atItemOffline()", 1
        )[0]
        self.assertIn("for (var lvl = 0; lvl <= 10; lvl++)", method)
        self.assertNotIn("matrixEnd", method)
        self.assertNotIn("NATMODES-TIME", method)

    def test_substitution_covers_all_servers_and_compatible_modes(self):
        method = SOURCE.split("Future<void> _atItemSubst()", 1)[1].split(
            "Future<void> _atItemNatModes()", 1
        )[0]
        for marker in ("_atSubstServers", "_atSubstPerServer", ".take(_atSubst"):
            self.assertNotIn(marker, method)
        self.assertIn("healthy = _usable().toList()", method)
        self.assertIn("untried.where((v) => _natAppliesF(f, v)).toList()", method)

    def test_diagnostic_samples_are_not_silently_truncated(self):
        self.assertNotIn("_samples.length > 500", SOURCE)
        self.assertIn("نمونه‌های ثبت‌شده: ${_samples.length}", SOURCE)

    def test_progress_tracks_completed_stages_not_elapsed_minutes(self):
        self.assertIn("_atCompletedSteps / _atTotalSteps", SOURCE)
        self.assertNotIn("now.difference(_startedAt!).inMilliseconds", SOURCE)


if __name__ == "__main__":
    unittest.main()
