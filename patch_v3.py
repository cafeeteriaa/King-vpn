#!/usr/bin/env python3
# patch_v3.py (v7.0 — FINAL: ALL PATCHES, ZERO BUILD FAILURES)
# 
# این اسکریپت هرگز با خطا متوقف نمی‌شود.
# اگر خطی پیدا نشود، در لاگ WARN می‌دهد و به کار خود ادامه می‌دهد تا APK ساخته شود.
# پچ‌هایی که به هم وابسته هستند، در صورت شکست یکی، بقیه هم به صورت خودکار رد می‌شوند
# تا کد Dart دچار خطای Undefined نشود.

import os
import re
import sys

LIB = sys.argv[1] if len(sys.argv) > 1 else 'build_app/lib'
if not os.path.isdir(LIB):
    print(f'ERROR: target directory does not exist: {LIB}')
    sys.exit(1)

ok = {}
applied_count = 0
skipped_count = 0

def patch(fname, old, new, label, deps=None):
    global applied_count, skipped_count
    if deps:
        for d in deps:
            if not ok.get(d, False):
                print(f'⏭️  SKIP [{label}]: dependency {d} not applied')
                skipped_count += 1
                return False
    path = os.path.join(LIB, fname)
    if not os.path.exists(path):
        print(f'⚠️  WARN [{label}]: {fname} not found')
        skipped_count += 1
        return False
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    if old not in src:
        if new in src:
            print(f'✅ OK   [{label}]: already applied')
            applied_count += 1
            return True
        print(f'⚠️  WARN [{label}]: anchor not found in {fname}')
        skipped_count += 1
        return False
    src = src.replace(old, new, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src)
    print(f'✅ OK   [{label}]: applied to {fname}')
    applied_count += 1
    return True

def patch_all(fname, old, new, label, deps=None):
    global applied_count, skipped_count
    if deps:
        for d in deps:
            if not ok.get(d, False):
                print(f'⏭️  SKIP [{label}]: dependency {d} not applied')
                skipped_count += 1
                return False
    path = os.path.join(LIB, fname)
    if not os.path.exists(path):
        print(f'⚠️  WARN [{label}]: {fname} not found')
        skipped_count += 1
        return False
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    if old not in src:
        if new in src:
            print(f'✅ OK   [{label}]: already applied')
            applied_count += 1
            return True
        print(f'⚠️  WARN [{label}]: anchor not found in {fname}')
        skipped_count += 1
        return False
    n = src.count(old)
    src = src.replace(old, new)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src)
    print(f'✅ OK   [{label}]: applied ({n}×) to {fname}')
    applied_count += 1
    return True

print('')
print('═' * 72)
print('PATCH_V3 v7.0 — Starting all patches (Safe Mode)')
print('═' * 72)

# ═══════════════════════════════════════════════════════════════════════════
# GROUP 1: nat_ultra.dart — IP scan + matrix
# ═══════════════════════════════════════════════════════════════════════════
ok['P1'] = patch('nat_ultra.dart',
    'const bool kNatIpScanOn = false;',
    'bool kNatIpScanOn = true;',
    'P1  Enable IP scan')

ok['P2'] = patch('nat_ultra.dart',
    'const int natMaxVariants = 200;',
    'const int natMaxVariants = 2000000;',
    'P2  Remove matrix cap')

path = os.path.join(LIB, 'nat_ultra.dart')
with open(path, 'r', encoding='utf-8') as f:
    _src = f.read()
_m = re.search(r'const\s+List<int>\s+_natGenCap\s*=\s*\[[^\]]+\]\s*;', _src)
if _m:
    _src = _src[: _m.start()] + (
        'const List<int> _natGenCap = [\n'
        '  0, 0, 200, 1200, 6000, 15000, 30000, 60000, 100000, 150000, 200000\n'
        '];'
    ) + _src[_m.end():]
    with open(path, 'w', encoding='utf-8') as f:
        f.write(_src)
    print('✅ OK   [P3  Expand matrix gen]: applied (regex) to nat_ultra.dart')
    ok['P3'] = True
    applied_count += 1
else:
    print('⚠️  WARN [P3  Expand matrix gen]: regex not found in nat_ultra.dart')
    ok['P3'] = False
    skipped_count += 1

# ═══════════════════════════════════════════════════════════════════════════
# GROUP 2: Adaptive workers (main.dart defines, nat_ultra & main use)
# ═══════════════════════════════════════════════════════════════════════════
ok['P4'] = patch('main.dart',
    'const int kNatDelayConcurrency = 4;',
    'int natAdaptiveWorkers() {\n'
    '  try {\n'
    '    final cores = Platform.numberOfProcessors;\n'
    '    return (cores * 2).clamp(4, 32).toInt();\n'
    '  } catch (_) {\n'
    '    return 8;\n'
    '  }\n'
    '}\n'
    'const int kNatDelayConcurrency = 4;',
    'P4  Define adaptive workers func')

ok['P5'] = patch('nat_ultra.dart',
    'int natWorkers = kNatDelayConcurrency;',
    'int natWorkers = natAdaptiveWorkers();',
    'P5  Use adaptive (ultra default)',
    deps=['P4'])

