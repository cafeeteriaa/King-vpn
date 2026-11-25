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
        self.assertIn("inferenceBatchTargetChars = 9000", self.source)
        self.assertIn("batches.add(currentBatch)", self.source)
        self.assertIn("for (var batchIndex = 0; batchIndex < batches.length; batchIndex++)", self.source)

    def test_large_file_patch_operations_are_supported(self):
        patch = Path("lib/king_ai_patch_engine.dart").read_text(encoding="utf-8")
        self.assertIn("baseSha256", self.source)
        self.assertIn("KingAiPatchEngine.apply(", self.source)
        self.assertIn("final operations = item['operations'] as List;", self.source)
        self.assertIn("must match exactly once", patch)
        self.assertIn("sha256.convert(utf8.encode(original))", patch)
        protected = self.source.split("const protectedPaths = <String>{", 1)[1].split("};", 1)[0]
        self.assertIn("'lib/king_ai_patch_engine.dart'", protected)

    def test_oversized_files_are_chunked_without_loss_before_inference(self):
        chunker = Path("lib/king_ai_source_chunker.dart").read_text(encoding="utf-8")
        self.assertIn("KingAiSourceChunker.split(", self.source)
        self.assertIn("processedChunks", self.source)
        self.assertIn("chunkCount", self.source)
        self.assertIn("baseSha256", chunker)
        self.assertIn("for (final rune in source.runes)", chunker)
        self.assertIn("Large-file chunks must be edited with patch operations", self.source)
        self.assertIn("chunkedOperations", self.source)

    def test_maintenance_pipeline_has_no_two_file_change_ceiling(self):
        self.assertNotIn("changes.length <= 2", self.source)
        self.assertIn("final safeCandidate = changes.isNotEmpty", self.source)

    def test_documentation_paths_are_available_without_opening_native_or_ci_paths(self):
        self.assertIn("path.startsWith('docs/')", self.source)
        self.assertIn("path.endsWith('.md')", self.source)
        self.assertIn("path.startsWith('lib/android')", self.source)
        self.assertIn("path.startsWith('lib/own_vpn')", self.source)

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
