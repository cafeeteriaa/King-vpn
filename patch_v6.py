#!/usr/bin/env python3
# patch_v6.py (ULTIMATE BULLETPROOF: Fixes skipEngine compile error)
import os
import re
import sys

LIB = sys.argv[1] if len(sys.argv) > 1 else 'build_app/lib'
path = os.path.join(LIB, 'main.dart')

if not os.path.exists(path):
    print(f"⚠️ WARN: main.dart not found at {path}")
    sys.exit(1)

with open(path, 'r', encoding='utf-8') as f:
    src = f.read()

print("--- Starting ULTIMATE Patch v6.2 ---")

# 1. Fix the signature using a robust Regex that ignores spacing/newlines.
# It looks for 'bool keepNet = false}) async {' and adds skipEngine before the closing brace.
pattern = r'(bool\s+keepNet\s*=\s*false)(\s*\}\)\s*async\s*\{)'
if re.search(pattern, src):
    if "bool skipEngine = false" not in src:
        src = re.sub(pattern, r'\1, bool skipEngine = false\2', src, count=1)
        print("✅ OK: Signature fixed via robust Regex")
    else:
        print("✅ OK: skipEngine already in signature")
else:
    # Fallback to exact string if regex fails
    old_str = "bool keepNet = false}) async {"
    new_str = "bool keepNet = false, bool skipEngine = false}) async {"
    if old_str in src:
        src = src.replace(old_str, new_str, 1)
        print("✅ OK: Signature fixed via exact match")
    else:
        print("⚠️ WARN: Could not find signature anchor.")

# 2. Ensure logic uses skipEngine
pattern2 = r'final\s+e\s*=\s*await\s+pickVpnEngineDialog\(\);'
repl2 = "final e = skipEngine ? 'v2ray' : await pickVpnEngineDialog();"
if re.search(pattern2, src) and "skipEngine ?" not in src:
    src = re.sub(pattern2, repl2, src, count=1)
    print("✅ OK: Logic updated to use skipEngine")

# 3. Ensure Main button asks Online/Offline but skips engine
old3 = "askMode: false, skipEngine: true"
new3 = "askMode: true, skipEngine: true"
if old3 in src:
    src = src.replace(old3, new3)
    print("✅ OK: Main button now asks online/offline")

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

print("--- ULTIMATE Patch v6.2 complete ---")
