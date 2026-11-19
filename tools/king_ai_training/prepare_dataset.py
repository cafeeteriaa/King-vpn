#!/usr/bin/env python3
"""Build a leak-resistant SFT dataset from reviewed, CI-green repair records.

Input JSONL fields: task, diff, ci_passed, human_reviewed,
security_scan_passed. Unreviewed, failed, malformed, duplicate, or secret-bearing
records are discarded. No API or hosted AI service is used.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from pathlib import Path

SECRET_PATTERNS = [
    re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"github_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"(?i)(api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[:=]\s*[^\s,;]+"),
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
]
MAX_TASK = 6000
MAX_DIFF = 24000


def has_secret(value: str) -> bool:
    return any(pattern.search(value) for pattern in SECRET_PATTERNS)


def prepare(source: Path, output_dir: Path, min_examples: int = 5) -> dict:
    accepted: dict[str, dict[str, str]] = {}
    rejected = 0
    for line in source.read_text(encoding="utf-8").splitlines():
        try:
            row = json.loads(line)
            task, diff = row["task"], row["diff"]
            if not isinstance(task, str) or not isinstance(diff, str):
                raise ValueError("task and diff must be strings")
            if not row.get("ci_passed") or not row.get("human_reviewed") or not row.get("security_scan_passed"):
                rejected += 1
                continue
            task, diff = task.strip(), diff.strip()
            if not task or not diff or len(task) > MAX_TASK or len(diff) > MAX_DIFF:
                rejected += 1
                continue
            if has_secret(task) or has_secret(diff):
                rejected += 1
                continue
            digest = hashlib.sha256((task + "\0" + diff).encode()).hexdigest()
            accepted[digest] = {
                "text": "<|user|>Repair task:\n" + task +
                        "\nReturn a minimal unified diff only.\n<|assistant|>\n" + diff
            }
        except (ValueError, KeyError, TypeError, json.JSONDecodeError):
            rejected += 1

    rows = list(accepted.items())
    if len(rows) < min_examples:
        raise RuntimeError(f"Only {len(rows)} trusted examples; at least {min_examples} required")
    train, evaluation = [], []
    for digest, row in rows:
        (evaluation if int(digest[:8], 16) % 10 == 0 else train).append(row)
    if not evaluation:
        evaluation.append(train.pop())
    if len(train) < 2:
        raise RuntimeError("Not enough training examples after deterministic holdout split")
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, data in (("train.jsonl", train), ("eval.jsonl", evaluation)):
        (output_dir / name).write_text(
            "".join(json.dumps(item, ensure_ascii=False) + "\n" for item in data),
            encoding="utf-8",
        )
    report = {"accepted": len(rows), "rejected": rejected,
              "train": len(train), "evaluation": len(evaluation),
              "deployment_authorized": False}
    (output_dir / "dataset_report.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--min-examples", type=int, default=5)
    args = parser.parse_args()
    print(json.dumps(prepare(args.input, args.output_dir, args.min_examples), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
