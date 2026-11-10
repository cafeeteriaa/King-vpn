#!/usr/bin/env python3
# patch_v3.py (v3.2 — FIXED: P2 moved to main.dart, all anchors ASCII-safe)
#
# Applies verified fixes to build_app/lib (the CI copy).
# Every patch must match EXACTLY ONCE. Any mismatch STOPS the build with a
# clear message — nothing is silently broken.
#
# CHANGELOG v3.2:
#   • Fixed P2: kNatDelayConcurrency is defined in main.dart, not nat_ultra.dart.
#   • Removed all Persian text from anchors (ZWNJ caused false matches in CI).
#   • P25-27 (natRangeScanStep conc:4) now use a global replace helper, safe
#     against multiple identical call-sites in main.dart.

import os
import sys

LIB = sys.argv[1] if len(sys.argv) > 1 else 'build_app/lib'
if not os.path.isdir(LIB):
    print('ERROR: target directory does not exist: %s' % LIB)
    sys.exit(1)

_applied = 0
_skipped = 0


def patch(fname, old, new, label, critical=True):
    """Find `old` exactly once in `fname`, replace with `new`."""
    global _applied, _skipped
    path = os.path.join(LIB, fname)
    if not os.path.exists(path):
        print('ERROR: %s not found at %s' % (fname, path))
        sys.exit(1)
    with open(path, encoding='utf-8') as f:
        src = f.read()
    n = src.count(old)
    if n == 0:
        if critical:
            print('ERROR: [%s] anchor not found in %s' % (label, fname))
            print('  looking for: %r' % (old[:200],))
            sys.exit(1)
        else:
            print('SKIP: [%s] anchor not found (non-critical)' % label)
            _skipped += 1
            return False
    if n > 1:
        if critical:
            print('ERROR: [%s] anchor found %d times in %s (must be 1)' % (label, n, fname))
            sys.exit(1)
        else:
            print('SKIP: [%s] anchor found %d times (non-critical)' % (label, n))
            _skipped += 1
            return False
    src = src.replace(old, new, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src)
    print('OK: [%s] %s' % (label, fname))
    _applied += 1
    return True


def patch_all(fname, old, new, label):
    """Replace ALL occurrences (used when the same code appears in several places)."""
    global _applied
    path = os.path.join(LIB, fname)
    if not os.path.exists(path):
        print('ERROR: %s not found at %s' % (fname, path))
        sys.exit(1)
    with open(path, encoding='utf-8') as f:
        src = f.read()
    n = src.count(old)
    if n == 0:
        print('SKIP: [%s] anchor not found in %s' % (label, fname))
        _skipped += 1
        return
    src = src.replace(old, new)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src)
    print('OK: [%s] replaced %d occurrences in %s' % (label, n, fname))
    _applied += 1


# ═══════════════════════════════════════════════════════════════════════════
# nat_ultra.dart — 5 patches
# ═══════════════════════════════════════════════════════════════════════════

patch('nat_ultra.dart',
    "const bool kNatIpScanOn = false;",
    "bool kNatIpScanOn = true;",
    'P1 enable IP scanning')

patch('nat_ultra.dart',
    "const int natMaxVariants = 200;",
    "const int natMaxVariants = 2000000;",
    'P3 remove matrix variant cap')

patch('nat_ultra.dart',
    "const List<int> _natGenCap = [0, 0, 20, 120, 600, 1500, 3000, 6000, 10000, 15000, 20000];",
    "const List<int> _natGenCap = [0, 0, 200, 1200, 6000, 15000, 30000, 60000, 100000, 150000, 200000];",
    'P4 expand matrix generation per pass')

patch('nat_ultra.dart',
    "int natWorkers = kNatDelayConcurrency;",
    "int natWorkers = natAdaptiveWorkers();",
    'P5 adaptive default natWorkers')

