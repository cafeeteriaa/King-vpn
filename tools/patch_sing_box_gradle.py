#!/usr/bin/env python3
"""Align pinned libbox plugin Gradle versions and Maven mirrors."""
import json
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlparse

AGP_VERSION = "9.3.1"
KOTLIN_VERSION = "2.4.20"
COMPILE_SDK = 37
MIRRORS = (
    'maven { url = uri("https://maven-central.storage-download.googleapis.com/maven2/") }',
    'maven { url = uri("https://maven.aliyun.com/repository/central/") }',
    'maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin/") }',
)

def matching_brace(text, start):
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{": depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0: return i
    return -1

def add_mirrors(text, scope):
    match = re.search(r"\b" + re.escape(scope) + r"\s*\{", text)
    if not match: raise SystemExit(f"HARD FAIL: missing {scope}")
    open_pos = match.end() - 1
    close_pos = matching_brace(text, open_pos)
    if close_pos < 0: raise SystemExit(f"HARD FAIL: malformed {scope}")
    body = text[open_pos + 1:close_pos]
    repo = re.search(r"\brepositories\s*\{", body)
    if not repo: raise SystemExit(f"HARD FAIL: no repositories in {scope}")
    repo_open = open_pos + 1 + repo.end() - 1
    repo_close = matching_brace(text, repo_open)
    if repo_close < 0: raise SystemExit(f"HARD FAIL: malformed repositories in {scope}")
    repo_body = text[repo_open + 1:repo_close]
    extra = "".join("\n        " + m for m in MIRRORS if m not in repo_body)
    return text[:repo_open + 1] + extra + text[repo_open + 1:] if extra else text

def main():
    host = Path(sys.argv[1] if len(sys.argv) > 1 else "build_app").resolve()
    config = host / ".dart_tool" / "package_config.json"
    if not config.is_file(): raise SystemExit(f"HARD FAIL: missing {config}")
    data = json.loads(config.read_text(encoding="utf-8"))
    pkg = next((p for p in data.get("packages", []) if p.get("name") == "sing_box"), None)
    if pkg is None: raise SystemExit("HARD FAIL: sing_box package missing")
    uri = urlparse(pkg.get("rootUri", ""))
    root = Path(unquote(uri.path)) if uri.scheme == "file" else (config.parent / unquote(pkg["rootUri"])).resolve()
    gradle = root / "android" / "build.gradle.kts"
    if not gradle.is_file(): raise SystemExit(f"HARD FAIL: missing {gradle}")
    text = gradle.read_text(encoding="utf-8")
    if "minSdk = 24" not in text:
        raise SystemExit("HARD FAIL: plugin minSdk changed; preserve API 24 support")
    text, a = re.subn(r'classpath\("com\.android\.tools\.build:gradle:[^"]+"\)', f'classpath("com.android.tools.build:gradle:{AGP_VERSION}")', text, count=1)
    text, k = re.subn(r'val kotlinVersion = "[^"]+"', f'val kotlinVersion = "{KOTLIN_VERSION}"', text, count=1)
    text, c = re.subn(r"compileSdk = \d+", f"compileSdk = {COMPILE_SDK}", text, count=1)
    if (a, k, c) != (1, 1, 1): raise SystemExit("HARD FAIL: unexpected plugin Gradle declarations")
    text = add_mirrors(text, "buildscript")
    text = add_mirrors(text, "allprojects")
    gradle.write_text(text, encoding="utf-8")
    check = gradle.read_text(encoding="utf-8")
    for item in (f'classpath("com.android.tools.build:gradle:{AGP_VERSION}")', f'val kotlinVersion = "{KOTLIN_VERSION}"', f"compileSdk = {COMPILE_SDK}", "minSdk = 24", *MIRRORS):
        if item not in check: raise SystemExit(f"HARD FAIL: Gradle patch verification missing {item}")
    state_file = root / "android" / "src" / "main" / "kotlin" / "com" / "qusadprod" / "sing_box" / "core" / "ServiceState.kt"
    if not state_file.is_file():
        raise SystemExit(f"HARD FAIL: missing libbox ServiceState API: {state_file}")
    state_source = state_file.read_text(encoding="utf-8")
    for private_decl, public_decl in (
        ("internal enum class ServiceStatus", "enum class ServiceStatus"),
        ("internal data class ServiceSnapshot", "data class ServiceSnapshot"),
        ("internal object ServiceState", "object ServiceState"),
    ):
        if private_decl in state_source:
            state_source = state_source.replace(private_decl, public_decl, 1)
        elif public_decl not in state_source:
            raise SystemExit(f"HARD FAIL: unexpected ServiceState declaration: {private_decl}")
    state_file.write_text(state_source, encoding="utf-8")
    print("OK: libbox Gradle aligned; minSdk 24 retained; native ServiceState exposed")

if __name__ == "__main__":
    main()
