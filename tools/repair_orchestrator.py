#!/usr/bin/env python3
"""Apply and verify a proposed source-repair patch in a disposable copy.

The original source tree is never modified. A patch is exported as verified
only after the complete Flutter/Android validation pipeline succeeds.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = ROOT / 'tools' / 'patch_gate.py'
spec = importlib.util.spec_from_file_location('patch_gate', GATE_PATH)
patch_gate = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(patch_gate)

DEPENDENCIES = [
    'http', 'flutter_v2ray_client:3.5.0', 'installed_apps:1.6.0',
    'permission_handler', 'workmanager', 'url_launcher', 'webview_flutter',
    'crypto:^3.0.3', 'flutter_secure_storage:^9.2.2', 'local_inference:0.1.1', 'local_inference_flutter:0.1.1', 'path_provider', 'speech_to_text:^7.4.0', 'cryptography:^2.7.0', 'flutter_tts:^4.2.3',
]


def run(command: list[str], cwd: Path, timeout: int = 1800) -> None:
    print('+', ' '.join(command), flush=True)
    subprocess.run(command, cwd=cwd, check=True, timeout=timeout)


def verify(patch_file: Path, output_patch: Path) -> dict:
    diff = patch_file.read_text(encoding='utf-8', errors='replace')
    errors = patch_gate.validate(diff)
    if errors:
        raise RuntimeError('Patch gate rejected: ' + '; '.join(errors))
    if shutil.which('flutter') is None or shutil.which('git') is None:
        raise RuntimeError('Flutter SDK and Git are required for isolated source repair validation')

    with tempfile.TemporaryDirectory(prefix='kingvpn-repair-') as tmp_name:
        tmp = Path(tmp_name) / 'source'
        shutil.copytree(ROOT, tmp, ignore=shutil.ignore_patterns(
            '.git', '.dart_tool', 'build', 'build_app', '__pycache__', '*.pyc',
        ))
        local_patch = tmp / '.repair-candidate.patch'
        shutil.copy2(patch_file, local_patch)
        run(['git', 'apply', '--check', str(local_patch)], tmp)
        run(['git', 'apply', str(local_patch)], tmp)
        local_patch.unlink(missing_ok=True)

        run(['python3', '-m', 'unittest', 'discover', '-s', 'test', '-p', 'test_*.py'], tmp)
        run(['flutter', 'create', '--project-name', 'king_vpn', '--org', 'com.kingvpn',
             '--platforms=android', 'build_app'], tmp, timeout=600)
        build_app = tmp / 'build_app'
        (build_app / 'android' / 'app' / 'libs').mkdir(parents=True, exist_ok=True)
        (build_app / 'test').mkdir(parents=True, exist_ok=True)
        (build_app / 'test' / 'widget_test.dart').unlink(missing_ok=True)
        shutil.copytree(tmp / 'lib', build_app / 'lib', dirs_exist_ok=True)
        shutil.copytree(tmp / 'test', build_app / 'test', dirs_exist_ok=True)
        run(['python3', 'prepare_android.py'], tmp)
        run(['python3', 'tools/configure_local_ai_host.py', 'build_app/pubspec.yaml'], tmp)
        run(['flutter', 'pub', 'add', *DEPENDENCIES], build_app, timeout=900)
        run(['flutter', 'pub', 'get'], build_app, timeout=900)
        run(['python3', '../patch_plugin.py'], build_app)
        # Match the CI normalization for the selected V2Ray plugin only.
        pub_cache = Path(os.environ.get('PUB_CACHE', str(Path.home() / '.pub-cache')))
        for gradle_file in pub_cache.rglob('*'):
            if gradle_file.name not in ('build.gradle', 'build.gradle.kts') or 'flutter_v2ray_client' not in str(gradle_file):
                continue
            try:
                content = gradle_file.read_text(encoding='utf-8')
                content = re.sub(r'compileSdk(Version)?[\s]*=?[\s]*[0-9]+', 'compileSdk = 35', content)
                content = re.sub(r'compileSdkVersion[\s]+[0-9]+', 'compileSdkVersion 35', content)
                gradle_file.write_text(content, encoding='utf-8')
            except OSError:
                pass
        run(['flutter', 'test'], build_app, timeout=900)
        run(['flutter', 'analyze', '--no-fatal-warnings', '--no-fatal-infos'], build_app, timeout=900)
        run(['flutter', 'build', 'apk', '--debug', '--target-platform', 'android-arm64'],
            build_app, timeout=1800)

    output_patch.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(patch_file, output_patch)
    return {
        'status': 'verified',
        'source_tree_modified': False,
        'patch_exported': str(output_patch),
        'checks': ['patch_gate', 'python_tests', 'flutter_test', 'flutter_analyze', 'android_arm64_debug_build'],
        'device_tested': False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--patch', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('verified-repair.patch'))
    parser.add_argument('--report', type=Path, default=Path('repair-verification.json'))
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
            'device_tested': False,
        }
        code = 1
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return code


if __name__ == '__main__':
    sys.exit(main())