ok['P6'] = patch_all('main.dart',
    'natWorkers = kNatDelayConcurrency;',
    'natWorkers = natAdaptiveWorkers();',
    'P6  Use adaptive (main assignments)',
    deps=['P4'])

# ═══════════════════════════════════════════════════════════════════════════
# GROUP 3: One-click connect
# ═══════════════════════════════════════════════════════════════════════════
ok['P7'] = patch('main.dart',
    '{bool askMode = true, bool? forceNet, bool keepNet = false}) async {',
    '{bool askMode = true, bool? forceNet, bool keepNet = false,\n'
    '      bool skipEngine = false}) async {',
    'P7  Add skipEngine param')

ok['P8'] = patch('main.dart',
    'final e = await pickVpnEngineDialog();\n'
    '    if (e == null) return false;\n'
    '    applyPilotEngine(e);',
    'final e = skipEngine ? \'v2ray\' : await pickVpnEngineDialog();\n'
    '    if (e == null) return false;\n'
    '    applyPilotEngine(e);',
    'P8  Use skipEngine in logic',
    deps=['P7'])

ok['P9'] = patch('main.dart',
    'await pickEngineThenStart(() => connect(), askMode: true);',
    'await pickEngineThenStart(() => connect(),\n'
    '                              askMode: false, skipEngine: true);',
    'P9  One-click UI button',
    deps=['P7'])

# ═══════════════════════════════════════════════════════════════════════════
# GROUP 4: Timeouts
# ═══════════════════════════════════════════════════════════════════════════
ok['P10'] = patch('main.dart',
    'final hardLimit = Duration(minutes: nationalMode ? 60 : 10);',
    'final hardLimit = Duration(minutes: nationalMode ? 20 : 8);',
    'P10 Reduce hard timeout')

ok['P11'] = patch('main.dart',
    'final idleLimit = Duration(minutes: nationalMode ? 5 : 3);',
    'final idleLimit = Duration(minutes: nationalMode ? 3 : 2);',
    'P11 Reduce idle timeout')

# ═══════════════════════════════════════════════════════════════════════════
# GROUP 5: natSafeVariant guard
# ═══════════════════════════════════════════════════════════════════════════
ok['P12'] = patch('nat_ultra.dart',
    'int natVarFor(Server s) {\n'
    '  if (!nationalMode) return 0;\n'
    '  final v = natVar[_nk(s)] ?? 0;\n'
    '  if (v <= 0 || v >= _natSpecs.length) return 0;',
    'int natSafeVariant(int v) {\n'
    '  if (v < 0) return 0;\n'
    '  if (v >= _natSpecs.length) return 0;\n'
    '  return v;\n'
    '}\n'
    'int natVarFor(Server s) {\n'
    '  if (!nationalMode) return 0;\n'
    '  final rawV = natVar[_nk(s)] ?? 0;\n'
    '  final v = natSafeVariant(rawV);\n'
    '  if (v <= 0) return 0;',
    'P12 Add natSafeVariant guard')

# ═══════════════════════════════════════════════════════════════════════════
# GROUP 6: _syncBad state tracking
# ═══════════════════════════════════════════════════════════════════════════
ok['P13'] = patch('main.dart',
    'int _syncBad = 0, _syncFixes = 0;',
    'int _syncBad = 0, _syncFixes = 0;\n'
    "  String _syncLastState = '';",
    'P13 Add _syncBad tracking field')

ok['P14'] = patch('main.dart',
    "      if (lastState == 'CONNECTED' && !connected) {\n"
    '        _syncBad = 0;',
    '      if (_syncLastState != lastState) {\n'
    '        _syncLastState = lastState;\n'
    '        _syncBad = 0;\n'
    '      }\n'
    "      if (lastState == 'CONNECTED' && !connected) {\n"
    '        _syncBad = 0;',
    'P14 Use _syncBad state tracking',
    deps=['P13'])

# ═══════════════════════════════════════════════════════════════════════════
# GROUP 7: _haltAll bounded wait
# ═══════════════════════════════════════════════════════════════════════════
ok['P15'] = patch('main.dart',
    '    if (busy || searching) {\n'
    '      unawaited(_clearAbortWhenIdle());\n'
    '    } else {\n'
    '      abort = false;\n'
    '    }',
    '    if (busy || searching) {\n'
    '      unawaited(_clearAbortWhenIdle());\n'
    '      Future.delayed(const Duration(seconds: 8), () {\n'
    '        if (mounted && (busy || searching)) return;\n'
    '        if (!mounted) return;\n'
    '        if (abort) abort = false;\n'
    '      });\n'
    '    } else {\n'
    '      abort = false;\n'
    '    }',
    'P15 _haltAll bounded wait')

# ═══════════════════════════════════════════════════════════════════════════
# GROUP 8: _natQuickStart cap
# ═══════════════════════════════════════════════════════════════════════════
ok['P16'] = patch('main.dart',
    'delayTimeout = Duration(seconds: max(delayTimeout.inSeconds, 14));',
    'delayTimeout = Duration(seconds: max(delayTimeout.inSeconds, 8).clamp(8, 12));',
    'P16 _natQuickStart cap',
    deps=['P4'])

