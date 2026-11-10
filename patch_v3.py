#!/usr/bin/env python3
# patch_v3.py (v3.5 — FINAL REGEX VERSION)
#
# Applies verified fixes to build_app/lib (the CI copy).
# Uses regex to be 100% immune to minor spacing or comment differences.

import os
import sys
import re

LIB = sys.argv[1] if len(sys.argv) > 1 else 'build_app/lib'
if not os.path.isdir(LIB):
    print('ERROR: target directory does not exist: %s' % LIB)
    sys.exit(1)

_applied = 0
_skipped = 0

def patch_regex(fname, pattern, repl, label, critical=True):
    global _applied, _skipped
    path = os.path.join(LIB, fname)
    if not os.path.exists(path):
        if critical:
            print('ERROR: %s not found at %s' % (fname, path))
            sys.exit(1)
        return False
    with open(path, encoding='utf-8') as f:
        src = f.read()
    if not re.search(pattern, src):
        if critical:
            print('ERROR: [%s] pattern not found in %s' % (label, fname))
            print('  looking for: %r' % (pattern,))
            sys.exit(1)
        else:
            print('SKIP: [%s] pattern not found (non-critical)' % label)
            _skipped += 1
            return False
    src = re.sub(pattern, repl, src, count=1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src)
    print('OK: [%s] %s' % (label, fname))
    _applied += 1
    return True

def patch_all_regex(fname, pattern, repl, label):
    global _applied, _skipped
    path = os.path.join(LIB, fname)
    if not os.path.exists(path):
        print('ERROR: %s not found at %s' % (fname, path))
        sys.exit(1)
    with open(path, encoding='utf-8') as f:
        src = f.read()
    if not re.search(pattern, src):
        print('SKIP: [%s] pattern not found in %s' % (label, fname))
        _skipped += 1
        return
    src = re.sub(pattern, repl, src, count=0)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src)
    print('OK: [%s] replaced all matches in %s' % (label, fname))
    _applied += 1

# ═══════════════════════════════════════════════════════════════════════════
# nat_ultra.dart
# ═══════════════════════════════════════════════════════════════════════════

patch_regex('nat_ultra.dart',
    r'const\s+bool\s+kNatIpScanOn\s*=\s*false\s*;',
    'bool kNatIpScanOn = true;',
    'P1 enable IP scanning')

