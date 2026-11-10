#!/usr/bin/env python3
# patch_v4.py (Fixes the 5 skipped patches from v3 using Regex)
import os
import re
import sys

LIB = sys.argv[1] if len(sys.argv) > 1 else 'build_app/lib'
if not os.path.isdir(LIB):
    sys.exit(1)

def safe_regex(fname, pattern, repl, label):
    path = os.path.join(LIB, fname)
    if not os.path.exists(path):
        print(f"⚠️ WARN: {fname} not found. {label}")
        return
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    if re.search(pattern, src):
        src = re.sub(pattern, repl, src, count=1)
        with open(path, 'w', encoding='utf-8') as f:
            f.write(src)
        print(f"✅ OK: [{label}] applied to {fname}")
    else:
        print(f"⚠️ WARN: [{label}] anchor not found in {fname}")

print("--- Starting Patch v4 (Fixing skipped patches) ---")

# Fix P5: Adaptive workers in nat_ultra.dart
safe_regex('nat_ultra.dart',
    r'int\s+natWorkers\s*=\s*kNatDelayConcurrency\s*;',
    'int natWorkers = natAdaptiveWorkers();',
    'P5 Adaptive default natWorkers')

# Fix P7: skipEngine param in main.dart signature
safe_regex('main.dart',
    r'\{bool\s+askMode\s*=\s*true,\s*bool\?\s*forceNet,\s*bool\s+keepNet\s*=\s*false\}\)',
    '{bool askMode = true, bool? forceNet, bool keepNet = false, bool skipEngine = false})',
    'P7 Add skipEngine param')

# Fix P8: Use skipEngine in main.dart logic
safe_regex('main.dart',
    r'final\s+e\s*=\s*await\s+pickVpnEngineDialog\(\);',
    "final e = skipEngine ? 'v2ray' : await pickVpnEngineDialog();",
    'P8 Use skipEngine in logic')

# Fix P9: One-click UI button in main.dart
safe_regex('main.dart',
    r'await\s+pickEngineThenStart\(\(\)\s*=>\s*connect\(\),\s*askMode:\s*true\);',
    "await pickEngineThenStart(() => connect(), askMode: false, skipEngine: true);",
    'P9 One-click UI button')

# Fix P25: auto_test reset helper call
safe_regex('auto_test.dart',
    r"(_atVerdict\s*=\s*'';\s*)_atCoreDeadStreak\s*=\s*0\s*;",
    r"\1_resetCoreDeadStreak();",
    'P25 auto_test call reset helper')

print("--- Patch v4 complete ---")
