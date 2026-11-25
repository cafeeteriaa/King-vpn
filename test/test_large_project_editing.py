#!/usr/bin/env python3
"""Regression guards for scalable, multi-file KING AI project editing."""
from pathlib import Path
import unittest


class LargeProjectEditingGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = Path("lib/king_local_ai.dart").read_text(encoding="utf-8")

    def test_no_fixed_file_count_or_context_byte_quotas(self):
        forbidden = (
            "sourceFiles.length > 6",
            "files.length >= 6",
            "Maximum three files per repair",
            "changes.length > 3",
            "Provide between 1 and 6 source files",
            "Source context exceeds 7.5 KB",
            "total + content.length > 7500",
            "content.length > 4000",
            "entry['size'] as num) <= 16000",
            "candidates.take(40)",
            "scored.take(6)",
        )
        for marker in forbidden:
            with self.subTest(marker=marker):
                self.assertNotIn(marker, self.source)

    def test_source_context_is_not_silently_truncated(self):
        self.assertIn("final safePrompt = prompt;", self.source)
        self.assertNotIn("prompt.substring(0, 18000)", self.source)

    def test_owner_authenticated_engine_can_be_updated_by_its_own_pipeline(self):
        protected = self.source.split("const protectedPaths = <String>{", 1)[1]
        protected = protected.split("};", 1)[0]
        self.assertNotIn("'lib/king_local_ai.dart'", protected)
        self.assertIn("_requireRepositoryOwnerIdentity();", self.source)
        self.assertIn("KingAiOwnerAuth.instance.hasActiveSession", self.source)

    def test_path_and_secret_guards_remain(self):
        self.assertIn("_validatePath(entry.key);", self.source)
        self.assertIn("_rejectSecrets(entry.value);", self.source)
        self.assertIn("path.contains('\\\\')", self.source)


if __name__ == "__main__":
    unittest.main()
