from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
PILOT = (ROOT / "lib" / "iran_ai_extras.dart").read_text(encoding="utf-8")


def test_home_has_dedicated_smart_pilot_entry():
    assert "Future<void> _openPilotMode() async" in MAIN
    assert "label: const Text('خلبان هوشمند • انتخاب مسیر اتصال')" in MAIN
    assert "onPressed: (busy || switching) ? null : _openPilotMode" in MAIN


def test_pilot_entry_uses_existing_independent_mode_picker():
    body = MAIN.split("Future<void> _openPilotMode() async", 1)[1].split(
        "@override\n  Widget build(BuildContext context)", 1
    )[0]
    assert "_askOnlineOfflineMode()" in body
    assert "await connect();" in body
    picker = PILOT.split("Future<bool> _askOnlineOfflineMode() async", 1)[1]
    assert "mode == 'personal'" in picker
    assert "mode == 'offline'" in picker


def test_old_implicit_pilot_row_and_fixed_waiting_display_cap_are_gone():
    assert "Widget searchAllRow(VoidCallback onTap)" not in MAIN
    assert "rows.addAll(waiting.take(30));" not in MAIN
    assert "rows.addAll(waiting);" in MAIN
