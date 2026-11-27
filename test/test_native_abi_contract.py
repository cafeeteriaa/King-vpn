import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class NativeAbiContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dart = (ROOT / "lib" / "king_native_accel.dart").read_text(encoding="utf-8")
        cls.rust = (ROOT / "native" / "king_native_core" / "src" / "lib.rs").read_text(encoding="utf-8")

    def test_dart_and_rust_declare_the_same_abi_version(self):
        dart_match = re.search(r"expectedNativeAbiVersion\s*=\s*(\d+)", self.dart)
        rust_match = re.search(
            r"fn\s+king_native_core_abi_version\s*\(\)\s*->\s*u32\s*\{\s*(\d+)\s*\}",
            self.rust,
        )
        self.assertIsNotNone(dart_match, "Dart must declare its expected native ABI")
        self.assertIsNotNone(rust_match, "Rust must export the native ABI version")
        self.assertEqual(dart_match.group(1), rust_match.group(1))

    def test_dart_checks_abi_before_resolving_the_data_plane_symbol(self):
        abi_lookup = self.dart.index("'king_native_core_abi_version'")
        data_lookup = self.dart.index("'king_expand_range_batch'")
        self.assertLess(abi_lookup, data_lookup)
        self.assertIn("if (abiVersion != expectedNativeAbiVersion)", self.dart)
        self.assertIn("_loadedNativeAbiVersion != expectedNativeAbiVersion", self.dart)

    def test_abi_failure_clears_native_handles_and_preserves_fallback(self):
        self.assertIn("_loadedNativeAbiVersion = null;", self.dart)
        self.assertIn("_library = null;", self.dart)
        self.assertIn("_expand = null;", self.dart)
        self.assertIn("Optional Android FFI bridge. Failures preserve the established Dart path.", self.dart)


if __name__ == "__main__":
    unittest.main()
