#!/usr/bin/env python3
"""Create a deterministic, secret-free manifest for KING VPN CI build outputs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Mapping


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _record(root: Path, path: Path, role: str) -> dict[str, object]:
    root = root.resolve()
    candidate = (root / path).resolve() if not path.is_absolute() else path.resolve()
    try:
        relative = candidate.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"{role} path escapes repository root: {path}") from exc
    if not candidate.is_file():
        raise FileNotFoundError(f"required {role} file is missing: {relative}")
    return {
        "role": role,
        "path": relative.as_posix(),
        "size_bytes": candidate.stat().st_size,
        "sha256": _sha256(candidate),
    }


def create_manifest(
    *,
    root: Path,
    apk: Path,
    source_archive: Path,
    dependency_lock: Path,
    symbols_dir: Path,
    toolchain_report: Path,
    output_dir: Path,
    environ: Mapping[str, str] | None = None,
) -> dict[str, object]:
    """Hash all build inputs/outputs without serializing environment secrets."""
    root = root.resolve()
    env = os.environ if environ is None else environ
    symbols_path = (root / symbols_dir).resolve()
    try:
        symbols_path.relative_to(root)
    except ValueError as exc:
        raise ValueError("symbols directory escapes repository root") from exc
    if not symbols_path.is_dir():
        raise FileNotFoundError(f"required symbols directory is missing: {symbols_dir}")

    records = [
        _record(root, apk, "apk"),
        _record(root, source_archive, "source-archive"),
        _record(root, dependency_lock, "dependency-lock"),
        _record(root, toolchain_report, "toolchain-report"),
    ]
    symbol_files = sorted(path for path in symbols_path.rglob("*") if path.is_file())
    if not symbol_files:
        raise FileNotFoundError("symbols directory contains no files")
    records.extend(_record(root, path, "obfuscation-symbol") for path in symbol_files)
    records.sort(key=lambda item: (str(item["role"]), str(item["path"])))

    manifest: dict[str, object] = {
        "schema_version": 1,
        "source": {
            "repository": env.get("GITHUB_REPOSITORY", ""),
            "commit": env.get("GITHUB_SHA", ""),
            "ref": env.get("GITHUB_REF", ""),
        },
        "workflow": {
            "name": env.get("GITHUB_WORKFLOW", ""),
            "run_id": env.get("GITHUB_RUN_ID", ""),
            "run_number": env.get("GITHUB_RUN_NUMBER", ""),
            "run_attempt": env.get("GITHUB_RUN_ATTEMPT", ""),
            "event": env.get("GITHUB_EVENT_NAME", ""),
        },
        "runner": {
            "os": env.get("RUNNER_OS", ""),
            "architecture": env.get("RUNNER_ARCH", ""),
        },
        "signing": "CI-generated Flutter debug key; not production-signed",
        "artifacts": records,
    }

    output = (root / output_dir).resolve() if not output_dir.is_absolute() else output_dir.resolve()
    try:
        output.relative_to(root)
    except ValueError as exc:
        raise ValueError("output directory escapes repository root") from exc
    output.mkdir(parents=True, exist_ok=True)
    manifest_path = output / "build-manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    sums = "".join(
        f"{item['sha256']}  {item['path']}\n" for item in records
    )
    (output / "SHA256SUMS").write_text(sums, encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--source-archive", type=Path, required=True)
    parser.add_argument("--dependency-lock", type=Path, required=True)
    parser.add_argument("--symbols-dir", type=Path, required=True)
    parser.add_argument("--toolchain-report", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    create_manifest(
        root=args.root,
        apk=args.apk,
        source_archive=args.source_archive,
        dependency_lock=args.dependency_lock,
        symbols_dir=args.symbols_dir,
        toolchain_report=args.toolchain_report,
        output_dir=args.output_dir,
    )


if __name__ == "__main__":
    main()
