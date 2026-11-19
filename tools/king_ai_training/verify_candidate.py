#!/usr/bin/env python3
"""Verify the SHA-256 manifest of a local King AI training candidate."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path


def verify(candidate_dir: Path) -> dict:
    root = candidate_dir.resolve()
    report_path = root / "training_report.json"
    if not report_path.is_file():
        raise RuntimeError("training_report.json is missing")
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report.get("status") != "candidate_trained" or report.get("deployment_authorized") is not False:
        raise RuntimeError("Candidate report has an invalid status or deployment flag")
    manifest = report.get("files_sha256")
    if not isinstance(manifest, dict) or not manifest:
        raise RuntimeError("Candidate SHA-256 manifest is empty")
    verified = 0
    for relative, expected in manifest.items():
        rel = Path(relative)
        if rel.is_absolute() or ".." in rel.parts or not isinstance(expected, str):
            raise RuntimeError(f"Unsafe manifest entry: {relative!r}")
        path = (root / rel).resolve()
        if root not in path.parents or not path.is_file():
            raise RuntimeError(f"Candidate file is missing or escapes directory: {relative}")
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != expected:
            raise RuntimeError(f"SHA-256 mismatch: {relative}")
        verified += 1
    return {"status": "verified", "files": verified, "deployment_authorized": False}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate-dir", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.candidate_dir), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