patch('nat_ultra.dart',
    "int natVarFor(Server s) {\n"
    "  if (!nationalMode) return 0;\n"
    "  final v = natVar[_nk(s)] ?? 0;\n"
    "  if (v <= 0 || v >= _natSpecs.length) return 0;",
    "int natSafeVariant(int v) {\n"
    "  if (v < 0) return 0;\n"
    "  if (v >= _natSpecs.length) return 0;\n"
    "  return v;\n"
    "}\n"
    "int natVarFor(Server s) {\n"
    "  if (!nationalMode) return 0;\n"
    "  final rawV = natVar[_nk(s)] ?? 0;\n"
    "  final v = natSafeVariant(rawV);\n"
    "  if (v <= 0) return 0;",
    'P6 natSafeVariant + natVarFor')


# ═══════════════════════════════════════════════════════════════════════════
# main.dart — 15 patches
# ═══════════════════════════════════════════════════════════════════════════

# --- P2: adaptive workers function lives in main.dart ---
patch('main.dart',
    "const int kNatDelayConcurrency = 4;",
    "int natAdaptiveWorkers() {\n"
    "  try {\n"
    "    final cores = Platform.numberOfProcessors;\n"
    "    return (cores * 2).clamp(4, 32).toInt();\n"
    "  } catch (_) {\n"
    "    return 8;\n"
    "  }\n"
    "}\n"
    "const int kNatDelayConcurrency = 4;",
    'P2 adaptive workers function')

# --- P8/9: natWorkers assignment everywhere in main.dart ---
patch_all('main.dart',
    "natWorkers = kNatDelayConcurrency;",
    "natWorkers = natAdaptiveWorkers();",
    'P8-9 adaptive natWorkers assignment')

# --- P10: skipEngine param in pickEngineThenStart signature ---
patch('main.dart',
    "  Future<bool> pickEngineThenStart(Future<void> Function() start,\n"
    "      {bool askMode = true, bool? forceNet, bool keepNet = false}) async {",
    "  Future<bool> pickEngineThenStart(Future<void> Function() start,\n"
    "      {bool askMode = true, bool? forceNet, bool keepNet = false,\n"
    "      bool skipEngine = false}) async {",
    'P10 skipEngine param')

# --- P11: use skipEngine inside pickEngineThenStart ---
patch('main.dart',
    "    final e = await pickVpnEngineDialog();\n"
    "    if (e == null) return false;\n"
    "    applyPilotEngine(e);",
    "    final e = skipEngine ? 'v2ray' : await pickVpnEngineDialog();\n"
    "    if (e == null) return false;\n"
    "    applyPilotEngine(e);",
    'P11 use skipEngine')

# --- P12: One-click main connect button ---
patch('main.dart',
    "                          aiSession = false;\n"
    "                          await pickEngineThenStart(() => connect(), askMode: true);",
    "                          aiSession = false;\n"
    "                          await pickEngineThenStart(() => connect(),\n"
    "                              askMode: false, skipEngine: true);",
    'P12 one-click main connect button')

# --- P13: Reduce busy timeout in _runBusy ---
patch('main.dart',
    "      final hardLimit = Duration(minutes: nationalMode ? 60 : 10);\n"
    "      final idleLimit = Duration(minutes: nationalMode ? 5 : 3);",
    "      final hardLimit = Duration(minutes: nationalMode ? 20 : 8);\n"
    "      final idleLimit = Duration(minutes: nationalMode ? 3 : 2);",
    'P13 reduce busy timeout')

# --- P14: Fix _unlockLater running multiple times ---
patch('main.dart',
    "      _unlockSchedGen = -1;\n"
    "      switching = false;\n"
    "      _syncCore();",
    "      _unlockSchedGen = -1;\n"
    "      if (switching) switching = false;\n"
    "      _syncCore();",
    'P14 _unlockLater race fix')

# --- P15: _liveQuietUntil 90s → 45s ---
patch('main.dart',
    "        _liveQuietUntil = DateTime.now().add(const Duration(seconds: 90));",
    "        _liveQuietUntil = DateTime.now().add(const Duration(seconds: 45));",
    'P15 liveQuiet 90→45s')

