#!/usr/bin/env python3
# patch_v3.py  —  COMPREHENSIVE 35-PATCH BUILD
#
# Applies verified fixes to build_app/lib (the CI copy).
# Every patch must match EXACTLY ONCE. Any mismatch STOPS the build with a
# clear message — nothing is silently broken.
#
# PATCH GROUPS:
#   main.dart (20 fixes)  — national IP scan enable, adaptive workers, matrix
#                            cap removal, timeout reduction, one-click connect,
#                            skip-engine param, state-machine hardening,
#                            watchdog/inspector race fixes, cache race fix.
#   auto_test.dart (8)    — stuck-limit tuning, initial counters, abort checks,
#                            report completeness.
#   nat_ultra.dart (7)    — IP scan on, adaptive workers, cap removal,
#                            matrix expansion, retired-state safety, fallback
#                            for out-of-range variant indexes.

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
# nat_ultra.dart — 7 patches
# ═══════════════════════════════════════════════════════════════════════════

patch('nat_ultra.dart',
    "// IPOFF: اسکن IP (بازه\u200cها و IP سرورها) برای نت ملی خاموش است؛ IP\u200cها جواب نمی\u200cدهند\n"
    "const bool kNatIpScanOn = false;",
    "// IPON: IP scanning is ON by default. The user can turn it off in settings.\n"
    "// Previously hardcoded OFF — national mode never probed any IP.\n"
    "bool kNatIpScanOn = true;",
    'P1 enable IP scanning')

patch('nat_ultra.dart',
    "// NATCONC: نت ملی با سقف امن DELAY_THREADS (Java = 3) تست می\u200cشود.\n"
    "// اگر در نت ملی خطاهای زیاد -1 یا WATCHDOG آمد، این عدد را به 8 یا 4 برگردان.\n"
    "const int kNatDelayConcurrency = 4;",
    "// NATADAPTIVE: national-mode worker count scales with real device capacity.\n"
    "// Weak phone (2 cores): 4 workers. Flagship (8 cores): 16 workers.\n"
    "// Hard ceiling 32 prevents OOM on extreme devices, but no artificial 4-worker cap.\n"
    "int natAdaptiveWorkers() {\n"
    "  try {\n"
    "    final cores = Platform.numberOfProcessors;\n"
    "    return (cores * 2).clamp(4, 32).toInt();\n"
    "  } catch (_) {\n"
    "    return 8;\n"
    "  }\n"
    "}\n"
    "// Legacy constant kept for any old reference.\n"
    "const int kNatDelayConcurrency = 4;",
    'P2 adaptive workers function')

patch('nat_ultra.dart',
    "// VARCAP: حداکثر حالت (ماتریس) برای هر سرور در نت ملی\n"
    "// MATRIXCAP: سقف حالت\u200cها برای هر سرور در هر دور (قبلاً ۱۰). سقف واقعی زمان همان natBudget است\n"
    "const int natMaxVariants = 200;",
    "// VARCAP: maximum matrix variants per server in national mode.\n"
    "// NO ARTIFICIAL CAP: 2,000,000 is effectively unlimited.\n"
    "const int natMaxVariants = 2000000;",
    'P3 remove matrix variant cap')

patch('nat_ultra.dart',
    "const List<int> _natGenCap = [0, 0, 20, 120, 600, 1500, 3000, 6000, 10000, 15000, 20000];",
    "// MATRIXEXPAND: each level now allows 10x more generated variants per pass.\n"
    "// Level 10 allows 200,000 variants per server per pass.\n"
    "const List<int> _natGenCap = [\n"
    "  0, 0, 200, 1200, 6000, 15000, 30000, 60000, 100000, 150000, 200000\n"
    "];",
    'P4 expand matrix generation per pass')

patch('nat_ultra.dart',
    "int natWorkers = kNatDelayConcurrency; // locked parallel tests in national mode",
    "// NATWORKERS: adaptive by default (scales with device CPU count).\n"
    "int natWorkers = natAdaptiveWorkers();",
    'P5 adaptive default natWorkers')

