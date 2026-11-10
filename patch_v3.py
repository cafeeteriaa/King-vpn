#!/usr/bin/env python3
# patch_v3.py
#
# Applies verified fixes to the copied app sources (build_app/lib).
# Every patch must match EXACTLY ONCE. If any anchor is not found, the build
# stops with a clear message — nothing is silently broken.
#
# FIXES APPLIED:
#   1. Enable IP scanning for national mode (was hardcoded OFF).
#   2. Adaptive worker count (was hardcoded to 4) scaled by CPU cores.
#   3. Remove artificial matrix variant cap (was 200 → now 2,000,000).
#   4. Expand generated-matrix budget per pass (10x at every level).
#   5. Adaptive natWorkers default.
#   6. Reduce national busy timeout (60 min → 20 min).
#   7. Fix natWorkers assignment inside _doConnect national branch.
#   8. Fix natWorkers assignment inside _natEscalate.
#   9. Add `skipEngine` param to pickEngineThenStart.
#  10. Use `skipEngine` to skip the engine dialog.
#  11. Main connect button = one tap, no dialogs (advanced paths keep theirs).

import os
import sys

LIB = sys.argv[1] if len(sys.argv) > 1 else 'build_app/lib'

if not os.path.isdir(LIB):
    print('ERROR: target directory does not exist: %s' % LIB)
    sys.exit(1)


def patch(fname, old, new, label, critical=True):
    """Find `old` exactly once in `fname`, replace with `new`."""
    path = os.path.join(LIB, fname)
    if not os.path.exists(path):
        print('ERROR: %s not found at %s' % (fname, path))
        sys.exit(1)
    with open(path, encoding='utf-8') as f:
        src = f.read()
    n = src.count(old)
    if n != 1:
        level = 'ERROR' if critical else 'SKIP'
        print('%s: %s: expected 1 match in %s, found %d' % (level, label, fname, n))
        print('  pattern: %r' % (old[:150],))
        if critical:
            sys.exit(1)
        return False
    src = src.replace(old, new, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src)
    print('OK: %s (%s)' % (label, fname))
    return True


# ============================================================================
# PATCH 1 (nat_ultra.dart) — enable IP scanning
# ============================================================================
patch(
    'nat_ultra.dart',
    "// IPOFF: اسکن IP (بازه\u200cها و IP سرورها) برای نت ملی خاموش است؛ IP\u200cها جواب نمی\u200cدهند\n"
    "const bool kNatIpScanOn = false;",
    "// IPON: IP scanning is ON by default. The user can turn it off in settings.\n"
    "// Previously hardcoded OFF (`const ... = false`) so national mode NEVER probed\n"
    "// any IP address. That directly contradicted the project requirement.\n"
    "bool kNatIpScanOn = true;",
    'P1 enable IP scanning',
)

# ============================================================================
# PATCH 2 (nat_ultra.dart) — adaptive workers function (replaces hardcoded 4)
# ============================================================================
patch(
    'nat_ultra.dart',
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
    "    return 8; // conservative fallback if Platform fails\n"
    "  }\n"
    "}\n"
    "// Legacy constant kept for any old reference; new code uses natAdaptiveWorkers().\n"
    "const int kNatDelayConcurrency = 4;",
    'P2 adaptive workers function',
)

# ============================================================================
# PATCH 3 (nat_ultra.dart) — remove matrix variant cap
# ============================================================================
patch(
    'nat_ultra.dart',
    "// VARCAP: حداکثر حالت (ماتریس) برای هر سرور در نت ملی\n"
    "// MATRIXCAP: سقف حالت\u200cها برای هر سرور در هر دور (قبلاً ۱۰). سقف واقعی زمان همان natBudget است\n"
    "const int natMaxVariants = 200;",
    "// VARCAP: maximum matrix variants per server in national mode.\n"
    "// NO ARTIFICIAL CAP: 2,000,000 is effectively unlimited. The real limit is\n"
    "// natBudget() (time-based) and device capacity, not a fixed number.\n"
    "const int natMaxVariants = 2000000;",
    'P3 remove matrix variant cap',
)

# ============================================================================
# PATCH 4 (nat_ultra.dart) — expand generated matrix per pass
# ============================================================================
patch(
    'nat_ultra.dart',
    "const List<int> _natGenCap = [0, 0, 20, 120, 600, 1500, 3000, 6000, 10000, 15000, 20000];",
    "// MATRIXEXPAND: each level now allows 10x more generated variants per pass.\n"
    "// Level 10 (the deepest) allows 200,000 variants per server per pass.\n"
    "const List<int> _natGenCap = [\n"
    "  0, 0, 200, 1200, 6000, 15000, 30000, 60000, 100000, 150000, 200000\n"
    "];",
    'P4 expand matrix generation per pass',
)

# ============================================================================
# PATCH 5 (nat_ultra.dart) — adaptive default natWorkers
# ============================================================================
patch(
    'nat_ultra.dart',
    "int natWorkers = kNatDelayConcurrency; // locked parallel tests in national mode",
    "// NATWORKERS: adaptive by default (scales with device CPU count).\n"
    "// The actual value is recomputed per connection in _doConnect.\n"
    "int natWorkers = natAdaptiveWorkers(); // parallel tests in national mode",
    'P5 adaptive default natWorkers',
)