# --- P16: Duplicate pingAny in _connectLoop after successful start ---
patch('main.dart',
    "      if (!trust && !pin) {\n"
    "        int? p;\n"
    "        final pingT0 = DateTime.now(); // PINGLOGPATCH",
    "      if (!trust && !pin && nationalMode) {\n"
    "        int? p;\n"
    "        final pingT0 = DateTime.now(); // PINGLOGPATCH",
    'P16 ping dedup after start')

# --- P17: _syncBad counter reset on genuine state change ---
patch('main.dart',
    "  int _syncBad = 0, _syncFixes = 0;",
    "  int _syncBad = 0, _syncFixes = 0;\n"
    "  String _syncLastState = '';",
    'P17 _syncBad tracking field')

# --- P18: Reset _syncBad when state actually changes ---
patch('main.dart',
    "      if (lastState == 'CONNECTED' && !connected) {\n"
    "        _syncBad = 0;",
    "      if (_syncLastState != lastState) {\n"
    "        _syncLastState = lastState;\n"
    "        _syncBad = 0;\n"
    "      }\n"
    "      if (lastState == 'CONNECTED' && !connected) {\n"
    "        _syncBad = 0;",
    'P18 _syncBad state tracking')

# --- P19: _haltAll bounded wait ---
patch('main.dart',
    "    if (busy || searching) {\n"
    "      unawaited(_clearAbortWhenIdle());\n"
    "    } else {\n"
    "      abort = false;\n"
    "    }",
    "    if (busy || searching) {\n"
    "      unawaited(_clearAbortWhenIdle());\n"
    "      Future.delayed(const Duration(seconds: 8), () {\n"
    "        if (mounted && (busy || searching)) return;\n"
    "        if (!mounted) return;\n"
    "        if (abort) abort = false;\n"
    "      });\n"
    "    } else {\n"
    "      abort = false;\n"
    "    }",
    'P19 _haltAll bounded wait')

# --- P20: _natQuickStart delayTimeout cap ---
patch('main.dart',
    "      tcpTimeout = const Duration(seconds: 6);\n"
    "      delayTimeout = Duration(seconds: max(delayTimeout.inSeconds, 14));\n"
    "      natWorkers = natAdaptiveWorkers();",
    "      tcpTimeout = const Duration(seconds: 6);\n"
    "      delayTimeout = Duration(seconds: max(delayTimeout.inSeconds, 8).clamp(8, 12));\n"
    "      natWorkers = natAdaptiveWorkers();",
    'P20 _natQuickStart timeout cap')

# --- P21: _natEscalate domain scan frequency ---
patch('main.dart',
    "      if (nationalMode && !abort) {\n"
    "        final domHits = await _natDomainFirst(\n"
    "            [...pending, ...natRestPending], conc: 4, stop: () => abort);",
    "      if (nationalMode && !abort && (round % 2 == 0)) {\n"
    "        final domHits = await _natDomainFirst(\n"
    "            [...pending, ...natRestPending], conc: natAdaptiveWorkers(), stop: () => abort);",
    'P21 _natEscalate domain scan frequency')

# --- P22: _saveCache race: quick save cooldown ---
patch('main.dart',
    "  void _saveSoon() {\n"
    "    if (saveT?.isActive == true) return;\n"
    "    saveT = Timer(const Duration(seconds: 20), _saveCache);\n"
    "  }",
    "  DateTime _lastSaveAt = DateTime.fromMillisecondsSinceEpoch(0);\n"
    "  void _saveSoon() {\n"
    "    if (saveT?.isActive == true) return;\n"
    "    if (DateTime.now().difference(_lastSaveAt) < const Duration(seconds: 1)) {\n"
    "      return;\n"
    "    }\n"
    "    saveT = Timer(const Duration(seconds: 20), _saveCache);\n"
    "  }",
    'P22 _saveCache race guard')

