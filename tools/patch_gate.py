#!/usr/bin/env python3
"""Conservative gate for source-repair patches proposed by an external agent.

This tool validates a unified diff only. It never applies patches or deploys APKs.
The CI pipeline remains responsible for tests, analysis, build and signed release.
"""
from __future__ import annotations
import argparse
import re
import sys

PROTECTED = {
    'android/app/src/main/AndroidManifest.xml',
    'android/app/build.gradle',
    'android/app/build.gradle.kts',
    'android/build.gradle',
    'android/build.gradle.kts',
    'android/settings.gradle',
    'android/settings.gradle.kts',
    'android/gradle.properties',
    'android/gradle/wrapper/gradle-wrapper.properties',
    'pubspec.yaml',
    'pubspec.lock',
}
ALLOWED_ROOTS = ('lib/', 'test/', 'tools/')
SECRET_PATTERNS = [
    re.compile(r'(?i)(api[_-]?key|access[_-]?token|client[_-]?secret|private[_-]?key)\s*[:=]\s*["\'][^"\']{12,}'),
    re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
]


def validate(diff: str, max_changed_lines: int | None = None) -> list[str]:
    errors: list[str] = []
    paths: set[str] = set()
    changed = 0
    for line in diff.splitlines():
        if line.startswith(('+++ ', '--- ')):
            raw = line[4:].split('\t', 1)[0]
            if raw == '/dev/null':
                continue
            if raw.startswith(('a/', 'b/')):
                raw = raw[2:]
            if (raw.startswith('/') or '\\' in raw or
                    any(part in ('', '.', '..') for part in raw.split('/'))):
                errors.append(f'unsafe path: {raw}')
            elif not raw.startswith(ALLOWED_ROOTS):
                errors.append(f'path outside allowed source roots: {raw}')
            paths.add(raw)
        elif line.startswith(('+', '-')) and not line.startswith(('+++', '---')):
            changed += 1
            for pattern in SECRET_PATTERNS:
                if pattern.search(line[1:]):
                    errors.append('possible secret in diff')
                    break
    for path in sorted(paths):
        if path in PROTECTED or path.startswith((
            'android/app/src/main/java/', 'android/app/src/main/kotlin/'
        )):
            errors.append(f'protected file requires human review: {path}')
    if changed <= 0:
        errors.append(f'patch contains no changed lines: {changed}')
    if max_changed_lines is not None and changed > max_changed_lines:
        errors.append(f'changed line count exceeds explicitly configured limit {max_changed_lines}: {changed}')
    return sorted(set(errors))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('diff_file')
    parser.add_argument('--max-changed-lines', type=int, default=None,
                        help='Optional operator-selected guard; no default changed-line ceiling.')
    args = parser.parse_args()
    with open(args.diff_file, encoding='utf-8') as handle:
        errors = validate(handle.read(), args.max_changed_lines)
    if errors:
        print('PATCH REJECTED')
        for error in errors:
            print(f'- {error}')
        return 1
    print('PATCH STRUCTURE ACCEPTED; tests, review, signature and rollback are still required.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
