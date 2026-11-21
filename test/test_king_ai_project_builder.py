import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class KingAiProjectBuilderGuards(unittest.TestCase):
    def test_project_generation_is_local_and_separate_from_github_writer(self):
        ai = (ROOT / "lib" / "king_local_ai.dart").read_text(encoding="utf-8")
        builder = (ROOT / "lib" / "king_ai_project_builder.dart").read_text(encoding="utf-8")
        start = ai.index("Future<String> generateProjectText({")
        end = ai.index("bool _looksLikeCodeGenerationRequest", start)
        method = ai[start:end]
        self.assertIn("if (!isLoaded)", method)
        self.assertIn("_generateWithSystemPrompt(", method)
        self.assertNotIn("_github(", method)
        self.assertIn("KingLocalAi.instance.generateProjectText(", builder)
        self.assertIn("getApplicationSupportDirectory()", builder)
        self.assertIn("king_ai_projects", builder)
        self.assertIn("buildVerified': false", builder)

    def test_generated_project_paths_and_sizes_are_bounded(self):
        builder = (ROOT / "lib" / "king_ai_project_builder.dart").read_text(encoding="utf-8")
        self.assertIn("static const int _maxFiles = 10", builder)
        self.assertIn("static const int _maxFileBytes = 32000", builder)
        self.assertIn("static const int _maxProjectBytes = 200000", builder)
        self.assertIn("part == '..'", builder)
        self.assertIn("path.startsWith('/')", builder)
        self.assertIn("path.contains('\\\\')", builder)
        self.assertIn("path.split('/').any((part) => part.startsWith('.'))", builder)
        self.assertIn("_extensions.any(", builder)
        self.assertIn("'.kts'", builder)

    def test_failed_project_export_cleans_partial_workspace_and_zip(self):
        builder = (ROOT / "lib" / "king_ai_project_builder.dart").read_text(encoding="utf-8")
        start = builder.index("final zipFile = File(projects.path")
        end = builder.index("return {", start)
        export = builder[start:end]
        self.assertIn("try {", export)
        self.assertIn("workspace.delete(recursive: true)", export)
        self.assertIn("zipFile.delete()", export)
        self.assertIn("rethrow;", export)
        self.assertLess(export.index("workspace.delete(recursive: true)"),
                        export.index("rethrow;"))
        self.assertLess(export.index("zipFile.delete()"), export.index("rethrow;"))


    def test_zip_writer_emits_stored_entries_and_central_directory(self):
        builder = (ROOT / "lib" / "king_ai_project_builder.dart").read_text(encoding="utf-8")
        self.assertIn("0x04034b50", builder)
        self.assertIn("0x02014b50", builder)
        self.assertIn("0x06054b50", builder)
        self.assertIn("0x0800", builder)
        self.assertIn("_crc32(data)", builder)
        self.assertIn("Endian.little", builder)

    def test_console_exports_project_zip_through_android_share_sheet(self):
        console = (ROOT / "lib" / "king_ai_console.dart").read_text(encoding="utf-8")
        workflow = (ROOT / ".github" / "workflows" / "build.yml").read_text(encoding="utf-8")
        self.assertIn("KingAiProjectBuilder.instance.buildProject(", console)
        self.assertIn("Share.shareXFiles(", console)
        self.assertIn("XFile(zipPath)", console)
        self.assertIn("share_plus:^10.1.4", workflow)
        self.assertIn("File(zipPath).exists()", console)


    def test_natural_language_app_requests_open_zip_builder_not_repository_pr(self):
        main = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
        console = (ROOT / "lib" / "king_ai_console.dart").read_text(encoding="utf-8")
        self.assertIn("final projectRequest =", main)
        self.assertIn("اپلیکیشن بساز", main)
        self.assertIn("(اپلیکیشن|اپ|برنامه|پروژه).{0,50}(بساز|ایجاد کن|درست کن|طراحی کن|بنویس)", main)
        self.assertIn("create an app", main)
        self.assertIn("initialProjectRequest: projectRequest ? command : null", main)
        self.assertIn("initialFeatureRequest: projectRequest ? null : command", main)
        self.assertIn("this.initialProjectRequest", console)
        self.assertIn("widget.initialProjectRequest ??", console)
        self.assertIn("Future<void> _maybeSubmitInitialFeatureRequest()", console)

    def test_project_generation_phrases_are_classified_as_code_requests_in_chat(self):
        ai = (ROOT / "lib" / "king_local_ai.dart").read_text(encoding="utf-8")
        start = ai.index("bool _looksLikeCodeGenerationRequest")
        end = ai.index("final List<String> _conversationTurns", start)
        self.assertIn("'اپلیکیشن بساز'", ai[start:end])
        self.assertIn("'پروژه بساز'", ai[start:end])
        self.assertIn("'create an app'", ai[start:end])


if __name__ == "__main__":
    unittest.main()
