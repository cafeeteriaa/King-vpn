#!/usr/bin/env python3
"""Verify every packaged Android ELF shared library supports 16 KiB pages."""

from __future__ import annotations

import argparse
import struct
import sys
import zipfile
from pathlib import Path

PAGE_SIZE = 16 * 1024
ELF_HEADER = struct.Struct("<HHIQQQIHHHHHH")
ELF64_PROGRAM_HEADER = struct.Struct("<IIQQQQQQ")
PT_LOAD = 1
EM_AARCH64 = 183


def inspect_elf(data: bytes, label: str = "ELF") -> list[str]:
    errors: list[str] = []
    if len(data) < 16 + ELF_HEADER.size or data[:4] != b"\x7fELF":
        return [f"{label}: missing or truncated ELF header"]
    ident = data[:16]
    if ident[4] != 2:
        errors.append(f"{label}: expected ELF64 (class=2), got {ident[4]}")
    if ident[5] != 1:
        errors.append(f"{label}: expected little-endian ELF (data=1), got {ident[5]}")
    if errors:
        return errors

    fields = ELF_HEADER.unpack_from(data, 16)
    machine, phoff, ehsize, phentsize, phnum = (
        fields[1], fields[4], fields[7], fields[8], fields[9]
    )
    if machine != EM_AARCH64:
        errors.append(f"{label}: expected AArch64 (e_machine=183), got {machine}")
    if ehsize < 64:
        errors.append(f"{label}: invalid ELF header size {ehsize}")
    if phentsize < ELF64_PROGRAM_HEADER.size:
        errors.append(f"{label}: invalid program-header entry size {phentsize}")
    if phnum == 0:
        errors.append(f"{label}: no program headers")
    end = phoff + phentsize * phnum
    if phoff < 64 or end > len(data):
        errors.append(f"{label}: program-header table is outside the ELF file")
    if errors:
        return errors

    load_count = 0
    for index in range(phnum):
        offset = phoff + index * phentsize
        p_type, _flags, p_offset, p_vaddr, _paddr, _filesz, _memsz, p_align = (
            ELF64_PROGRAM_HEADER.unpack_from(data, offset)
        )
        if p_type != PT_LOAD:
            continue
        load_count += 1
        if p_align < PAGE_SIZE:
            errors.append(
                f"{label}: PT_LOAD[{index}] p_align={p_align:#x} is below 16 KiB"
            )
        elif p_align & (p_align - 1):
            errors.append(f"{label}: PT_LOAD[{index}] p_align={p_align:#x} is not a power of two")
        elif p_vaddr % p_align != p_offset % p_align:
            errors.append(
                f"{label}: PT_LOAD[{index}] p_vaddr/p_offset are not congruent modulo p_align"
            )
    if load_count == 0:
        errors.append(f"{label}: no PT_LOAD segments")
    return errors


def inspect_apk(apk_path: Path) -> tuple[int, list[str]]:
    errors: list[str] = []
    try:
        with zipfile.ZipFile(apk_path) as archive:
            libraries = [
                name for name in archive.namelist()
                if name.startswith("lib/") and name.endswith(".so")
            ]
            if not libraries:
                return 0, ["APK contains no packaged native .so libraries"]
            for name in libraries:
                try:
                    errors.extend(inspect_elf(archive.read(name), name))
                except (KeyError, OSError, zipfile.BadZipFile) as exc:
                    errors.append(f"{name}: unable to read ELF entry: {exc}")
            return len(libraries), errors
    except (OSError, zipfile.BadZipFile) as exc:
        return 0, [f"Unable to read APK {apk_path}: {exc}"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path, help="arm64 APK to validate")
    args = parser.parse_args()
    count, errors = inspect_apk(args.apk)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"OK: {count} native ELF libraries have 16 KiB-compatible PT_LOAD alignment")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
