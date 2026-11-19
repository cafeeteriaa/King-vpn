#!/usr/bin/env python3
"""Collect a narrowly allowlisted, merged, CI-green repair PR as an SFT record.

Uses only Python's standard library. Requires GITHUB_TOKEN, GITHUB_REPOSITORY,
and GITHUB_EVENT_PATH supplied by the GitHub Actions workflow.
"""
from __future__ import annotations
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.request
import urllib.parse
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
    re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{20,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"AIza[0-9A-Za-z_-]{30,}"),
    re.compile(r"sk-[A-Za-z0-9_-]{20,}"),
    re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}"),
    re.compile(r"(?i)\bBasic\s+[A-Za-z0-9+/]{12,}={0,2}"),
    re.compile(r"https?://[^/\s:@]+:[^@\s]+@"),
    re.compile(r"(?i)(api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[:=]\s*[^\s,;]+"),
    re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----"),

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

    reviews = github_get(f"{api}/pulls/{number}/reviews?per_page=100", token)
    author = pull.get("user")
    author_login = author.get("login") if isinstance(author, dict) else None
    latest_reviews: dict[str, dict] = {}
    if isinstance(reviews, list):
        for review in reviews:
            if not isinstance(review, dict):
                continue
            user = review.get("user")
            login = user.get("login") if isinstance(user, dict) else None
            submitted_at = review.get("submitted_at")
            if not isinstance(login, str) or not login or not isinstance(submitted_at, str):
                continue
            previous = latest_reviews.get(login)
            if previous is None or submitted_at >= previous.get("submitted_at", ""):
                latest_reviews[login] = review
    if not any(
        review.get("state") == "APPROVED"
        and review.get("commit_id") == sha
        and (review.get("user") or {}).get("type") == "User"
        and (review.get("user") or {}).get("login") != author_login
        for review in latest_reviews.values()
    ):
        return {"status": "skipped", "reason": "No current independent human approval for the exact head SHA"}

    task = (str(pull.get("title") or "") + "\n" + str(pull.get("body") or ""))[:MAX_TASK].strip()
    merge_sha = pull.get("merge_commit_sha")
    if not isinstance(merge_sha, str) or not merge_sha:
        return {"status": "skipped", "reason": "Missing merge commit SHA"}
    merge_commit = github_get(f"{api}/commits/{merge_sha}", token)
    parents = merge_commit.get("parents") or []
    if not parents or not isinstance(parents[0].get("sha"), str):
        return {"status": "skipped", "reason": "Cannot identify pre-merge base commit"}
    base_sha = parents[0]["sha"]
    source_files = {}
    changes = {}
    total_chars = len(task)
    for item in files:
        path = item["filename"]
        encoded_path = urllib.parse.quote(path, safe="/")
        old_file = github_get(f"{api}/contents/{encoded_path}?ref={base_sha}", token)
        new_file = github_get(f"{api}/contents/{encoded_path}?ref={sha}", token)
        if old_file.get("encoding") != "base64" or new_file.get("encoding") != "base64":
            return {"status": "skipped", "reason": "GitHub did not return base64 source contents"}
        try:
            old_content = base64.b64decode(old_file.get("content", "")).decode("utf-8")
            new_content = base64.b64decode(new_file.get("content", "")).decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            return {"status": "skipped", "reason": "Changed file is not valid UTF-8 text"}
        if len(old_content) > 20000 or len(new_content) > MAX_DIFF:
            return {"status": "skipped", "reason": "Source or replacement file is oversized"}
        source_files[path] = old_content
        changes[path] = new_content
        total_chars += len(old_content) + len(new_content)
    if not task or not source_files or total_chars > 48000:
        return {"status": "skipped", "reason": "Task or source/target context is empty/oversized"}
    all_text = task + "\n" + json.dumps(source_files, ensure_ascii=False) + "\n" + json.dumps(changes, ensure_ascii=False)
    if not secret_free(all_text):
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
        "source_files": source_files,
        "changes": changes,
        "ci_passed": True,
        "merged": True,
        "human_reviewed": True,
        "secret_scan_passed": True,
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
