#!/usr/bin/env python3
# patch_v5.py (Fixes the final skipEngine compile error)
import os
import re
import sys

LIB = sys.argv[1] if len(sys.argv) > 1 else 'build_app/lib'
path = os.path.join(LIB, 'main.dart')

if not os.path.exists(path):
    sys.exit(1)

with open(path, 'r', encoding='utf-8') as f:
    src = f.read()

print("--- Starting Patch v5 (Fixing skipEngine error) ---")

# The exact string we want to find in the signature
old1 = "{bool askMode = true, bool? forceNet, bool keepNet = false}) async {"
new1 = "{bool askMode = true, bool? forceNet, bool keepNet = false, bool skipEngine = false}) async {"

# Try exact match first
if old1 in src:
    src = src.replace(old1, new1, 1)
    print("✅ OK: skipEngine parameter added via exact match")
else:
    # Fallback to Regex if spaces are weird
    pattern = r'\{bool\s+askMode\s*=\s*true,\s*bool\?\s*forceNet,\s*bool\s+keepNet\s*=\s*false\}\)'
    if re.search(pattern, src):
        src = re.sub(pattern, new1, src, count=1)
        print("✅ OK: skipEngine parameter added via regex")
    else:
        print("⚠️ WARN: Could not find signature to add skipEngine. Already added?")
        # Check if it's already there
        if "bool skipEngine = false" in src:
            print("✅ OK: skipEngine is already present in the file.")

with open(path, 'w', encoding='utf-8') as f:
    f.write(src)

print("--- Patch v5 complete ---")
