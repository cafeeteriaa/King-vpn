#!/usr/bin/env python3
"""Configure the generated Flutter host for the pinned local llama.cpp runtime."""
from pathlib import Path
import sys

def configure(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    block = (
        "\nhooks:\n"
        "  user_defines:\n"
        "    llamadart:\n"
        "      llamadart_native_runtimes: [llama_cpp]\n"
    )
    if "llamadart_native_runtimes:" in text:
        return
    if "\nhooks:" in text or text.startswith("hooks:"):
        raise SystemExit("pubspec already has a hooks block; merge llamadart settings explicitly")
    path.write_text(text.rstrip() + "\n" + block, encoding="utf-8")
    print(f"Configured local llama.cpp native runtime in {path}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: configure_local_ai_host.py build_app/pubspec.yaml")
    configure(Path(sys.argv[1]))