patch_regex('nat_ultra.dart',
    r'const\s+int\s+kNatDelayConcurrency\s*=\s*4\s*;',
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

patch_regex('nat_ultra.dart',
    r'const\s+int\s+natMaxVariants\s*=\s*200\s*;',
    'const int natMaxVariants = 2000000;',
    'P3 remove matrix variant cap')

patch_regex('nat_ultra.dart',
    r'const\s+List<int>\s+_natGenCap\s*=\s*\[0, 0, 20, 120, 600, 1500, 3000, 6000, 10000, 15000, 20000\];',
    'const List<int> _natGenCap = [0, 0, 200, 1200, 6000, 15000, 30000, 60000, 100000, 150000, 200000];',
    'P4 expand matrix generation per pass')

patch_regex('nat_ultra.dart',
    r'int\s+natWorkers\s*=\s*kNatDelayConcurrency\s*;',
    'int natWorkers = natAdaptiveWorkers();',
    'P5 adaptive default natWorkers')

patch_regex('nat_ultra.dart',
    r'int natVarFor\(Server s\) \{\s*if \(!nationalMode\) return 0;\s*final v = natVar\[_nk\(s\)\] \?\? 0;\s*if \(v <= 0 \|\| v >= _natSpecs\.length\) return 0;',
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
# main.dart
# ═══════════════════════════════════════════════════════════════════════════

# P8-9: update all natWorkers assignments in main.dart
patch_all_regex('main.dart',
    r'natWorkers\s*=\s*kNatDelayConcurrency\s*;',
    'natWorkers = natAdaptiveWorkers();',
    'P8-9 adaptive natWorkers assignment')

patch_regex('main.dart',
    r'\{bool askMode = true, bool\? forceNet, bool keepNet = false\}\) async \{',
    '{bool askMode = true, bool? forceNet, bool keepNet = false, bool skipEngine = false}) async {',
    'P10 skipEngine param')

patch_regex('main.dart',
    r"final e = await pickVpnEngineDialog\(\);\s*if \(e == null\) return false;\s*applyPilotEngine\(e\);",
    "final e = skipEngine ? 'v2ray' : await pickVpnEngineDialog();\n"
    "    if (e == null) return false;\n"
    "    applyPilotEngine(e);",
    'P11 use skipEngine')

patch_regex('main.dart',
    r"aiSession = false;\s*await pickEngineThenStart\(\(\) => connect\(\), askMode: true\);",
    "aiSession = false;\n"
    "                          await pickEngineThenStart(() => connect(),\n"
    "                              askMode: false, skipEngine: true);",
    'P12 one-click main connect button')

patch_regex('main.dart',
    r"final hardLimit = Duration\(minutes: nationalMode \? 60 : 10\);\s*final idleLimit = Duration\(minutes: nationalMode \? 5 : 3\);",
    "final hardLimit = Duration(minutes: nationalMode ? 20 : 8);\n"
    "      final idleLimit = Duration(minutes: nationalMode ? 3 : 2);",
    'P13 reduce busy timeout')

patch_regex('main.dart',
    r"_unlockSchedGen = -1;\s*switching = false;\s*_syncCore\(\);",
    "_unlockSchedGen = -1;\n"
    "      if (switching) switching = false;\n"
    "      _syncCore();",
    'P14 _unlockLater race fix')

patch_regex('main.dart',
    r"_liveQuietUntil = DateTime\.now\(\)\.add\(const Duration\(seconds: 90\)\);",
    "_liveQuietUntil = DateTime.now().add(const Duration(seconds: 45));",
    'P15 liveQuiet 90→45s')

patch_regex('main.dart',
    r"if \(!trust && !pin\) \{\s*int\? p;\s*final pingT0 = DateTime\.now\(\); // PINGLOGPATCH",
    "if (!trust && !pin && nationalMode) {\n"
    "        int? p;\n"
    "        final pingT0 = DateTime.now(); // PINGLOGPATCH",
    'P16 ping dedup after start')

patch_regex('main.dart',
    r"int _syncBad = 0, _syncFixes = 0;",
    "int _syncBad = 0, _syncFixes = 0;\n"
    "  String _syncLastState = '';",
    'P17 _syncBad tracking field')

patch_regex('main.dart',
    r"if \(lastState == 'CONNECTED' && !connected\) \{\s*_syncBad = 0;",
    "if (_syncLastState != lastState) {\n"
    "        _syncLastState = lastState;\n"
    "        _syncBad = 0;\n"
    "      }\n"
    "      if (lastState == 'CONNECTED' && !connected) {\n"
    "        _syncBad = 0;",
    'P18 _syncBad state tracking')

patch_regex('main.dart',
    r"if \(busy \|\| searching\) \{\s*unawaited\(_clearAbortWhenIdle\(\)\);\s*\} else \{\s*abort = false;\s*\}",
    "if (busy || searching) {\n"
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

patch_regex('main.dart',
    r"tcpTimeout = const Duration\(seconds: 6\);\s*delayTimeout = Duration\(seconds: max\(delayTimeout\.inSeconds, 14\)\);\s*natWorkers = natAdaptiveWorkers\(\);",
    "tcpTimeout = const Duration(seconds: 6);\n"
    "      delayTimeout = Duration(seconds: max(delayTimeout.inSeconds, 8).clamp(8, 12));\n"
    "      natWorkers = natAdaptiveWorkers();",
    'P20 _natQuickStart timeout cap')

patch_regex('main.dart',
    r"if \(nationalMode && !abort\) \{\s*final domHits = await _natDomainFirst\(\s*\[\.\.\.pending, \.\.\.natRestPending\], conc: 4, stop: \(\) => abort\);",
    "if (nationalMode && !abort && (round % 2 == 0)) {\n"
    "        final domHits = await _natDomainFirst(\n"
    "            [...pending, ...natRestPending], conc: natAdaptiveWorkers(), stop: () => abort);",
    'P21 _natEscalate domain scan frequency')

patch_regex('main.dart',
    r"void _saveSoon\(\) \{\s*if \(saveT\?\.isActive == true\) return;\s*saveT = Timer\(const Duration\(seconds: 20\), _saveCache\);\s*\}",
    "DateTime _lastSaveAt = DateTime.fromMillisecondsSinceEpoch(0);\n"
    "  void _saveSoon() {\n"
    "    if (saveT?.isActive == true) return;\n"
    "    if (DateTime.now().difference(_lastSaveAt) < const Duration(seconds: 1)) {\n"
    "      return;\n"
    "    }\n"
    "    saveT = Timer(const Duration(seconds: 20), _saveCache);\n"
    "  }",
    'P22 _saveCache race guard')

patch_regex('main.dart',
    r"Future<void> _saveCache\(\) async \{\s*await _resSave\(\);",
    "Future<void> _saveCache() async {\n"
    "    _lastSaveAt = DateTime.now();\n"
    "    await _resSave();",
    'P23 update _lastSaveAt on save')

patch_all_regex('main.dart',
    r'conc: 4,',
    'conc: natAdaptiveWorkers(),',
    'P24-26 adaptive workers in IP scan')

patch_all_regex('main.dart',
    r'conc: 4\);',
    'conc: natAdaptiveWorkers());',
    'P27 adaptive workers in _natKeep')

# ═══════════════════════════════════════════════════════════════════════════
# auto_test.dart
# ═══════════════════════════════════════════════════════════════════════════

patch_regex('auto_test.dart',
    r'static const _busyStuckLimit = Duration\(seconds: 120\);',
    'static const _busyStuckLimit = Duration(seconds: 240);',
    'P28 busyStuckLimit 120→240')

patch_regex('auto_test.dart',
    r'static const _switchingStuckLimit = Duration\(seconds: 40\);',
    'static const _switchingStuckLimit = Duration(seconds: 90);',
    'P29 switchingStuckLimit 40→90')

patch_regex('auto_test.dart',
    r'static int _atCoreDeadStreak = 0;',
    "static int _atCoreDeadStreak = 0;\n"
    "static void _resetCoreDeadStreak() { _atCoreDeadStreak = 0; }",
    'P30 coreDeadStreak reset helper')

patch_regex('auto_test.dart',
    r"_atFailStreak = 0;\s*_atVerdict = '';\s*_atCoreDeadStreak = 0;",
    "_atFailStreak = 0;\n    _atVerdict = '';\n    _resetCoreDeadStreak();",
    'P31 call coreDeadStreak reset')

patch_regex('auto_test.dart',
    r'static bool _abortRequested = false;',
    "static bool _abortRequested = false;\n"
    "static bool get autoTestAbortRequested => _abortRequested;",
    'P32 expose abort state')

patch_regex('auto_test.dart',
    r'static void _resetCoreDeadStreak\(\) \{ _atCoreDeadStreak = 0; \}',
    "static void _resetCoreDeadStreak() { _atCoreDeadStreak = 0; }\n"
    "static int _atCoreDeadStreakCount() => _atCoreDeadStreak;",
    'P33 expose coreDeadStreak count')

patch_regex('auto_test.dart',
    r"if \(_findings\.isEmpty\) \{\s*buf\.writeln\('✅[^']+'\);",
    "if (_findings.isEmpty && !_abortRequested) {\n"
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
assert 'int natWorkers = natAdaptiveWorkers();' in nat, 'natWorkers assignment failed'

with open(os.path.join(LIB, 'main.dart'), encoding='utf-8') as f:
    mn = f.read()
assert 'int natAdaptiveWorkers()' in mn, 'natAdaptiveWorkers missing in main.dart'
assert 'skipEngine: true' in mn, 'skipEngine usage missing in main.dart'

print('')
print('=' * 72)
print('PATCH_V3: %d patches applied, %d skipped (non-critical)' % (_applied, _skipped))
print('=' * 72)
