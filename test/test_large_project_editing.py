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
        self.assertIn("for (var batchIndex = completedBatches; batchIndex < batches.length; batchIndex++)", self.source)

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

    def test_owner_feature_proposals_are_not_limited_to_two_files(self):
        start = self.source.index("Future<Map<String, Object?>> createOwnerFeatureProposal(")
        end = self.source.index("Future<void> dispose()", start)
        owner_proposal = self.source[start:end]
        self.assertNotIn("changes.length <= 2", owner_proposal)
        audit_start = self.source.index("Future<Map<String, Object?>> createAutonomousMaintenanceProposal(")
        audit_end = self.source.index("Future<void> dispose()", audit_start)
        autonomous_audit = self.source[audit_start:audit_end]
        self.assertIn("changes.length <= 2", autonomous_audit)

    def test_documentation_paths_are_available_without_opening_native_or_ci_paths(self):
        self.assertIn("path.startsWith('docs/')", self.source)
        self.assertIn("path.endsWith('.md')", self.source)
        self.assertIn("path.startsWith('lib/android')", self.source)
        self.assertIn("path.startsWith('lib/own_vpn')", self.source)

    def test_repository_tree_walk_avoids_recursive_api_truncation(self):
        self.assertIn("final pendingTrees =", self.source)
        self.assertIn("while (pendingTrees.isNotEmpty)", self.source)
        self.assertIn("visitedTrees", self.source)
        self.assertIn("directoryTree['truncated'] == true", self.source)
        self.assertNotIn("git/trees/$treeSha?recursive=1", self.source)
        self.assertIn("child['mode'] == '120000'", self.source)

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

    def test_checkpoint_resume_is_atomic_and_bound_to_exact_inputs(self):
        checkpoint = Path("lib/king_ai_repair_checkpoint.dart").read_text(encoding="utf-8")
        self.assertIn("checkpointStore.save(", self.source)
        self.assertIn("checkpointStore.load(", self.source)
        self.assertIn("KingAiRepairCheckpointStore.deterministicId", self.source)
        self.assertIn("_validatePath(path)", self.source)
        self.assertIn("_rejectSecrets(content)", self.source)
        self.assertIn("Repair checkpoint batch position is invalid", self.source)
        self.assertIn("sourceSnapshotHash", checkpoint)
        self.assertIn("taskHash", checkpoint)
        self.assertIn("temporary.rename(target.path)", checkpoint)
        self.assertIn("Repair checkpoint is stale", checkpoint)
        self.assertIn("listRepairCheckpoints", self.source)

    def test_cross_file_dependency_graph_is_supplied_to_each_repair_batch(self):
        analyzer = Path("lib/king_ai_dependency_analyzer.dart").read_text(encoding="utf-8")
        self.assertIn("KingAiDependencyAnalyzer.analyze(safeFiles)", self.source)
        self.assertIn("CROSS-FILE DEPENDENCY GRAPH", self.source)
        self.assertIn("KingAiDependencyAnalyzer.forBatch(", self.source)
        self.assertIn("static Map<String, Object?> forBatch(", analyzer)
        self.assertIn("'edges': edges", analyzer)
        self.assertIn("'unresolved': unresolved", analyzer)
        self.assertIn("'cycles': _cycles(edges)", analyzer)

    def test_zip_import_has_path_link_duplicate_and_bomb_guards(self):
        importer = Path("lib/king_ai_zip_import.dart").read_text(encoding="utf-8")
        self.assertIn("KingAiZipImport.extract(", self.source)
        self.assertIn("importProjectZip(File archiveFile)", self.source)
        self.assertIn("normalizeEntryPath", importer)
        self.assertIn("Duplicate normalized ZIP path", importer)
        self.assertIn("ZIP symbolic link rejected", importer)
        self.assertIn("_maxExpansionRatio", importer)
        self.assertIn("size/CRC mismatch", importer)
        self.assertIn("Encrypted ZIP entry rejected", importer)
        self.assertIn("_zip64Eocd", importer)
        self.assertIn("_zip64ExtraValues", importer)
        self.assertIn("centralDirectoryEnd", importer)
        self.assertIn("await file.setPosition(centralCursor)", importer)
        self.assertIn("ZIP64 end record", importer)

    def test_ci_diagnostics_paginate_all_checks_annotations_and_workflow_jobs(self):
        start = self.source.index("Future<Map<String, Object?>> inspectPullRequestCi(")
        end = self.source.index("Future<int?> findOpenPullRequestForHeadBranch(", start)
        inspector = self.source[start:end]
        self.assertIn("Future<List<dynamic>> _githubAllPages(", self.source)
        self.assertIn("'per_page': '100'", self.source)
        self.assertIn("collectionKey: 'check_runs'", inspector)
        self.assertIn("collectionKey: 'workflow_runs'", inspector)
        self.assertIn("collectionKey: 'jobs'", inspector)
        self.assertIn("!['success', 'neutral', 'skipped'].contains(item['conclusion'])", inspector)
        self.assertIn("!['success', 'neutral', 'skipped'].contains(item['conclusion'])", inspector)
        self.assertNotIn(".take(", inspector)

    def test_owner_task_descriptions_have_no_fixed_character_ceiling(self):
        self.assertNotIn("request.length > 2000", self.source)
        self.assertIn("final request = task.trim();", self.source)
        self.assertNotIn("task.substring", self.source)


if __name__ == "__main__":
    unittest.main()
