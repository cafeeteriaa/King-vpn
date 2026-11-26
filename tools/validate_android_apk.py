#!/usr/bin/env python3
"""Verify that a release APK contains the real native VPN engines for its ABI.

This is a packaging/integrity check, not a claim that a VPN tunnel connects.
It deliberately has no size, count, protocol, or feature allow/deny limits.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
import zipfile
from pathlib import Path

REQUIRED_NATIVE_LIBRARIES = {
    "libbox.so": "sing-box/libbox",
    "libv2jni.so": "Xray/V2Ray",
    "libwg-go.so": "WireGuard userspace",
    "libwg.so": "WireGuard native support",
    "libwg-quick.so": "WireGuard quick support",
}
ARM64_PREFIX = "lib/arm64-v8a/"
ELF_MAGIC = b"\x7fELF"
EM_AARCH64 = 183


class ApkValidationError(RuntimeError):
    pass


def _check_elf64_aarch64(name: str, payload: bytes) -> None:
    if len(payload) < 20 or payload[:4] != ELF_MAGIC:
        raise ApkValidationError(f"{name}: missing ELF header")
    if payload[4] != 2:
        raise ApkValidationError(f"{name}: expected 64-bit ELF class")
    if payload[5] != 1:
        raise ApkValidationError(f"{name}: expected little-endian ELF")
    machine = struct.unpack_from("<H", payload, 18)[0]
    if machine != EM_AARCH64:
        raise ApkValidationError(
            f"{name}: expected AArch64 machine {EM_AARCH64}, got {machine}"
        )


def validate_apk(apk_path: Path) -> dict:
    if not apk_path.is_file() or apk_path.stat().st_size == 0:
        raise ApkValidationError(f"APK is missing or empty: {apk_path}")

    try:
        with zipfile.ZipFile(apk_path) as archive:
            names = archive.namelist()
            duplicates = sorted({name for name in names if names.count(name) > 1})
            if duplicates:
                raise ApkValidationError(
                    "APK contains duplicate ZIP entries: " + ", ".join(duplicates)
                )
            corrupt = archive.testzip()
            if corrupt:
                raise ApkValidationError(f"APK ZIP integrity check failed at {corrupt}")

            required_entries = {"AndroidManifest.xml", "classes.dex"}
            missing_entries = sorted(required_entries.difference(names))
            if missing_entries:
                raise ApkValidationError(
                    "APK is missing required Android entries: "
                    + ", ".join(missing_entries)
                )

            native_entries = sorted(
                name for name in names
                if name.startswith("lib/") and name.endswith(".so")
            )
            if not native_entries:
                raise ApkValidationError("APK contains no native shared libraries")

            wrong_abi = [
                name for name in native_entries
                if not name.startswith(ARM64_PREFIX)
            ]
            if wrong_abi:
                raise ApkValidationError(
                    "arm64 split contains native libraries for other ABIs: "
                    + ", ".join(wrong_abi)
                )

            native_names = {Path(name).name for name in native_entries}
            missing_libraries = sorted(
                set(REQUIRED_NATIVE_LIBRARIES).difference(native_names)
            )
            if missing_libraries:
                raise ApkValidationError(
                    "APK is missing required native engine libraries: "
                    + ", ".join(missing_libraries)
                )

            native_details = []
            for name in native_entries:
                payload = archive.read(name)
                _check_elf64_aarch64(name, payload)
                native_details.append({
                    "path": name,
                    "size_bytes": len(payload),
                    "sha256": hashlib.sha256(payload).hexdigest(),
                })
    except zipfile.BadZipFile as exc:
        raise ApkValidationError(f"Invalid APK ZIP archive: {exc}") from exc

    digest = hashlib.sha256()
    with apk_path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)

    return {
        "result": "PASS",
        "check_scope": "APK package and native ELF integrity; not device connectivity",
        "apk": apk_path.name,
        "apk_size_bytes": apk_path.stat().st_size,
        "apk_sha256": digest.hexdigest(),
        "abi": "arm64-v8a",
        "required_engine_libraries": REQUIRED_NATIVE_LIBRARIES,
        "native_library_count": len(native_details),
        "native_libraries": native_details,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--json-report", type=Path)
    args = parser.parse_args()
    try:
        report = validate_apk(args.apk)
    except ApkValidationError as exc:
        print(f"APK VALIDATION FAILED: {exc}", file=sys.stderr)
        return 1

    rendered = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.json_report:
        args.json_report.parent.mkdir(parents=True, exist_ok=True)
        args.json_report.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