# ============================================================================
# PATCH 6 (main.dart) — reduce national-mode busy timeout
# ============================================================================
patch(
    'main.dart',
    "      final hardLimit = Duration(minutes: nationalMode ? 60 : 10);\n"
    "      final idleLimit = Duration(minutes: nationalMode ? 5 : 3);",
    "      // TIMEOUTREDUCE: national mode used to wait up to 60 minutes on a\n"
    "      // silent search. That is what a user sees as \"the app froze\".\n"
    "      // Now: 20 minutes hard cap, 3 minutes of no progress.\n"
    "      final hardLimit = Duration(minutes: nationalMode ? 20 : 8);\n"
    "      final idleLimit = Duration(minutes: nationalMode ? 3 : 2);",
    'P6 reduce national busy timeout',
)

# ============================================================================
# PATCH 7 (main.dart) — natWorkers adaptive in national branch of _doConnect
# ============================================================================
patch(
    'main.dart',
    "        badPingMs = max(badPingMs, 6000);\n"
    "        if (natLevel < 2) natLevel = 2;\n"
    "        natWorkers = kNatDelayConcurrency; // NATGATE: national matrix tests max 3",
    "        badPingMs = max(badPingMs, 6000);\n"
    "        if (natLevel < 2) natLevel = 2;\n"
    "        // ADAPTIVEW: scale workers with device capacity, not hardcoded 4.\n"
    "        natWorkers = natAdaptiveWorkers();",
    'P7 adaptive natWorkers in national branch',
)

# ============================================================================
# PATCH 8 (main.dart) — natWorkers adaptive in _natEscalate
# ============================================================================
patch(
    'main.dart',
    "      tcpTimeout = Duration(seconds: round >= 8 ? 10 : (round >= 4 ? 8 : 6));\n"
    "      delayTimeout = Duration(seconds: max(delayTimeout.inSeconds, round >= 8 ? 18 : 14));\n"
    "      natWorkers = kNatDelayConcurrency; // NATGATE: national matrix tests max 3",
    "      tcpTimeout = Duration(seconds: round >= 8 ? 10 : (round >= 4 ? 8 : 6));\n"
    "      delayTimeout = Duration(seconds: max(delayTimeout.inSeconds, round >= 8 ? 18 : 14));\n"
    "      // ADAPTIVEW: scale workers with device capacity in escalation too.\n"
    "      natWorkers = natAdaptiveWorkers();",
    'P8 adaptive natWorkers in _natEscalate',
)

# ============================================================================
# PATCH 9 (main.dart) — add skipEngine parameter to pickEngineThenStart
# ============================================================================
patch(
    'main.dart',
    "  Future<bool> pickEngineThenStart(Future<void> Function() start,\n"
    "      {bool askMode = true, bool? forceNet, bool keepNet = false}) async {",
    "  Future<bool> pickEngineThenStart(Future<void> Function() start,\n"
    "      {bool askMode = true, bool? forceNet, bool keepNet = false,\n"
    "      bool skipEngine = false}) async {",
    'P9 add skipEngine param',
)

# ============================================================================
# PATCH 10 (main.dart) — use skipEngine inside pickEngineThenStart
# ============================================================================
patch(
    'main.dart',
    "    final e = await pickVpnEngineDialog();\n"
    "    if (e == null) return false;\n"
    "    applyPilotEngine(e);",
    "    // ONECLICK: skipEngine=true means the main connect button has already\n"
    "    // chosen V2Ray (the only engine), so no dialog is shown to the user.\n"
    "    final e = skipEngine ? 'v2ray' : await pickVpnEngineDialog();\n"
    "    if (e == null) return false;\n"
    "    applyPilotEngine(e);",
    'P10 use skipEngine inside pickEngineThenStart',
)

# ============================================================================
# PATCH 11 (main.dart) — one-click main connect button (no dialogs)
# ============================================================================
patch(
    'main.dart',
    "                          aiSession = false;\n"
    "                          await pickEngineThenStart(() => connect(), askMode: true);",
    "                          aiSession = false;\n"
    "                          // ONECLICK: main button = one tap, no dialogs.\n"
    "                          // Advanced paths (server rows, national button)\n"
    "                          // keep their online/offline and engine dialogs.\n"
    "                          await pickEngineThenStart(() => connect(),\n"
    "                              askMode: false, skipEngine: true);",
    'P11 one-click main connect button',
)

# ============================================================================
# FINAL VERIFICATION
# ============================================================================
with open(os.path.join(LIB, 'nat_ultra.dart'), encoding='utf-8') as f:
    final_nat = f.read()
if 'bool kNatIpScanOn = true;' not in final_nat:
    print('ERROR: post-check failed: kNatIpScanOn is not true')
    sys.exit(1)
if 'int natAdaptiveWorkers()' not in final_nat:
    print('ERROR: post-check failed: natAdaptiveWorkers() not defined')
    sys.exit(1)

with open(os.path.join(LIB, 'main.dart'), encoding='utf-8') as f:
    final_main = f.read()
if 'natAdaptiveWorkers()' not in final_main:
    print('ERROR: post-check failed: natAdaptiveWorkers not used in main.dart')
    sys.exit(1)
if 'skipEngine: true' not in final_main:
    print('ERROR: post-check failed: skipEngine not wired in main.dart')
    sys.exit(1)

print('')
print('=' * 64)
print('PATCH_V3: all 11 patches applied successfully')
print('=' * 64)