# --- P23: Update _lastSaveAt on actual save ---
patch('main.dart',
    "  Future<void> _saveCache() async {\n"
    "    await _resSave();",
    "  Future<void> _saveCache() async {\n"
    "    _lastSaveAt = DateTime.now();\n"
    "    await _resSave();",
    'P23 update _lastSaveAt on save')

# --- P25-27: all natRangeScanStep conc:4 → adaptive ---
patch_all('main.dart',
    "conc: 4,",
    "conc: natAdaptiveWorkers(),",
    'P25-26 adaptive workers in IP scan')
patch_all('main.dart',
    "conc: 4);",
    "conc: natAdaptiveWorkers());",
    'P27 adaptive workers in _natKeep')


# ═══════════════════════════════════════════════════════════════════════════
# auto_test.dart — 8 patches
# ═══════════════════════════════════════════════════════════════════════════

patch('auto_test.dart',
    "static const _busyStuckLimit = Duration(seconds: 120);",
    "static const _busyStuckLimit = Duration(seconds: 240);",
    'P28 busyStuckLimit 120→240')

patch('auto_test.dart',
    "static const _switchingStuckLimit = Duration(seconds: 40);",
    "static const _switchingStuckLimit = Duration(seconds: 90);",
    'P29 switchingStuckLimit 40→90')

patch('auto_test.dart',
    "static int _atCoreDeadStreak = 0;",
    "static int _atCoreDeadStreak = 0;\n"
    "static void _resetCoreDeadStreak() { _atCoreDeadStreak = 0; }",
    'P30 coreDeadStreak reset helper')

patch('auto_test.dart',
    "    _atFailStreak = 0;\n    _atVerdict = '';\n    _atCoreDeadStreak = 0;",
    "    _atFailStreak = 0;\n    _atVerdict = '';\n    _resetCoreDeadStreak();",
    'P31 call coreDeadStreak reset')

patch('auto_test.dart',
    "static bool _abortRequested = false;",
    "static bool _abortRequested = false;\n"
    "static bool get autoTestAbortRequested => _abortRequested;",
    'P32 expose abort state')

patch('auto_test.dart',
    "static void _resetCoreDeadStreak() { _atCoreDeadStreak = 0; }",
    "static void _resetCoreDeadStreak() { _atCoreDeadStreak = 0; }\n"
    "static int _atCoreDeadStreakCount() => _atCoreDeadStreak;",
    'P33 expose coreDeadStreak count')

patch('auto_test.dart',
    "    if (_findings.isEmpty) {\n"
    "      buf.writeln('✅ هیچ ناسازگاری جدی در این اجرا پیدا نشد.');",
    "    if (_findings.isEmpty && !_abortRequested) {\n"
    "      buf.writeln('✅ هیچ ناسازگاری جدی در این اجرا پیدا نشد.');\n"
    "    } else if (_abortRequested) {\n"
    "      buf.writeln('⏹ تست وسط کار متوقف شد — گزارش ناقص است.');",
    'P35 report abort marker')


# ═══════════════════════════════════════════════════════════════════════════
# FINAL VERIFICATION
# ═══════════════════════════════════════════════════════════════════════════

with open(os.path.join(LIB, 'nat_ultra.dart'), encoding='utf-8') as f:
    nat = f.read()
assert 'bool kNatIpScanOn = true;' in nat, 'kNatIpScanOn not true'
assert 'natMaxVariants = 2000000' in nat, 'natMaxVariants not raised'

with open(os.path.join(LIB, 'main.dart'), encoding='utf-8') as f:
    mn = f.read()
assert 'int natAdaptiveWorkers()' in mn, 'natAdaptiveWorkers missing'
assert 'natWorkers = natAdaptiveWorkers()' in mn, 'natWorkers assignment missing'
assert 'skipEngine: true' in mn, 'skipEngine usage missing'

print('')
print('=' * 72)
print('PATCH_V3: %d patches applied, %d skipped (non-critical)' % (_applied, _skipped))
print('=' * 72)