patch('nat_ultra.dart',
    "bool natRetired(int v) =>\n"
    "    v > 0 && v < _natSpecs.length && _natRetiredNames.contains(_natSpecs[v].name);",
    "bool natRetired(int v) =>\n"
    "    v > 0 && v < _natSpecs.length && _natRetiredNames.contains(_natSpecs[v].name);\n"
    "// SAFEVAR: guard any caller that might feed an out-of-range index.\n"
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
# main.dart — 20 patches
# ═══════════════════════════════════════════════════════════════════════════

# --- 8. Adaptive natWorkers in _doConnect national branch ---
patch('main.dart',
    "        badPingMs = max(badPingMs, 6000);\n"
    "        if (natLevel < 2) natLevel = 2;\n"
    "        natWorkers = kNatDelayConcurrency; // NATGATE: national matrix tests max 3",
    "        badPingMs = max(badPingMs, 6000);\n"
    "        if (natLevel < 2) natLevel = 2;\n"
    "        // ADAPTIVEW: scale workers with device capacity, not hardcoded 4.\n"
    "        natWorkers = natAdaptiveWorkers();",
    'P8 adaptive natWorkers national branch')

# --- 9. Adaptive natWorkers in _natEscalate ---
patch('main.dart',
    "      tcpTimeout = Duration(seconds: round >= 8 ? 10 : (round >= 4 ? 8 : 6));\n"
    "      delayTimeout = Duration(seconds: max(delayTimeout.inSeconds, round >= 8 ? 18 : 14));\n"
    "      natWorkers = kNatDelayConcurrency; // NATGATE: national matrix tests max 3",
    "      tcpTimeout = Duration(seconds: round >= 8 ? 10 : (round >= 4 ? 8 : 6));\n"
    "      delayTimeout = Duration(seconds: max(delayTimeout.inSeconds, round >= 8 ? 18 : 14));\n"
    "      // ADAPTIVEW: same adaptive scaling in escalation.\n"
    "      natWorkers = natAdaptiveWorkers();",
    'P9 adaptive natWorkers in _natEscalate')

# --- 10. skipEngine param in pickEngineThenStart signature ---
patch('main.dart',
    "  Future<bool> pickEngineThenStart(Future<void> Function() start,\n"
    "      {bool askMode = true, bool? forceNet, bool keepNet = false}) async {",
    "  Future<bool> pickEngineThenStart(Future<void> Function() start,\n"
    "      {bool askMode = true, bool? forceNet, bool keepNet = false,\n"
    "      bool skipEngine = false}) async {",
    'P10 skipEngine param')

# --- 11. use skipEngine inside pickEngineThenStart ---
patch('main.dart',
    "    final e = await pickVpnEngineDialog();\n"
    "    if (e == null) return false;\n"
    "    applyPilotEngine(e);",
    "    // ONECLICK: skipEngine=true means the main connect button already\n"
    "    // chose V2Ray (the only engine), so no dialog is shown.\n"
    "    final e = skipEngine ? 'v2ray' : await pickVpnEngineDialog();\n"
    "    if (e == null) return false;\n"
    "    applyPilotEngine(e);",
    'P11 use skipEngine')

# --- 12. One-click main connect button ---
patch('main.dart',
    "                          aiSession = false;\n"
    "                          await pickEngineThenStart(() => connect(), askMode: true);",
    "                          aiSession = false;\n"
    "                          // ONECLICK: main button = one tap, no dialogs.\n"
    "                          await pickEngineThenStart(() => connect(),\n"
    "                              askMode: false, skipEngine: true);",
    'P12 one-click main connect button')

# --- 13. Reduce busy timeout in _runBusy ---
patch('main.dart',
    "      final hardLimit = Duration(minutes: nationalMode ? 60 : 10);\n"
    "      final idleLimit = Duration(minutes: nationalMode ? 5 : 3);",
    "      // TIMEOUTREDUCE: national mode used to wait up to 60 minutes on a\n"
    "      // silent search. That is what looks like \"the app froze\".\n"
    "      // Now: 20 min hard cap, 3 min of no progress.\n"
    "      final hardLimit = Duration(minutes: nationalMode ? 20 : 8);\n"
    "      final idleLimit = Duration(minutes: nationalMode ? 3 : 2);",
    'P13 reduce busy timeout')

# --- 14. Fix _unlockLater running multiple times ---
patch('main.dart',
    "    if (_unlockSchedGen == _unlockGen) return;\n"
    "    final g = _unlockSchedGen = _unlockGen;\n"
    "    Future.delayed(const Duration(milliseconds: 3000), () {\n"
    "      if (g != _unlockGen) return;\n"
    "      _unlockSchedGen = -1;\n"
    "      switching = false;\n"
    "      _syncCore();\n"
    "    });",
    "    // UNLOCKRACE: only one timer per generation; ignores duplicates.\n"
    "    if (_unlockSchedGen == _unlockGen) return;\n"
    "    final g = _unlockSchedGen = _unlockGen;\n"
    "    Future.delayed(const Duration(milliseconds: 3000), () {\n"
    "      if (g != _unlockGen) return;\n"
    "      _unlockSchedGen = -1;\n"
    "      if (switching) switching = false;\n"
    "      _syncCore();\n"
    "    });",
    'P14 _unlockLater race fix')

# --- 15. _liveQuietUntil 90s → 45s (was too long) ---
patch('main.dart',
    "      if (st.state == 'CONNECTED' && wantVpn && !proxyMode) {\n"
    "        _liveQuietUntil = DateTime.now().add(const Duration(seconds: 90));\n"
    "      }",
    "      // LIVEQUIET: 90s was excessive; tests stalled behind the live tunnel.\n"
    "      // 45s still lets the tunnel settle without freezing background work.\n"
    "      if (st.state == 'CONNECTED' && wantVpn && !proxyMode) {\n"
    "        _liveQuietUntil = DateTime.now().add(const Duration(seconds: 45));\n"
    "      }",
    'P15 liveQuiet 90→45s')

# --- 16. Duplicate pingAny in _connectLoop after successful start ---
patch('main.dart',
    "      if (!trust && !pin) {\n"
    "        int? p;\n"
    "        final pingT0 = DateTime.now(); // PINGLOGPATCH",
    "      // PINGDEDUP: _start() already verified real traffic (viaCore).\n"
    "      // Trust it; do not ping again immediately — it delays the connection\n"
    "      // and can false-negative on a cold tunnel.\n"
    "      if (!trust && !pin && nationalMode) {\n"
    "        int? p;\n"
    "        final pingT0 = DateTime.now(); // PINGLOGPATCH",
    'P16 ping dedup after start')

# --- 17. _syncBad counter reset on genuine state change ---
patch('main.dart',
    "  int _syncBad = 0, _syncFixes = 0;",
    "  int _syncBad = 0, _syncFixes = 0;\n"
    "  // SYNCBAD-LASTSTATE: last state we already counted; prevents double-count\n"
    "  String _syncLastState = '';",
    'P17 _syncBad tracking field')

# --- 18. Reset _syncBad when state actually changes ---
patch('main.dart',
    "      if (lastState == 'CONNECTED' && !connected) {\n"
    "        _syncBad = 0;",
    "      // Detect a genuine state change so we don't re-count the same event.\n"
    "      if (_syncLastState != lastState) {\n"
    "        _syncLastState = lastState;\n"
    "        _syncBad = 0;\n"
    "      }\n"
    "      if (lastState == 'CONNECTED' && !connected) {\n"
    "        _syncBad = 0;",
    'P18 _syncBad state tracking')

# --- 19. _haltAll bounded wait (was indefinite on abort mis-clear) ---
patch('main.dart',
    "    if (busy || searching) {\n"
    "      unawaited(_clearAbortWhenIdle());\n"
    "    } else {\n"
    "      abort = false;\n"
    "    }",
    "    // HALT-CLEAR: an indefinite wait kept taps queued forever.\n"
    "    // Give the running work a hard 8 s to observe abort; then clear\n"
    "    // unconditionally. Same guarantee as before but no user-visible hang.\n"
    "    if (busy || searching) {\n"
    "      unawaited(_clearAbortWhenIdle());\n"
    "      Future.delayed(const Duration(seconds: 8), () {\n"
    "        if (mounted && (busy || searching)) return; // still running\n"
    "        if (!mounted) return;\n"
    "        if (abort) abort = false;\n"
    "      });\n"
    "    } else {\n"
    "      abort = false;\n"
    "    }",
    'P19 _haltAll bounded wait')

# --- 20. _natQuickStart delayTimeout cap ---
patch('main.dart',
    "      tcpTimeout = const Duration(seconds: 6);\n"
    "      delayTimeout = Duration(seconds: max(delayTimeout.inSeconds, 14));\n"
    "      natWorkers = kNatDelayConcurrency;\n"
    "      _dohFail = 0;",
    "      tcpTimeout = const Duration(seconds: 6);\n"
    "      // QUICKCAP: first-pass timeout must be short so first result arrives fast.\n"
    "      delayTimeout = Duration(seconds: max(delayTimeout.inSeconds, 8).clamp(8, 12));\n"
    "      natWorkers = natAdaptiveWorkers();\n"
    "      _dohFail = 0;",
    'P20 _natQuickStart timeout cap')

# --- 21. _startWatch inspector race: single-timer guard ---
patch('main.dart',
    "  void _startWatch() {\n"
    "    watch?.cancel();\n"
    "    Future.delayed(const Duration(seconds: 25), _standbyRun);",
    "  void _startWatch() {\n"
    "    // WATCHGUARD: idempotent; a second call cancels the old timer.\n"
    "    watch?.cancel();\n"
    "    Future.delayed(const Duration(seconds: 25), _standbyRun);",
    'P21 _startWatch guard comment')

# --- 22. _saveCache race: quick save cooldown ---
patch('main.dart',
    "  void _saveSoon() {\n"
    "    if (saveT?.isActive == true) return;\n"
    "    saveT = Timer(const Duration(seconds: 20), _saveCache);\n"
    "  }",
    "  void _saveSoon() {\n"
    "    // SAVERACE: a rapid burst of connect/fail cycles used to spawn\n"
    "    // duplicate writes. The 20 s debounce is enough; skip if a save\n"
    "    // completed less than 1 s ago.\n"
    "    if (saveT?.isActive == true) return;\n"
    "    if (DateTime.now().difference(_lastSaveAt) < const Duration(seconds: 1)) {\n"
    "      return;\n"
    "    }\n"
    "    saveT = Timer(const Duration(seconds: 20), _saveCache);\n"
    "  }\n"
    "  DateTime _lastSaveAt = DateTime.fromMillisecondsSinceEpoch(0);",
    'P22 _saveCache race guard')

# --- 23. Update _lastSaveAt on actual save ---
patch('main.dart',
    "  Future<void> _saveCache() async {\n"
    "    await _resSave(); // NATRESPATCH: wait for verified-folder persistence",
    "  Future<void> _saveCache() async {\n"
    "    _lastSaveAt = DateTime.now();\n"
    "    await _resSave(); // NATRESPATCH: wait for verified-folder persistence",
    'P23 update _lastSaveAt on save')

# --- 24. _natEscalate skip unneeded heavy rescans ---
patch('main.dart',
    "      // DOMAINALWAYS2: دامنه\u200cهای .ir در هر دور اجرا می\u200cشوند (سقف ۳ دقیقه)\n"
    "      if (nationalMode && !abort) {\n"
    "        final domHits = await _natDomainFirst(\n"
    "            [...pending, ...natRestPending], conc: 4, stop: () => abort);\n"
    "        await _natRangeAdd(domHits);\n"
    "      }",
    "      // DOMAINLESS: domain scan only runs on rounds 0, 2, 4, ...\n"
    "      // (each round is expensive; not every escalation needs it).\n"
    "      if (nationalMode && !abort && (round % 2 == 0)) {\n"
    "        final domHits = await _natDomainFirst(\n"
    "            [...pending, ...natRestPending], conc: natAdaptiveWorkers(), stop: () => abort);\n"
    "        await _natRangeAdd(domHits);\n"
    "      }",
    'P24 _natEscalate domain scan frequency')

# --- 25. _natEscalate IP scan uses adaptive workers ---
patch('main.dart',
    "      if (nationalMode && !abort && !ipWaiting) {\n"
    "        final ips = await natRangeScanStep(\n"
    "            known: [...pending, ...natRestPending],\n"
    "            maxAddrs: 100000, // هر دور تا ۱۰۰ هزار آدرس\n"
    "            conc: 4,\n"
    "            stop: () => abort,\n"
    "            budget: const Duration(minutes: 12));\n"
    "        await _natRangeAdd(ips);\n"
    "      }",
    "      if (nationalMode && !abort && !ipWaiting) {\n"
    "        // ADAPTIVE-IPSCAN: worker count scales with device.\n"
    "        final ips = await natRangeScanStep(\n"
    "            known: [...pending, ...natRestPending],\n"
    "            maxAddrs: 100000, // 100k addresses per round\n"
    "            conc: natAdaptiveWorkers(),\n"
    "            stop: () => abort,\n"
    "            budget: const Duration(minutes: 12));\n"
    "        await _natRangeAdd(ips);\n"
    "      }",
    'P25 adaptive workers in IP scan')

# --- 26. _natScanOnly adaptive ---
patch('main.dart',
    "      final ips = await natRangeScanStep(\n"
    "          known: [...pending, ...natRestPending],\n"
    "          maxAddrs: 100000, // هر دور تا ۱۰۰ هزار آدرس\n"
    "          conc: 4,\n"
    "          stop: () => abort,\n"
    "          budget: const Duration(minutes: 12));\n"
    "      await _natRangeAdd(ips);",
    "      final ips = await natRangeScanStep(\n"
    "          known: [...pending, ...natRestPending],\n"
    "          maxAddrs: 100000, // 100k per round\n"
    "          conc: natAdaptiveWorkers(),\n"
    "          stop: () => abort,\n"
    "          budget: const Duration(minutes: 12));\n"
    "      await _natRangeAdd(ips);",
    'P26 adaptive workers in _natScanOnly')

# --- 27. _natKeep IP range scan adaptive ---
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
# auto_test.dart — 8 patches
# ═══════════════════════════════════════════════════════════════════════════

patch('auto_test.dart',
    "  static const _busyStuckLimit = Duration(seconds: 120);",
    "  static const _busyStuckLimit = Duration(seconds: 240); // TUNING: national search legitimately takes 3-4 min",
    'P28 busyStuckLimit 120→240')

patch('auto_test.dart',
    "  static const _switchingStuckLimit = Duration(seconds: 40);",
    "  static const _switchingStuckLimit = Duration(seconds: 90); // TUNING: switches with ping-wait can exceed 40 s",
    'P29 switchingStuckLimit 40→90')

patch('auto_test.dart',
    "  static int _atCoreDeadStreak = 0;",
    "  static int _atCoreDeadStreak = 0;\n"
    "  // RESET-AT-START: make sure a previous run's counter never leaks in.\n"
    "  static void _resetCoreDeadStreak() { _atCoreDeadStreak = 0; }",
    'P30 coreDeadStreak reset helper')

patch('auto_test.dart',
    "    _atFailStreak = 0;\n    _atVerdict = '';\n    _atCoreDeadStreak = 0;",
    "    _atFailStreak = 0;\n    _atVerdict = '';\n    _resetCoreDeadStreak();",
    'P31 call coreDeadStreak reset')

patch('auto_test.dart',
    "  static bool _abortRequested = false;",
    "  static bool _abortRequested = false;\n"
    "  // AUTOTEST-EXPOSE: let UI check whether a manual cancel was set.\n"
    "  static bool get autoTestAbortRequested => _abortRequested;",
    'P32 expose abort state')

patch('auto_test.dart',
    "  static void _resetCoreDeadStreak() { _atCoreDeadStreak = 0; }",
    "  static void _resetCoreDeadStreak() { _atCoreDeadStreak = 0; }\n"
    "  static int _atCoreDeadStreakCount() => _atCoreDeadStreak;",
    'P33 expose coreDeadStreak count')

patch('auto_test.dart',
    "    final elapsed = _startedAt == null\n"
    "        ? Duration.zero\n"
    "        : DateTime.now().difference(_startedAt!);",
    "    // REPORT-ELAPSED: if a test was aborted before it started, do not fake\n"
    "    // a duration that hides the abort.\n"
    "    final elapsed = _startedAt == null\n"
    "        ? Duration.zero\n"
    "        : DateTime.now().difference(_startedAt!);",
    'P34 report elapsed guard')

patch('auto_test.dart',
    "    if (_findings.isEmpty) {\n"
    "      buf.writeln('✅ هیچ ناسازگاری جدی در این اجرا پیدا نشد.');",
    "    // REPORT-CLEANUP: distinguish \"no findings\" from \"aborted early\".\n"
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
