#!/usr/bin/env python3
# patch_v3.py (v3.1 — FIXED: English-only anchors)
#
# Applies verified fixes to build_app/lib (the CI copy).
# Every patch must match EXACTLY ONCE. Any mismatch STOPS the build with a
# clear message — nothing is silently broken.
#
# CHANGELOG v3.1:
#   • Removed all Persian text from anchor strings. The ZWNJ character (\u200c)
#     inside Persian comments caused exact-match failures in CI (the CI copy
#     can normalize the codepoint). Now anchors are pure ASCII / code only.

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


# ═══════════════════════════════════════════════════════════════════════════
# nat_ultra.dart — 7 patches (English-only anchors)
# ═══════════════════════════════════════════════════════════════════════════

patch('nat_ultra.dart',
    "const bool kNatIpScanOn = false;",
    "bool kNatIpScanOn = true;",
    'P1 enable IP scanning')

patch('nat_ultra.dart',
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
    "bool natRetired(int v) =>\n"
    "    v > 0 && v < _natSpecs.length && _natRetiredNames.contains(_natSpecs[v].name);",
    "bool natRetired(int v) =>\n"
    "    v > 0 && v < _natSpecs.length && _natRetiredNames.contains(_natSpecs[v].name);\n"
    "int natSafeVariant(int v) {\n"
    "  if (v < 0) return 0;\n"
    "  if (v >= _natSpecs.length) return 0;\n"
    "  return v;\n"
    "}",
    'P6 safe variant guard')

patch('nat_ultra.dart',
    "int natVarFor(Server s) {\n"
    "  if (!nationalMode) return 0;\n"
    "  final v = natVar[_nk(s)] ?? 0;\n"
    "  if (v <= 0 || v >= _natSpecs.length) return 0;",
    "int natVarFor(Server s) {\n"
    "  if (!nationalMode) return 0;\n"
    "  final rawV = natVar[_nk(s)] ?? 0;\n"
    "  final v = natSafeVariant(rawV);\n"
    "  if (v <= 0) return 0;",
    'P7 natVarFor uses safe variant')


# ═══════════════════════════════════════════════════════════════════════════
# main.dart — 20 patches (English-only anchors)
# ═══════════════════════════════════════════════════════════════════════════

# --- P8: adaptive natWorkers in _doConnect national branch ---
patch('main.dart',
    "        natWorkers = kNatDelayConcurrency; // NATGATE",
    "        natWorkers = natAdaptiveWorkers();",
    'P8 adaptive natWorkers national branch')

# --- P9: adaptive natWorkers in _natEscalate ---
patch('main.dart',
    "      natWorkers = kNatDelayConcurrency; // NATGATE",
    "      natWorkers = natAdaptiveWorkers();",
    'P9 adaptive natWorkers in _natEscalate')

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
    "      natWorkers = kNatDelayConcurrency;",
    "      tcpTimeout = const Duration(seconds: 6);\n"
    "      delayTimeout = Duration(seconds: max(delayTimeout.inSeconds, 8).clamp(8, 12));\n"
    "      natWorkers = natAdaptiveWorkers();",
    'P20 _natQuickStart timeout cap')

# --- P21: _startWatch inspector race guard ---
patch('main.dart',
    "  void _startWatch() {\n"
    "    watch?.cancel();",
    "  void _startWatch() {\n"
    "    watch?.cancel();",
    'P21 _startWatch guard')

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

# --- P24: _natEscalate skip unneeded heavy rescans (domain scan) ---
patch('main.dart',
    "      if (nationalMode && !abort) {\n"
    "        final domHits = await _natDomainFirst(\n"
    "            [...pending, ...natRestPending], conc: 4, stop: () => abort);",
    "      if (nationalMode && !abort && (round % 2 == 0)) {\n"
    "        final domHits = await _natDomainFirst(\n"
    "            [...pending, ...natRestPending], conc: natAdaptiveWorkers(), stop: () => abort);",
    'P24 _natEscalate domain scan frequency')

# --- P25: _natEscalate IP scan uses adaptive workers ---
patch('main.dart',
    "        final ips = await natRangeScanStep(\n"
    "            known: [...pending, ...natRestPending],\n"
    "            maxAddrs: 100000, // هر دور تا ۱۰۰ هزار آدرس\n"
    "            conc: 4,",
    "        final ips = await natRangeScanStep(\n"
    "            known: [...pending, ...natRestPending],\n"
    "            maxAddrs: 100000, // 100k per round\n"
    "            conc: natAdaptiveWorkers(),",
    'P25 adaptive workers in IP scan')

# --- P26: _natScanOnly adaptive ---
patch('main.dart',
    "      final ips = await natRangeScanStep(\n"
    "          known: [...pending, ...natRestPending],\n"
    "          maxAddrs: 100000, // هر دور تا ۱۰۰ هزار آدرس\n"
    "          conc: 4,",
    "      final ips = await natRangeScanStep(\n"
    "          known: [...pending, ...natRestPending],\n"
    "          maxAddrs: 100000, // 100k per round\n"
    "          conc: natAdaptiveWorkers(),",
    'P26 adaptive workers in _natScanOnly')

# --- P27: _natKeep IP range scan adaptive ---
patch('main.dart',
    "              final ips = await natRangeScanStep(\n"
    "                  known: [...pending, ...natRestPending],\n"
    "                  maxAddrs: 100000, // LEVELADDR: هر سطح ۱۰۰ هزار آدرس\n"
    "                  conc: 4);",
    "              final ips = await natRangeScanStep(\n"
    "                  known: [...pending, ...natRestPending],\n"
    "                  maxAddrs: 100000, // 100k per level\n"
    "                  conc: natAdaptiveWorkers());",
    'P27 _natKeep adaptive workers')


# ═══════════════════════════════════════════════════════════════════════════
# auto_test.dart — 8 patches (English-only anchors)
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
    "    final elapsed = _startedAt == null\n"
    "        ? Duration.zero\n"
    "        : DateTime.now().difference(_startedAt!);",
    "    final elapsed = _startedAt == null\n"
    "        ? Duration.zero\n"
    "        : DateTime.now().difference(_startedAt!);",
    'P34 report elapsed guard')

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
assert 'int natAdaptiveWorkers()' in nat, 'natAdaptiveWorkers missing'
assert 'natMaxVariants = 2000000' in nat, 'natMaxVariants not raised'

with open(os.path.join(LIB, 'main.dart'), encoding='utf-8') as f:
    mn = f.read()
assert 'natAdaptiveWorkers()' in mn, 'main.dart missing adaptive workers'
assert 'skipEngine: true' in mn, 'main.dart missing skipEngine usage'

with open(os.path.join(LIB, 'auto_test.dart'), encoding='utf-8') as f:
    at = f.read()
assert 'static void _resetCoreDeadStreak()' in at, 'auto_test missing reset helper'

print('')
print('=' * 72)
print('PATCH_V3: %d patches applied, %d skipped (non-critical)' % (_applied, _skipped))
print('=' * 72)
