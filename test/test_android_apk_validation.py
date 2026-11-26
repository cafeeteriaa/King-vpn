import json
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from tools.validate_android_apk import (
    ApkValidationError,
    REQUIRED_NATIVE_LIBRARIES,
    validate_apk,
)


def elf64_aarch64():
    header = bytearray(64)
    header[:4] = b"\x7fELF"
    header[4] = 2
    header[5] = 1
    struct.pack_into("<H", header, 18, 183)
    return bytes(header)


class AndroidApkValidationTests(unittest.TestCase):
    def create_apk(self, root, missing=(), wrong_abi=()):
        apk = root / "test.apk"
        with zipfile.ZipFile(apk, "w") as archive:
            archive.writestr("AndroidManifest.xml", b"manifest")
            archive.writestr("classes.dex", b"dex")
            for library in REQUIRED_NATIVE_LIBRARIES:
                if library in missing:
                    continue
                path = (
                    f"lib/x86_64/{library}"
                    if library in wrong_abi
                    else f"lib/arm64-v8a/{library}"
                )
                archive.writestr(path, elf64_aarch64())
            archive.writestr("lib/arm64-v8a/libextra-feature.so", elf64_aarch64())
        return apk

    def test_accepts_required_native_cores_and_preserves_extra_libraries(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = self.create_apk(Path(directory))
            report = validate_apk(apk)
            self.assertEqual(report["result"], "PASS")
            self.assertGreaterEqual(report["native_library_count"], 6)
            self.assertIn(
                "lib/arm64-v8a/libextra-feature.so",
                [item["path"] for item in report["native_libraries"]],
            )
            self.assertEqual(len(report["apk_sha256"]), 64)

    def test_fails_when_a_required_engine_library_is_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = self.create_apk(Path(directory), missing={"libbox.so"})
            with self.assertRaisesRegex(ApkValidationError, "libbox.so"):
                validate_apk(apk)

    def test_fails_when_arm64_split_contains_another_abi(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = self.create_apk(Path(directory), wrong_abi={"libv2jni.so"})
            with self.assertRaisesRegex(ApkValidationError, "other ABIs"):
                validate_apk(apk)

    def test_fails_on_wrong_elf_machine(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = self.create_apk(Path(directory))
            rewritten = Path(directory) / "wrong.apk"
            bad = bytearray(elf64_aarch64())
            struct.pack_into("<H", bad, 18, 62)
            with zipfile.ZipFile(rewritten, "w") as archive:
                archive.writestr("AndroidManifest.xml", b"manifest")
                archive.writestr("classes.dex", b"dex")
                for library in REQUIRED_NATIVE_LIBRARIES:
                    archive.writestr(f"lib/arm64-v8a/{library}", bad if library == "libbox.so" else elf64_aarch64())
            with self.assertRaisesRegex(ApkValidationError, "AArch64"):
                validate_apk(rewritten)

    def test_fails_on_corrupt_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "bad.apk"
            apk.write_bytes(b"not an apk")
            with self.assertRaises(ApkValidationError):
                validate_apk(apk)


if __name__ == "__main__":
    unittest.main()