# ═══════════════════════════════════════════════════════════════════════════
# GROUP 9: natEscalate domain frequency
# ═══════════════════════════════════════════════════════════════════════════
ok['P17'] = patch('main.dart',
    'if (nationalMode && !abort) {\n'
    '        final domHits = await _natDomainFirst(',
    'if (nationalMode && !abort && (round % 2 == 0)) {\n'
    '        final domHits = await _natDomainFirst(',
    'P17 _natEscalate domain freq')

# ═══════════════════════════════════════════════════════════════════════════
# GROUP 10: _saveCache race guard
# ═══════════════════════════════════════════════════════════════════════════
ok['P18'] = patch('main.dart',
    '  void _saveSoon() {\n'
    '    if (saveT?.isActive == true) return;\n'
    '    saveT = Timer(const Duration(seconds: 20), _saveCache);\n'
    '  }',
    '  DateTime _lastSaveAt = DateTime.fromMillisecondsSinceEpoch(0);\n'
    '  void _saveSoon() {\n'
    '    if (saveT?.isActive == true) return;\n'
    '    if (DateTime.now().difference(_lastSaveAt) < const Duration(seconds: 1)) {\n'
    '      return;\n'
    '    }\n'
    '    saveT = Timer(const Duration(seconds: 20), _saveCache);\n'
    '  }',
    'P18 _saveCache race guard')

ok['P19'] = patch('main.dart',
    '  Future<void> _saveCache() async {\n'
    '    await _resSave();',
    '  Future<void> _saveCache() async {\n'
    '    _lastSaveAt = DateTime.now();\n'
    '    await _resSave();',
    'P19 Update _lastSaveAt on save',
    deps=['P18'])

# ═══════════════════════════════════════════════════════════════════════════
# GROUP 11: Adaptive conc (all occurrences)
# ═══════════════════════════════════════════════════════════════════════════
ok['P20'] = patch_all('main.dart',
    'conc: 4,',
    'conc: natAdaptiveWorkers(),',
    'P20 Adaptive conc (comma)',
    deps=['P4'])

ok['P21'] = patch_all('main.dart',
    'conc: 4);',
    'conc: natAdaptiveWorkers());',
    'P21 Adaptive conc (paren)',
    deps=['P4'])

# ═══════════════════════════════════════════════════════════════════════════
# GROUP 12: auto_test.dart — timeouts
# ═══════════════════════════════════════════════════════════════════════════
ok['P22'] = patch('auto_test.dart',
    'static const _busyStuckLimit = Duration(seconds: 120);',
    'static const _busyStuckLimit = Duration(seconds: 240);',
    'P22 auto_test busy stuck 240s')

ok['P23'] = patch('auto_test.dart',
    'static const _switchingStuckLimit = Duration(seconds: 40);',
    'static const _switchingStuckLimit = Duration(seconds: 90);',
    'P23 auto_test switching 90s')

# ═══════════════════════════════════════════════════════════════════════════
# GROUP 13: auto_test.dart — core dead streak reset
# ═══════════════════════════════════════════════════════════════════════════
ok['P24'] = patch('auto_test.dart',
    'static int _atCoreDeadStreak = 0;',
    'static int _atCoreDeadStreak = 0;\n'
    'static void _resetCoreDeadStreak() { _atCoreDeadStreak = 0; }',
    'P24 auto_test coreDeadStreak helper')

ok['P25'] = patch('auto_test.dart',
    "    _atFailStreak = 0;\n    _atVerdict = '';\n    _atCoreDeadStreak = 0;",
    "    _atFailStreak = 0;\n    _atVerdict = '';\n    _resetCoreDeadStreak();",
    'P25 auto_test call reset helper',
    deps=['P24'])

# ═══════════════════════════════════════════════════════════════════════════
# GROUP 14: auto_test.dart — expose abort state
# ═══════════════════════════════════════════════════════════════════════════
ok['P26'] = patch('auto_test.dart',
    'static bool _abortRequested = false;',
    'static bool _abortRequested = false;\n'
    'static bool get autoTestAbortRequested => _abortRequested;',
    'P26 auto_test expose abort state')

# ═══════════════════════════════════════════════════════════════════════════
# GROUP 15: auto_test.dart — report abort marker
# ═══════════════════════════════════════════════════════════════════════════
ok['P27'] = patch('auto_test.dart',
    'if (_findings.isEmpty) {',
    'if (_findings.isEmpty && !_abortRequested) {',
    'P27 auto_test report abort marker',
    deps=['P26'])

# ═══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════
print('')
print('═' * 72)
print(f'PATCH_V3 SUMMARY: {applied_count} applied, {skipped_count} skipped')
print('─' * 72)

failed = [k for k, v in ok.items() if not v]
if failed:
    print(f'⚠️  Patches NOT applied (safe to skip, build continues):')
    for k in failed:
        print(f'   • {k}')
else:
    print('🎉 ALL PATCHES APPLIED SUCCESSFULLY')

print('─' * 72)
print('Build will now continue. APK will be produced.')
print('═' * 72)
print('')
