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


    def test_standalone_project_generation_requires_owner_and_fresh_password_proof(self):
        console = (ROOT / "lib" / "king_ai_console.dart").read_text(encoding="utf-8")
        start = console.index("Future<void> _createStandaloneProject({bool ownerReauthenticated = false})")
        end = console.index("Future<void> _submitFeatureRequest", start)
        method = console[start:end]
        self.assertIn("_requireOwnerSession('ساخت اپلیکیشن')", method)
        self.assertIn("_reauthenticateOwnerForCodeChange()", method)
        self.assertLess(method.index("_requireOwnerSession("),
                        method.index("KingAiProjectBuilder.instance.buildProject("))
        self.assertLess(method.index("_reauthenticateOwnerForCodeChange()"),
                        method.index("KingAiProjectBuilder.instance.buildProject("))
        button_start = console.index("label: const Text('ساخت اپلیکیشن مستقل و ارسال ZIP')")
        button = console[button_start - 300:button_start]
        self.assertIn("_ownerUnlocked", button)

    def test_owner_session_duration_text_matches_two_minute_policy(self):
        console = (ROOT / "lib" / "king_ai_console.dart").read_text(encoding="utf-8")
        auth = (ROOT / "lib" / "king_ai_owner_auth.dart").read_text(encoding="utf-8")
        self.assertIn("sessionLifetime = Duration(minutes: 2)", auth)
        self.assertIn("دسترسی مالک فعال است (حداکثر ۲ دقیقه).", console)
        self.assertNotIn("دسترسی مالک فعال است (حداکثر ۱۵ دقیقه).", console)


    def test_initial_project_request_runs_after_model_and_owner_reauthentication(self):
        console = (ROOT / "lib" / "king_ai_console.dart").read_text(encoding="utf-8")
        self.assertIn("bool _initialProjectRequestSubmitted = false;", console)
        start = console.index("Future<void> _maybeCreateInitialProject()")
        end = console.index("Future<void> _createStandaloneProject", start)
        flow = console[start:end]
        self.assertIn("widget.initialProjectRequest?.trim().length", flow)
        self.assertIn("_ownerAuth.hasActiveSession", flow)
        self.assertIn("_ai.isLoaded", flow)
        self.assertIn("_reauthenticateOwnerForCodeChange()", flow)
        self.assertIn("_createStandaloneProject(ownerReauthenticated: true)", flow)
        self.assertIn("_maybeCreateInitialProject();", console)


if __name__ == "__main__":
    unittest.main()
