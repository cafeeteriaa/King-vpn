#!/usr/bin/env python3
"""Create a deterministic, secret-filtered ZIP of the complete King VPN source tree."""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile
import zipfile


EXCLUDED_DIRS = {
    ".git", ".dart_tool", "build", "build-evidence", "__pycache__",
    ".gradle", ".terraform", "node_modules", ".pytest_cache", ".mypy_cache",
    ".ruff_cache", ".venv", "venv", ".idea", ".ssh", ".aws", ".azure",
    ".kube", ".docker",
}
EXCLUDED_PATHS = {(".config", "gcloud"), (".config", "gh")}
EXCLUDED_FILES = {
    "local.properties", "key.properties", ".envrc", ".netrc", ".npmrc",
    ".pypirc", ".git-credentials", ".vault-token", "id_rsa", "id_dsa",
    "id_ecdsa", "id_ed25519", "google-services.json",
}
SECRET_SUFFIXES = {
    ".jks", ".keystore", ".p12", ".pfx", ".pem", ".key", ".p8",
    ".asc", ".gpg", ".pgp", ".kdbx", ".mobileprovision",
    ".provisionprofile", ".tfstate",
}
SECRET_GLOBS = (
    ".env", ".env.*", "*service-account*.json", "*service_account*.json",
    "*serviceaccount*.json", "*credential*.json", "*secret*.json",
    "*token*.json", "*private-key*", "*private_key*", "*.tfstate.*",
)
CACHE_FILES = {".flutter-plugins", ".flutter-plugins-dependencies"}
REQUIRED_FILES = (
    "lib/main.dart",
    "build_app/pubspec.lock",
    ".github/workflows/build.yml",
    "android_src/MainActivity.kt",
)
PRIVATE_KEY_HEADERS = tuple(
    b"-----BEGIN " + label + b"-----"
    for label in (
        b"PRIVATE KEY", b"RSA PRIVATE KEY", b"EC PRIVATE KEY",
        b"DSA PRIVATE KEY", b"OPENSSH PRIVATE KEY", b"PGP PRIVATE KEY BLOCK",
    )
)
SECRET_VALUE_PATTERNS = (
    re.compile(rb"(?i)(?:aws_secret_access_key|client_secret|refresh_token|private_key)\s*[:=]\s*['\"]?[A-Za-z0-9/+=._-]{20,}"),
    re.compile(rb"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"),
)


def _is_excluded(relative: PurePosixPath, is_dir: bool) -> bool:
    parts = tuple(part.casefold() for part in relative.parts)
    name = parts[-1]
    if any(part in EXCLUDED_DIRS for part in parts):
        return True
    if any(parts[index:index + 2] == path for index in range(len(parts) - 1)
           for path in EXCLUDED_PATHS):
        return True
    if is_dir:
        return False
    if name in EXCLUDED_FILES or name in CACHE_FILES:
        return True
    if name.endswith((".pyc", ".pyo", ".swp", ".tmp", "~")):
        return True
    if any(name.endswith(suffix) for suffix in SECRET_SUFFIXES):
        return True
    return any(fnmatch.fnmatchcase(name, pattern) for pattern in SECRET_GLOBS)


def _contains_secret_content(path: Path) -> bool:
    """Detect high-confidence private-key and credential signatures in arbitrary filenames."""
    overlap = b""
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                return False
            window = overlap + chunk
            if any(marker in window for marker in PRIVATE_KEY_HEADERS):
                return True
            if any(pattern.search(window) for pattern in SECRET_VALUE_PATTERNS):
                return True
            overlap = window[-256:]


def _iter_source_files(root: Path):
    """Yield safe regular files in stable order; never follow symlinks."""
    def visit(directory: Path):
        try:
            with os.scandir(directory) as scan:
                entries = sorted(scan, key=lambda item: (item.name.casefold(), item.name))
        except OSError as exc:
            raise OSError(f"cannot enumerate source directory {directory}: {exc}") from exc
        for entry in entries:
            path = Path(entry.path)
            relative = PurePosixPath(path.relative_to(root).as_posix())
            try:
                if entry.is_symlink():
                    continue
                mode = entry.stat(follow_symlinks=False).st_mode
            except OSError as exc:
                raise OSError(f"cannot inspect source entry {relative}: {exc}") from exc
            if stat.S_ISDIR(mode):
                if not _is_excluded(relative, True):
                    yield from visit(path)
            elif stat.S_ISREG(mode) and not _is_excluded(relative, False):
                resolved = path.resolve(strict=True)
                try:
                    resolved.relative_to(root)
                except ValueError as exc:
                    raise ValueError(f"source path escapes repository root: {relative}") from exc
                if not _contains_secret_content(path):
                    yield path, relative, stat.S_IMODE(mode)
    yield from visit(root)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def create_source_archive(root: Path, output: Path) -> dict[str, object]:
    root = root.resolve(strict=True)
    requested_output = output if output.is_absolute() else root / output
    if requested_output.is_symlink():
        raise ValueError("source archive output must not be a symlink")
    output = requested_output.resolve(strict=False)
    try:
        output.relative_to(root)
    except ValueError as exc:
        raise ValueError("source archive output escapes repository root") from exc
    if output == root or output.exists() and output.is_dir():
        raise ValueError("source archive output must be a file inside the repository")
    output.parent.mkdir(parents=True, exist_ok=True)

    files = [
        record for record in _iter_source_files(root)
        if record[0].resolve(strict=True) != output
    ]
    names = [relative.as_posix() for _, relative, _ in files]
    if len(names) != len(set(names)):
        raise ValueError("duplicate source archive paths detected")
    missing = sorted(set(REQUIRED_FILES) - set(names))
    if missing:
        raise FileNotFoundError("required project source files are missing: " + ", ".join(missing))

    fd, temporary_name = tempfile.mkstemp(
        prefix=f".{output.name}.", suffix=".tmp", dir=output.parent
    )
    os.close(fd)
    temporary = Path(temporary_name)
    try:
        with zipfile.ZipFile(
            temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
        ) as archive:
            for path, relative, mode in files:
                info = zipfile.ZipInfo(relative.as_posix(), date_time=(1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | mode) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                with path.open("rb") as source, archive.open(info, "w") as target:
                    for chunk in iter(lambda: source.read(1024 * 1024), b""):
                        target.write(chunk)

        with zipfile.ZipFile(temporary, "r") as archive:
            bad_member = archive.testzip()
            if bad_member is not None:
                raise ValueError(f"source archive integrity check failed: {bad_member}")
            archived = archive.infolist()
            archived_names = [item.filename for item in archived]
            if len(archived_names) != len(set(archived_names)):
                raise ValueError("source archive contains duplicate paths")
            for item in archived:
                member = PurePosixPath(item.filename)
                if member.is_absolute() or ".." in member.parts or "\\" in item.filename:
                    raise ValueError(f"unsafe source archive member: {item.filename}")
                if _is_excluded(member, False):
                    raise ValueError(f"excluded sensitive/cache file entered archive: {item.filename}")
                mode = item.external_attr >> 16
                if stat.S_ISLNK(mode):
                    raise ValueError(f"symlink entered source archive: {item.filename}")
            if not set(REQUIRED_FILES).issubset(archived_names):
                raise ValueError("source archive is missing required project files")

        os.replace(temporary, output)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass

    return {
        "archive": output.relative_to(root).as_posix(),
        "files": len(files),
        "bytes": output.stat().st_size,
        "sha256": _sha256(output),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(create_source_archive(args.root, args.output), sort_keys=True))


if __name__ == "__main__":
    main()
