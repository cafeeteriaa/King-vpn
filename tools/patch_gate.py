#!/usr/bin/env python3
"""Fail-closed structural gate for untrusted source-repair diffs.

Only Dart application source and test fixtures are eligible. Tooling, build
scripts, Android/native code, dependency manifests and executable/symlink modes
require an explicit owner-reviewed change outside this automatic patch path.
This gate is not an execution sandbox or a substitute for human review.
"""
from __future__ import annotations
import argparse
import re
import sys

ALLOWED_ROOTS = ('lib/', 'test/')
SECRET_PATTERNS = [
    re.compile(r'(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|private[_-]?key|password)\s*[:=]\s*["\'][^"\']{8,}'),
    re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b'),
    re.compile(r'\bAKIA[0-9A-Z]{16}\b'),
    re.compile(r'\bxox[baprs]-[A-Za-z0-9-]{20,}\b'),
]


def _validate_path(raw: str, errors: list[str], paths: set[str]) -> None:
    if raw == '/dev/null':
        return
    if raw.startswith(('a/', 'b/')):
        raw = raw[2:]
    if (not raw or raw.startswith('/') or '\\' in raw or
            any(part in ('', '.', '..') for part in raw.split('/'))):
        errors.append(f'unsafe path: {raw}')
        return
    if not raw.startswith(ALLOWED_ROOTS):
        errors.append(f'path outside allowed source roots (lib/, test/ only): {raw}')
        return
    paths.add(raw)


def validate(diff: str, max_changed_lines: int = 1200) -> list[str]:
    errors: list[str] = []
    paths: set[str] = set()
    changed = 0
    for line in diff.splitlines():
        if line.startswith(('+++ ', '--- ')):
            raw = line[4:].split('\t', 1)[0]
            # Quoted/escaped paths are rejected rather than guessed.
            if raw.startswith('"') or '"' in raw:
                errors.append('quoted or escaped diff path is not accepted')
                continue
            _validate_path(raw, errors, paths)
        elif line.startswith(('rename from ', 'rename to ', 'copy from ', 'copy to ')):
            _validate_path(line.split(' ', 2)[2], errors, paths)
        elif line.startswith(('new file mode ', 'old mode ', 'new mode ', 'deleted file mode ')):
            mode = line.rsplit(' ', 1)[-1]
            if mode in ('120000', '160000'):
                errors.append(f'symlink or submodule mode is forbidden: {mode}')
            elif mode == '100755':
                errors.append('executable file mode is forbidden for generated patches')
            elif mode != '100644':
                errors.append(f'unsupported file mode: {mode}')
        elif line == 'GIT binary patch':
            errors.append('binary patches are forbidden')
        elif line.startswith(('+', '-')) and not line.startswith(('+++', '---')):
            changed += 1
            for pattern in SECRET_PATTERNS:
                if pattern.search(line[1:]):
                    errors.append('possible secret in diff')
                    break
    if not paths:
        errors.append('diff contains no eligible source paths')
    if changed <= 0 or changed > max_changed_lines:
        errors.append(f'changed line count outside 1..{max_changed_lines}: {changed}')
    return sorted(set(errors))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('diff_file')
    parser.add_argument('--max-changed-lines', type=int, default=1200)
    args = parser.parse_args()
    with open(args.diff_file, encoding='utf-8') as handle:
        errors = validate(handle.read(), args.max_changed_lines)
    if errors:
        print('PATCH REJECTED')
        for error in errors:
            print(f'- {error}')
        return 1
    print('PATCH STRUCTURE ACCEPTED; this is not a sandbox, signature, security review or release approval.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
