#!/usr/bin/env python3
# patch_v6.py (ULTIMATE MERGED: Fixes compile error + Smart Network Titles + Dialogs)
import os
import re
import sys

LIB = sys.argv[1] if len(sys.argv) > 1 else 'build_app/lib'
path = os.path.join(LIB, 'main.dart')

if not os.path.exists(path):
    sys.exit(1)

with open(path, 'r', encoding='utf-8') as f:
    src = f.read()

print("--- Starting ULTIMATE Patch v6 (Compile Fix + Dialogs) ---")

# 1. Fix the signature to include `skipEngine` (THE COMPILE ERROR)
pattern = r'Future<bool>\s+pickEngineThenStart\(Future<void>\s+Function\(\)\s+start,\s*\{bool\s+askMode\s*=\s*true,\s*bool\?\s*forceNet,\s*bool\s+keepNet\s*=\s*false\}\)\s+async\s*\{'
repl = 'Future<bool> pickEngineThenStart(Future<void> Function() start,\n      {bool askMode = true, bool? forceNet, bool keepNet = false, bool skipEngine = false}) async {'
if re.search(pattern, src):
    src = re.sub(pattern, repl, src, count=1)
    print("✅ OK: Signature fixed (skipEngine added via Regex)")
elif "bool skipEngine = false" in src:
    print("✅ OK: Signature already had skipEngine")
else:
    print("⚠️ WARN: Could not find signature with regex.")

# 2. Fix the logic to use `skipEngine`
pattern2 = r'final\s+e\s*=\s*await\s+pickVpnEngineDialog\(\);'
repl2 = "final e = skipEngine ? 'v2ray' : await pickVpnEngineDialog();"
if re.search(pattern2, src) and "skipEngine ?" not in src:
    src = re.sub(pattern2, repl2, src, count=1)
    print("✅ OK: Logic updated to use skipEngine")

# 3. Fix the UI button to ask Online/Offline, but skip engine
pattern3 = r'await\s+pickEngineThenStart\(\(\)\s*=>\s*connect\(\),\s*askMode:\s*false,\s*skipEngine:\s*true\);'
repl3 = "await pickEngineThenStart(() => connect(), askMode: true, skipEngine: true);"
if re.search(pattern3, src):
    src = re.sub(pattern3, repl3, src, count=1)
    print("✅ OK: Main button now asks online/offline")
else:
    # Fallback for exact string
    src = src.replace("askMode: false, skipEngine: true", "askMode: true, skipEngine: true")

# 4. Smart Dialog Titles (National vs Global)
src = src.replace("Future<String?> _pickOnlineOffline() async {", "Future<String?> _pickOnlineOffline({bool isNational = false}) async {")
src = src.replace("title: const Text('نوع اتصال'),", "title: Text(isNational ? 'نوع اتصال (نت ملی)' : 'نوع اتصال (نت جهانی)'),")
src = src.replace("Future<bool> _askOnlineOfflineMode() async {", "Future<bool> _askOnlineOfflineMode({bool isNational = false}) async {")
src = src.replace("var mode = await _pickOnlineOffline();", "var mode = await _pickOnlineOffline(isNational: isNational);")
src = src.replace("final ok = await _askOnlineOfflineMode();", "final ok = await _askOnlineOfflineMode(isNational: net);")
print("✅ OK: Smart Dialog Titles applied")

# 5. Force Pilot to ask Global
src = src.replace("await pickEngineThenStart(startGrokPilot, keepNet: true);", "await pickEngineThenStart(startGrokPilot, forceNet: false);")
src = src.replace("await pickEngineThenStart(() async { startLocalPilot(); }, keepNet: true);", "await pickEngineThenStart(() async { startLocalPilot(); }, forceNet: false);")
print("✅ OK: Pilots forced to ask Global")

with open(path, 'w', encoding='utf-8') as f:
    f.write(src)

print("--- ULTIMATE Patch v6 complete ---")
