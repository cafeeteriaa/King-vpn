#!/usr/bin/env python3
"""Collect a narrowly allowlisted, merged, CI-green repair PR as an SFT record.

Uses only Python's standard library. Requires GITHUB_TOKEN, GITHUB_REPOSITORY,
and GITHUB_EVENT_PATH supplied by the GitHub Actions workflow.
"""
from __future__ import annotations
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ALLOWED_PATHS = {
    "lib/king_ai_ci_policy.dart",
    "lib/king_ai_research_policy.dart",
    "test/king_ai_ci_policy_test.dart",
    "test/king_ai_research_policy_test.dart",
}
MAX_TASK = 6000
MAX_DIFF = 24000
SECRET_PATTERNS = [
    re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"github_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"(?i)(api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[:=]\s*[^\s,;]+"),
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
]


def secret_free(value: str) -> bool:
    return not any(pattern.search(value) for pattern in SECRET_PATTERNS)


def github_get(url: str, token: str):
    request = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "King-VPN-Repair-Dataset-Collector",
    })
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def collect(event: dict, repository: str, token: str, output: Path) -> dict:
    pull = event.get("pull_request") or {}
    if not pull.get("merged") or pull.get("base", {}).get("ref") != "main":
        return {"status": "skipped", "reason": "PR is not merged into main"}
    head = pull.get("head") or {}
    base = pull.get("base") or {}
    if head.get("ref", "").startswith("king-ai/") is False:
        return {"status": "skipped", "reason": "Not a King AI branch"}
    if head.get("repo", {}).get("full_name") != repository or base.get("repo", {}).get("full_name") != repository:
        return {"status": "skipped", "reason": "Fork or cross-repository PR"}
    number = pull.get("number")
    sha = head.get("sha")
    if not isinstance(number, int) or not isinstance(sha, str):
        return {"status": "skipped", "reason": "Missing PR identity"}

    api = f"https://api.github.com/repos/{repository}"
    files = github_get(f"{api}/pulls/{number}/files?per_page=100", token)
    if not isinstance(files, list) or not 1 <= len(files) <= 3:
        return {"status": "skipped", "reason": "Changed-file count outside allowlist"}
    if any(item.get("filename") not in ALLOWED_PATHS or not item.get("patch") for item in files):
        return {"status": "skipped", "reason": "Changed files outside explicit allowlist or patch unavailable"}

    checks = github_get(f"{api}/commits/{sha}/check-runs?per_page=100", token)
    check_runs = checks.get("check_runs") or []
    if not check_runs or any(
        check.get("status") != "completed" or check.get("conclusion") != "success"
        for check in check_runs
    ):
        return {"status": "skipped", "reason": "Not every check on exact head SHA succeeded"}

    task = (str(pull.get("title") or "") + "\n" + str(pull.get("body") or ""))[:MAX_TASK].strip()
    diff = "\n\n".join(
        f"FILE: {item['filename']}\n{item['patch']}" for item in files
    )
    if not task or not diff or len(diff) > MAX_DIFF:
        return {"status": "skipped", "reason": "Task or patch is empty/oversized"}
    if not secret_free(task) or not secret_free(diff):
        return {"status": "skipped", "reason": "Secret scan rejected the repair"}

    output.parent.mkdir(parents=True, exist_ok=True)
    existing = output.read_text(encoding="utf-8").splitlines() if output.exists() else []
    for line in existing:
        try:
            if json.loads(line).get("commit_sha") == sha:
                return {"status": "duplicate", "commit_sha": sha}
        except (ValueError, TypeError):
            continue

    record = {
        "task": task,
        "diff": diff,
        "ci_passed": True,
        "merged": True,
        "human_reviewed": False,
        "security_scan_passed": True,
        "commit_sha": sha,
        "pull_number": number,
    }
    with output.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(record, ensure_ascii=False) + "\n")
    return {"status": "collected", "pull_number": number, "commit_sha": sha}


def main() -> int:
    token = os.environ.get("GITHUB_TOKEN", "")
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    event_path = os.environ.get("GITHUB_EVENT_PATH", "")
    if not token or not repository or not event_path:
        raise RuntimeError("Required GitHub Actions environment is missing")
    event = json.loads(Path(event_path).read_text(encoding="utf-8"))
    output = Path("data/king_ai_accepted_repairs.jsonl")
    print(json.dumps(collect(event, repository, token, output), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, urllib.error.URLError, RuntimeError) as error:
        print(f"Dataset collection failed safely: {error}", file=sys.stderr)
        raise SystemExit(1)
