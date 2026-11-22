#!/usr/bin/env python3
"""Prepare an untrusted source-repair patch without executing candidate code.

The temporary copy is for structural application checks only; it is NOT a
sandbox. Candidate tests, analyzers and builds must run in the isolated,
secret-free GitHub Actions pull-request runner. This tool never executes code
from the candidate patch on the developer's host.
"""
from __future__ import annotations
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = ROOT / 'tools' / 'patch_gate.py'
import importlib.util
spec = importlib.util.spec_from_file_location('patch_gate', GATE_PATH)
patch_gate = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(patch_gate)

# Kept as a manifest of the CI dependency set; this local preparer does not
# resolve or execute packages. CI owns dependency resolution and compilation.
DEPENDENCIES = [
    'http', 'flutter_v2ray_client:3.5.0', 'installed_apps:1.6.0',
    'permission_handler', 'workmanager', 'url_launcher',
    'webview_flutter', 'crypto:^3.0.3', 'flutter_secure_storage:^9.2.2',
    'local_inference:0.1.1', 'local_inference_flutter:0.1.1',
    'path_provider', 'speech_to_text:^7.4.0', 'cryptography:^2.7.0',
    'flutter_tts:^4.2.3',
]


def ensure_internal_symlinks(root: Path) -> None:
    """Reject pre-existing symlinks that would escape the copied source tree."""
    resolved_root = root.resolve()
    for current, dirs, files in os.walk(root, followlinks=False):
        for name in [*dirs, *files]:
            path = Path(current) / name
            if not path.is_symlink():
                continue
            target = (path.parent / os.readlink(path)).resolve()
            if target != resolved_root and resolved_root not in target.parents:
                raise RuntimeError(f'External symlink in source tree is not accepted: {path.relative_to(root)}')


def verify(patch_file: Path, output_patch: Path) -> dict:
    diff = patch_file.read_text(encoding='utf-8', errors='replace')
    errors = patch_gate.validate(diff)
    if errors:
        raise RuntimeError('Patch gate rejected: ' + '; '.join(errors))
    if shutil.which('git') is None:
        raise RuntimeError('Git is required for temporary patch-application validation')

    with tempfile.TemporaryDirectory(prefix='kingvpn-repair-') as tmp_name:
        tmp = Path(tmp_name) / 'source'
        ensure_internal_symlinks(ROOT)
        shutil.copytree(
            ROOT,
            tmp,
            symlinks=True,
            ignore=shutil.ignore_patterns(
                '.git', '.dart_tool', 'build', 'build_app', '__pycache__', '*.pyc',
            ),
        )
        local_patch = tmp / '.repair-candidate.patch'
        shutil.copy2(patch_file, local_patch)
        subprocess.run(
            ['git', 'apply', '--check', str(local_patch)],
            cwd=tmp,
            check=True,
            timeout=120,
        )
        subprocess.run(
            ['git', 'apply', str(local_patch)],
            cwd=tmp,
            check=True,
            timeout=120,
        )
        local_patch.unlink(missing_ok=True)
        ensure_internal_symlinks(tmp)

    output_patch.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(patch_file, output_patch)
    return {
        'status': 'pending_ci_validation',
        'source_tree_modified': False,
        'patch_exported': str(output_patch),
        'checks': ['patch_gate', 'internal_symlink_check', 'git_apply_check', 'temporary_copy_apply'],
        'candidate_code_executed_locally': False,
        'ci_required': True,
        'human_diff_review_required': True,
        'signature_verified': False,
        'security_reviewed': False,
        'device_tested': False,
        'merge_ready': False,
        'note': 'Structural preparation only. GitHub Actions must run tests, analysis and build on the exact PR head.',
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--patch', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('candidate-repair.patch'))
    parser.add_argument('--report', type=Path, default=Path('repair-preparation.json'))
    args = parser.parse_args()
    try:
        report = verify(args.patch.resolve(), args.output.resolve())
        code = 0
    except Exception as exc:
        report = {
            'status': 'rejected',
            'source_tree_modified': False,
            'patch_exported': None,
            'reason': str(exc)[:2000],
            'candidate_code_executed_locally': False,
            'ci_required': False,
            'device_tested': False,
            'merge_ready': False,
        }
        code = 1
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return code


if __name__ == '__main__':
    sys.exit(main())
