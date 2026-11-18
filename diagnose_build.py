#!/usr/bin/env python3
"""Turn Flutter/Dart/Gradle logs into a bounded source-repair diagnostic report."""
from __future__ import annotations
import argparse
import json
import re
from pathlib import Path

PATTERNS = [
    ('dart_compile', re.compile(r"Error: (?:[A-Z][A-Za-z]+Error|The method|Undefined name|A value of type|Couldn't find|Expected)")),
    ('dart_analyzer', re.compile(r"\berror • .+ • .+\.dart:\d+:\d+")),
    ('flutter_test', re.compile(r"Some tests failed|Test failed|Expected:|Actual:|Exception caught by flutter test framework")),
    ('pub_resolution', re.compile(r"version solving failed|Because .+ depends on .+ version|pub get failed")),
    ('gradle', re.compile(r"FAILURE: Build failed|Execution failed for task|Could not resolve all files")),
    ('plugin_channel', re.compile(r"MissingPluginException|No implementation found for method")),
    ('jni_native', re.compile(r"UnsatisfiedLinkError|dlopen failed|No implementation found for")),
    ('manifest_permission', re.compile(r"Manifest merger failed|uses-sdk:minSdkVersion|foregroundServiceType")),
    ('resource_memory', re.compile(r"OutOfMemoryError|GC overhead limit exceeded|Java heap space")),
]
LOCATION = re.compile(r"(?P<file>(?:[A-Za-z0-9_./-]+)\.dart):(?P<line>\d+):(?P<column>\d+)")
STACK = re.compile(r"^\s*#\d+\s+(.+)$")


def analyze_logs(paths: list[Path]) -> dict:
    findings = []
    seen = set()
    for path in paths:
        if not path.is_file():
            continue
        try:
            lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
        except OSError:
            continue
        for index, line in enumerate(lines):
            categories = [name for name, pattern in PATTERNS if pattern.search(line)]
            if not categories:
                continue
            location = LOCATION.search(line)
            key = (str(path), index + 1, line.strip())
            if key in seen:
                continue
            seen.add(key)
            frames = []
            for candidate in lines[index + 1:index + 9]:
                match = STACK.match(candidate)
                if match:
                    frames.append(match.group(1)[:300])
            findings.append({
                'log': str(path),
                'log_line': index + 1,
                'categories': categories,
                'source_file': location.group('file') if location else None,
                'source_line': int(location.group('line')) if location else None,
                'source_column': int(location.group('column')) if location else None,
                'message': line.strip()[:1000],
                'stack_frames': frames,
            })
    return {
        'schema': 'kingvpn.repair-diagnostics.v1',
        'finding_count': len(findings),
        'findings': findings[:500],
        'safety': {
            'source_files_modified': False,
            'patch_generated': False,
            'credentials_collected': False,
            'note': 'این گزارش فقط شواهد خطا را استخراج می‌کند؛ Patch باید جداگانه تولید، بازبینی و آزمایش شود.',
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('logs', nargs='+', type=Path)
    parser.add_argument('--output', type=Path, default=Path('repair-diagnostics.json'))
    args = parser.parse_args()
    report = analyze_logs(args.logs)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"Wrote {report['finding_count']} findings to {args.output}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
