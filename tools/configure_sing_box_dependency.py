#!/usr/bin/env python3
"""Pin the reviewed libbox Flutter plugin in the generated Android host."""
from pathlib import Path
import sys

PLUGIN_URL = "https://github.com/QUSAD-prod/sing_box.git"
PLUGIN_REF = "72f76fb714e07637a560774a7f2fdd3ae11884c4"

def main():
    pubspec = Path(sys.argv[1] if len(sys.argv) > 1 else "pubspec.yaml")
    if not pubspec.is_file():
        raise SystemExit(f"pubspec not found: {pubspec}")
    source = pubspec.read_text(encoding="utf-8")
    block = (
        "  sing_box:\n"
        "    git:\n"
        f"      url: {PLUGIN_URL}\n"
        f"      ref: {PLUGIN_REF}\n"
    )
    if "  sing_box:" in source:
        if block not in source:
            raise SystemExit("HARD FAIL: sing_box exists but is not pinned to reviewed commit")
    else:
        if source.count("dependencies:\n") != 1:
            raise SystemExit("HARD FAIL: expected one dependencies block")
        pubspec.write_text(source.replace("dependencies:\n", "dependencies:\n" + block, 1), encoding="utf-8")
    print(f"OK: sing_box pinned to {PLUGIN_REF}")

if __name__ == "__main__":
    main()
