import struct
import unittest
import zipfile
from pathlib import Path
from tempfile import TemporaryDirectory

from tools.check_apk_elf_alignment import inspect_apk, inspect_elf


class ApkElfAlignmentTests(unittest.TestCase):
    @staticmethod
    def make_elf(align=0x4000, machine=183, p_offset=0, p_vaddr=0x4000):
        ident = b"\x7fELF" + bytes([2, 1, 1]) + bytes(9)
        header = struct.pack(
            "<HHIQQQIHHHHHH",
            3, machine, 1, 0, 64, 0, 0, 64, 56, 1, 0, 0, 0,
        )
        program = struct.pack(
            "<IIQQQQQQ", 1, 5, p_offset, p_vaddr, p_vaddr, 0x100, 0x100, align,
        )
        return ident + header + program

    def test_accepts_aarch64_load_segment_aligned_for_16k_pages(self):
        self.assertEqual(inspect_elf(self.make_elf()), [])

    def test_rejects_load_segment_aligned_only_for_4k_pages(self):
        errors = inspect_elf(self.make_elf(align=0x1000), "bad.so")
        self.assertTrue(any("below 16 KiB" in error for error in errors))

    def test_rejects_non_aarch64_native_library(self):
        errors = inspect_elf(self.make_elf(machine=62), "wrong-arch.so")
        self.assertTrue(any("expected AArch64" in error for error in errors))

    def test_rejects_incongruent_load_segment(self):
        errors = inspect_elf(self.make_elf(p_offset=0x1000, p_vaddr=0x4000), "bad-offset.so")
        self.assertTrue(any("not congruent" in error for error in errors))

    def test_apk_requires_and_checks_native_libraries(self):
        with TemporaryDirectory() as tmp:
            apk = Path(tmp) / "sample.apk"
            with zipfile.ZipFile(apk, "w") as archive:
                archive.writestr("lib/arm64-v8a/libsample.so", self.make_elf())
            count, errors = inspect_apk(apk)
            self.assertEqual(count, 1)
            self.assertEqual(errors, [])

    def test_apk_without_native_libraries_fails_closed(self):
        with TemporaryDirectory() as tmp:
            apk = Path(tmp) / "empty.apk"
            with zipfile.ZipFile(apk, "w") as archive:
                archive.writestr("assets/readme.txt", "no native code")
            count, errors = inspect_apk(apk)
            self.assertEqual(count, 0)
            self.assertTrue(any("no packaged native" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
