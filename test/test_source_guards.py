import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class KingVpnSourceGuardTests(unittest.TestCase):
    def test_manual_auto_test_abort_finishes_exactly_once(self):
        source = (ROOT / 'lib' / 'auto_test.dart').read_text(encoding='utf-8')
        self.assertIn("await _atFinish(reason: 'توقف دستی');", source)
        self.assertNotIn("return _atFinish(reason: 'توقف دستی');", source)

    def test_pilot_engine_extension_uses_throttled_state_update(self):
        source = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        start = source.index('void applyPilotEngine(String e)')
        end = source.index('String _engineLabel', start)
        method = source[start:end]
        self.assertIn('_set(', method)
        self.assertNotIn('setState(', method)

    def test_smart_pilot_code_requests_go_only_to_owner_console(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = main.index('Future<void> _runSmartCommand')
        end = main.index('Widget _smartCommandPanel()', start)
        dispatcher = main[start:end]
        self.assertIn('codeRequest', dispatcher)
        self.assertIn('KingAiConsolePage', dispatcher)
        self.assertNotIn('generateCode(', dispatcher)
        self.assertNotIn('repairFromFailedCi(', dispatcher)
        self.assertIn('فقط مالک اصلی', dispatcher)

    def test_command_help_mentions_king_address(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn('کینگ وصل شو', main)
        self.assertIn('کینگ نت ملی وصل شو', main)
        self.assertIn('کینگ نت جهانی وصل شو', main)

    def test_king_address_is_removed_before_smart_pilot_command_dispatch(self):
        safety = (ROOT / 'lib' / 'king_command_safety.dart').read_text(encoding='utf-8')
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn('stripKingAddress', safety)
        self.assertIn('(?:سلام|هی)', safety)
        self.assertIn('(?:کینگ|king)', safety)
        self.assertIn('KingCommandSafety.stripKingAddress(', main)

    def test_no_additional_engine_scaffolding_remains(self):
        self.assertFalse((ROOT / 'lib' / 'engine_registry.dart').exists())
        self.assertFalse((ROOT / 'lib' / 'singbox_core.dart').exists())
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertNotIn("import 'engine_registry.dart';", main)

    def test_automatic_scan_is_not_a_subnet_or_all_port_sweep(self):
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        start = nat.index('List<String> natSeedBlocks(')
        end = nat.index('\nint natMemQueued', start)
        seed_block = nat[start:end]
        self.assertIn("'${parsed.address}/32'", seed_block)
        domain_start = nat.index('Future<List<String>> _natDomainFirst(')
        domain_end = nat.index('\nFuture<List<String>> natDeviceHosts()', domain_start)
        domain_scan = nat[domain_start:domain_end]
        self.assertNotIn('natIrDomains', domain_scan)
        self.assertNotIn('for (var p = 1; p < 65536; p++)', domain_scan)

    def test_connect_path_uses_mode_aware_tunnel_probe(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn('networkAware: true', main)
        self.assertIn('final urls = nationalMode ? _tunnelTestUrlsNational', main)

    def test_code_changes_are_pinned_to_the_official_repository(self):
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        self.assertIn("static const String _repositoryOwner = 'cafeeteriaa';", ai)
        self.assertIn("static const String _repositoryName = 'King-vpn';", ai)
        self.assertIn('void _requireKingRepository(String owner, String repository)', ai)
        protected_start = ai.index('bool _isProtectedGeneratedPath(String path)')
        protected_end = ai.index('void _validatePath(String path)', protected_start)
        protected = ai[protected_start:protected_end]
        for path in (
            'lib/king_ai_console.dart',
            'test/test_source_guards.py',
            'test/king_ai_ci_policy_test.dart',
            'test/king_ai_research_policy_test.dart',
        ):
            self.assertIn(path, protected)
        self.assertIn('login.toLowerCase() != _repositoryOwner', ai)
        for method in (
            'createOwnerFeatureProposal({',
            'repairFromFailedCi({',
            'repairFromFailedCiAutonomous({',
        ):
            start = ai.index(method)
            body_start = ai.index('}) async {', start) + len('}) async {')
            if method == 'repairFromFailedCiAutonomous({':
                body_start = ai.index('}) {', start) + len('}) {')
            end = ai.index('\n  }', body_start)
            self.assertIn('_requireKingRepository(owner, repository);', ai[body_start:end])
        self.assertNotIn('old signature removed', ai)

    def test_first_owner_enrollment_requires_live_repository_owner_proof(self):
        auth = (ROOT / 'lib' / 'king_ai_owner_auth.dart').read_text(encoding='utf-8')
        start = auth.index('Future<void> setInitialPassword(String password)')
        end = auth.index('Future<void> changePassword(String password)', start)
        setup = auth[start:end]
        self.assertIn('await _requireRepositoryOwnerIdentity();', setup)
        self.assertLess(setup.index('await _requireRepositoryOwnerIdentity();'),
                        setup.index('_derive(password, salt)'))
        verifier = auth[auth.index('Future<void> _requireRepositoryOwnerIdentity()'):
                        auth.index('Future<List<int>> _derive(')]
        self.assertIn("Uri.https('api.github.com', '/user')", verifier)
        self.assertIn("login.toLowerCase() != _repositoryOwner", verifier)
        self.assertIn("key: 'king_ai_github_token'", verifier)

    def test_owner_password_rotation_restores_previous_pair_on_storage_failure(self):
        auth = (ROOT / 'lib' / 'king_ai_owner_auth.dart').read_text(encoding='utf-8')
        start = auth.index('Future<void> changePassword(String password)')
        end = auth.index('Future<bool> authenticate(String password)', start)
        rotation = auth[start:end]
        self.assertIn('final oldSalt = await _storage.read(key: _saltKey);', rotation)
        self.assertIn('final oldVerifier = await _storage.read(key: _verifierKey);', rotation)
        self.assertIn('await _storage.write(key: _saltKey, value: oldSalt);', rotation)
        self.assertIn('await _storage.write(key: _verifierKey, value: oldVerifier);', rotation)
        self.assertIn('Owner credential storage is incomplete', rotation)

    def test_local_model_prompt_uses_real_chat_template_newlines(self):
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        start = ai.index('final generation = engine.generate(', ai.index('Future<String> _generateWithSystemPrompt'))
        end = ai.index('GenerationOptions(', start)
        template = ai[start:end]
        self.assertIn("'<|im_start|>system\\n$systemPrompt", template)
        self.assertIn("'<|im_start|>user\\n$safePrompt", template)
        self.assertNotIn('\\\\n', template)

    def test_github_token_is_verified_as_repository_owner_before_use(self):
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        start = ai.index('Future<void> saveGitHubToken(String token)')
        end = ai.index('Future<bool> hasGitHubToken()', start)
        save = ai[start:end]
        self.assertIn('_requireRepositoryOwnerIdentity()', save)
        self.assertIn('final previous = await _secure.read', save)
        self.assertIn('await _secure.write(key: \'king_ai_github_token\', value: previous)', save)
        self.assertIn('rethrow;', save)

    def test_code_writes_require_matching_github_repository_owner_identity(self):
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        helper_start = ai.index('Future<void> _requireRepositoryOwnerIdentity(')
        helper_end = ai.index('Future<Map<String, dynamic>> _github(', helper_start)
        helper = ai[helper_start:helper_end]
        self.assertIn("Uri.https('api.github.com', '/user')", helper)
        self.assertIn('login.toLowerCase() != _repositoryOwner', helper)
        create_start = ai.index('Future<String> _createRepairPullRequest({')
        create_end = ai.index('Future<Map<String, Object?>> createOwnerFeatureProposal({', create_start)
        self.assertIn('_requireKingRepository(owner, repository);', ai[create_start:create_end])
        self.assertIn('await _requireRepositoryOwnerIdentity();', ai[create_start:create_end])

    def test_ordinary_king_chat_cannot_enter_the_coding_prompt(self):
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        ask_start = ai.index('Future<String> ask(String prompt')
        coding_start = ai.index('Future<String> _askCoding(', ask_start)
        public_ask = ai[ask_start:coding_start]
        self.assertIn('_looksLikeCodeGenerationRequest(prompt)', public_ask)
        self.assertIn('!KingCommandSafety.isQuestionRequest(prompt)', public_ask)
        self.assertIn('_conversationSystemPrompt', public_ask)
        self.assertNotIn('_systemPrompt', public_ask)
        self.assertIn('کدنویسی کن', ai[ai.index('bool _looksLikeCodeGenerationRequest'):ask_start])
        self.assertIn('add feature', ai[ai.index('bool _looksLikeCodeGenerationRequest'):ask_start])
        self.assertIn('پیاده سازی کن', ai[ai.index('bool _looksLikeCodeGenerationRequest'):ask_start])
        self.assertIn('write a function', ai[ai.index('bool _looksLikeCodeGenerationRequest'):ask_start])
        proposal_start = ai.index('Future<Map<String, Object?>> _proposeRepair({')
        proposal_end = ai.index('Future<Map<String, Object?>> repairFromFailedCi({', proposal_start)
        self.assertIn('await _askCoding(', ai[proposal_start:proposal_end])
        extras = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        self.assertIn('return KingLocalAi.instance.ask(prompt);', extras)
        for phrase in ('کد رو اصلاح', 'سورس رو تغییر', 'برنامه را تغییر', 'قابلیت بساز'):
            self.assertIn(phrase, ai)
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        code_start = main.index('final codeRequest = !KingCommandSafety.isQuestionRequest(command) && RegExp(')
        code_end = main.index(').hasMatch(command);', code_start)
        self.assertIn('کدشو بنویس', main[code_start:code_end])
        self.assertIn('قابلیت اضافه', main[code_start:code_end])
        self.assertIn('!KingCommandSafety.isQuestionRequest(command)', main[code_start:code_end])

    def test_generated_patches_cannot_modify_security_and_command_policy_files(self):
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        start = ai.index('bool _isProtectedGeneratedPath(String path)')
        end = ai.index('void _rejectSecrets(String text)', start)
        guard = ai[start:end]
        for path in (
            'lib/king_ai_owner_auth.dart',
            'lib/king_local_ai.dart',
            'lib/king_ai_background.dart',
            'lib/king_ai_ci_policy.dart',
            'lib/king_ai_research_policy.dart',
            'lib/iran_ai_extras.dart',
            'lib/main.dart',
            'lib/king_command_safety.dart',
            'test/king_command_safety_test.dart',
            'lib/auto_scanners.dart',
            'lib/nat_ultra.dart',
            'lib/national_engine.dart',
            'lib/network_health.dart',
            'lib/nnie_core.dart',
        ):
            self.assertIn(path, guard)
        self.assertIn('return protectedPaths.contains(path)', guard)
        self.assertIn('_isProtectedGeneratedPath(path)', guard)
        context_start = ai.index('Future<Map<String, String>> readRepositoryContext(')
        context_end = ai.index('Future<String> createRepairPullRequest(', context_start)
        self.assertIn('!_isProtectedGeneratedPath(path)', ai[context_start:context_end])

    def test_all_public_code_generation_and_pr_write_apis_require_owner(self):
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        propose_start = ai.index('Future<Map<String, Object?>> proposeRepair({')
        propose_end = ai.index('Future<Map<String, Object?>> _proposeRepair({', propose_start)
        public_propose = ai[propose_start:propose_end]
        self.assertIn('hasActiveSession', public_propose)
        self.assertIn('Owner authentication is required', public_propose)
        create_start = ai.index('Future<String> createRepairPullRequest({')
        create_end = ai.index('Future<String> _createRepairPullRequest({', create_start)
        public_create = ai[create_start:create_end]
        self.assertIn('hasActiveSession', public_create)
        self.assertIn('Owner authentication is required', public_create)
        self.assertIn('final proposal = await _proposeRepair(', ai)
        self.assertIn('final url = await _createRepairPullRequest(', ai)
        feature_start = ai.index('Future<Map<String, Object?>> createOwnerFeatureProposal({')
        feature_end = ai.index('Future<void> dispose()', feature_start)
        feature = ai[feature_start:feature_end]
        self.assertIn('hasActiveSession', feature)
        self.assertIn("'status': 'owner_auth_required'", feature)
        self.assertIn("baseBranch: 'main'", feature)
        console = (ROOT / 'lib' / 'king_ai_console.dart').read_text(encoding='utf-8')
        self.assertIn('createOwnerFeatureProposal(', console)
        self.assertIn('maxLength: 128', console)
        self.assertIn('_rejectSecrets(summary)', ai)

    def test_owner_password_rotation_is_available_only_in_active_session_ui(self):
        console = (ROOT / 'lib' / 'king_ai_console.dart').read_text(encoding='utf-8')
        auth = (ROOT / 'lib' / 'king_ai_owner_auth.dart').read_text(encoding='utf-8')
        self.assertIn('if (_ownerUnlocked) ...[', console)
        self.assertIn('_ownerAuth.changePassword(password)', console)
        self.assertIn('تغییر رمز مالک', console)
        change_start = auth.index('Future<void> changePassword(String password)')
        change_end = auth.index('Future<bool> authenticate(', change_start)
        self.assertIn('hasActiveSession', auth[change_start:change_end])

    def test_manual_code_repair_requires_device_owner_but_autonomous_repair_is_separate(self):
        auth = (ROOT / 'lib' / 'king_ai_owner_auth.dart').read_text(encoding='utf-8')
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        worker = (ROOT / 'lib' / 'king_ai_background.dart').read_text(encoding='utf-8')
        console = (ROOT / 'lib' / 'king_ai_console.dart').read_text(encoding='utf-8')
        self.assertIn('Argon2id(', auth)
        self.assertIn('memory: 32 * 1024', auth)
        self.assertIn('iterations: 3', auth)
        self.assertIn('FlutterSecureStorage', auth)
        self.assertIn('_maxFailuresBeforeLock', auth)
        self.assertIn('sessionLifetime', auth)
        self.assertIn('Stopwatch()', auth)
        self.assertIn('_maximumPasswordLength = 128', auth)
        manual = ai[ai.index('Future<Map<String, Object?>> repairFromFailedCi({'):
                    ai.index('Future<Map<String, Object?>> repairFromFailedCiAutonomous({')]
        self.assertIn('hasActiveSession', manual)
        self.assertIn("'status': 'owner_auth_required'", manual)
        self.assertIn('repairFromFailedCiAutonomous(', worker)
        missing_model = worker[worker.index('if (!loaded) {'):worker.index('final result = await ai.repairFromFailedCiAutonomous', worker.index('if (!loaded) {'))]
        self.assertIn('cancelByTag(_tag)', missing_model)
        self.assertIn('clearBackgroundRepairPullNumber()', missing_model)
        self.assertIn('setBackgroundAutoDiscovery(false)', missing_model)
        self.assertIn('_ownerAuth.setInitialPassword(password)', console)
        self.assertIn('_ownerAuth.authenticate(password)', console)
        self.assertIn('if (!_ownerAuth.hasActiveSession)', console)

    def test_autonomous_ci_repair_is_bounded_and_deduplicated(self):
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        policy = (ROOT / 'lib' / 'king_ai_ci_policy.dart').read_text(encoding='utf-8')
        start = ai.index('Future<Map<String, Object?>> _repairFromFailedCi({')
        end = ai.index('static const Set<String> _researchHosts', start)
        repair = ai[start:end]
        self.assertIn('kingAiCiRepairAttemptAllowed(used)', repair)
        self.assertIn('kingAiCiRepairBackoff(used)', repair)
        self.assertIn('lastAttemptAt', repair)
        self.assertIn('duplicate_patch_blocked', repair)
        self.assertIn('lastProposalHash', repair)
        self.assertIn('setBackgroundRepairPullNumber(createdPullNumber)', repair)
        self.assertIn('maxAttempts = 8', policy)
        self.assertIn('maximum = const Duration(hours: 6)', policy)

    def test_background_supervisor_controls_require_owner_session(self):
        worker = (ROOT / 'lib' / 'king_ai_background.dart').read_text(encoding='utf-8')
        console = (ROOT / 'lib' / 'king_ai_console.dart').read_text(encoding='utf-8')
        self.assertIn("import 'king_ai_owner_auth.dart';", worker)
        self.assertIn('static void _requireOwnerSession()', worker)
        for signature in (
            'static Future<void> enable(int pullNumber) async {',
            'static Future<void> enableAutonomousMaintenance() async {',
            'static Future<void> disable() async {',
        ):
            start = worker.index(signature)
            body = worker[start:worker.index('\n  }', start)]
            self.assertIn('_requireOwnerSession();', body)
        self.assertIn('static Future<void> enableAutomaticDiscovery() =>', worker)
        self.assertIn('enableAutonomousMaintenance();', worker)
        self.assertIn('Future<bool> _requireOwnerSession(String action)', console)
        self.assertNotIn('async { {', console)
        self.assertIn('_busy || !_hasToken ? null : _setupOwnerPassword', console)
        self.assertIn('ابتدا کلید GitHub حساب مالک مخزن', console)
        self.assertIn("_ownerConfigured && !await _reauthenticateOwnerForCodeChange()", console)
        self.assertIn('final valid = await _ownerAuth.authenticate(password);', console)
        for method in ('_submitFeatureRequest', '_repair', '_enableBackground',
                       '_enableAutomaticDiscovery', '_saveToken', '_clearToken'):
            start = console.index('Future<void> ' + method)
            end = console.find('\\n  Future<void> ', start + 1)
            if end < 0:
                end = console.find('\\n  @override', start + 1)
            self.assertIn('_reauthenticateOwnerForCodeChange()', console[start:end], method)

    def test_national_network_optimization_requests_enter_owner_code_flow(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn("r'(نت ملی|اینترنت ایران).{0,40}(بهینه|ارتقا|بروز|به روز|خودکار|هوشمند|توسعه|تقویت).{0,12}(کن|کنید|بده|بساز)|'", main)
        self.assertIn("KingAiConsolePage(initialFeatureRequest: command", main)

    def test_daily_autonomous_source_audit_is_owner_enabled_and_review_only(self):
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        worker = (ROOT / 'lib' / 'king_ai_background.dart').read_text(encoding='utf-8')
        start = ai.index('Future<Map<String, Object?>> createAutonomousMaintenanceProposal(')
        end = ai.index('static const Set<String> _researchHosts', start)
        audit = ai[start:end]
        self.assertIn('isBackgroundAutoDiscoveryEnabled()', audit)
        self.assertIn("Duration(hours: 24)", audit)
        self.assertIn('changes.length <= 2', audit)
        self.assertIn('context.containsKey(entry.key)', audit)
        self.assertIn('_createRepairPullRequest(', audit)
        self.assertNotIn('await createRepairPullRequest(', audit)
        self.assertIn('_auditTaskName', worker)
        self.assertIn('frequency: const Duration(hours: 24)', worker)
        self.assertIn('await Workmanager().cancelByTag(_auditTag)', worker)

    def test_official_iran_network_research_is_scheduled_automatically(self):
        worker = (ROOT / 'lib' / 'king_ai_background.dart').read_text(encoding='utf-8')
        policy = (ROOT / 'lib' / 'king_ai_autonomy_policy.dart').read_text(encoding='utf-8')
        self.assertIn('await _scheduleOfficialResearch();', worker)
        self.assertIn("const String _researchTaskName = 'kingAiIranNetworkResearch';", worker)
        self.assertIn('maxResults: kingAiBackgroundResearchMaxResults', worker)
        self.assertIn('const int kingAiBackgroundResearchMaxResults = 2', policy)
        self.assertIn('frequency: kingAiOfficialResearchInterval', worker)
        self.assertIn('Duration(hours: 6)', policy)
        self.assertIn('networkType: NetworkType.connected', worker)
        self.assertIn('requiresBatteryNotLow: true', worker)
        self.assertIn('static Future<void> enableAutonomousMaintenance() async {', worker)
        self.assertIn('never merges or publishes', worker)

    def test_autonomous_repair_uses_persisted_backoff_and_duplicate_patch_guard(self):
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        policy = (ROOT / 'lib' / 'king_ai_ci_policy.dart').read_text(encoding='utf-8')
        start = ai.index('Future<Map<String, Object?>> _repairFromFailedCi({')
        end = ai.index('Future<Map<String, Object?>> repairUntilGreen(', start)
        repair = ai[start:end]
        self.assertIn('kingAiCiRepairBackoff(used)', repair)
        self.assertIn("'lastAttemptAt'", repair)
        self.assertIn("'lastProposalHash'", repair)
        self.assertIn("'duplicate_patch_blocked'", repair)
        self.assertIn('maxAttempts = 8', policy)
        self.assertIn('maximum = const Duration(hours: 6)', policy)

    def test_smart_command_respects_negated_connect_and_scan_intents(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn('KingCommandSafety.negatesConnection(command)', main)
        self.assertIn('KingCommandSafety.isConnectIntent(command)', main)
        self.assertNotIn('!negatesConnection;', main)
        self.assertIn('KingCommandSafety.negatesScan(command)', main)
        self.assertIn("!negatesScan && command.contains('dns') && command.contains('اسکن')", main)
        self.assertIn("!negatesScan &&", main[main.index("Future<void> _runSmartCommand"):main.index("Widget _smartCommandPanel()")])
        self.assertIn("command.contains('اسکن sni')", main)
        self.assertIn("command.contains('اسکن پورت')", main)

    def test_command_safety_helper_is_used_and_has_dart_unit_coverage(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        helper = (ROOT / 'lib' / 'king_command_safety.dart').read_text(encoding='utf-8')
        tests = (ROOT / 'test' / 'king_command_safety_test.dart').read_text(encoding='utf-8')
        self.assertIn("import 'king_command_safety.dart';", main)
        self.assertIn('KingCommandSafety.negatesConnection(command)', main)
        self.assertIn('KingCommandSafety.negatesScan(command)', main)
        self.assertIn('static bool negatesConnection(String command)', helper)
        self.assertIn('static bool isConnectIntent(String command)', helper)
        self.assertIn('static bool negatesScan(String command)', helper)
        self.assertIn("test('connect intent recognises متصل", tests)
        self.assertIn("test('negative connect commands are blocked'", tests)
        self.assertIn("test('negative scan commands are blocked'", tests)

    def test_gradle_plugin_buildscripts_receive_maven_central_mirror(self):
        patcher = (ROOT / 'patch_plugin.py').read_text(encoding='utf-8')
        self.assertIn('patch_android_plugin_buildscript_repositories()', patcher)
        self.assertIn('MAVEN_CENTRAL_MIRROR', patcher)
        self.assertIn(r'buildscript\s*\{\s*repositories\s*\{', patcher)
        self.assertIn('repo_body = source[repo_open + 1:repo_close]', patcher)
        self.assertIn('Maven Central mirror added to plugin buildscript', patcher)
        self.assertNotIn('if MAVEN_CENTRAL_MIRROR in source:', patcher)
        self.assertIn('maven-central.storage-download.googleapis.com/maven2/', patcher)

    def test_flutter_kotlin_dsl_resolution_has_central_and_plugin_fallback_mirrors(self):
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        self.assertIn('maven.aliyun.com/repository/central/', prepare)
        self.assertIn('maven.aliyun.com/repository/gradle-plugin/', prepare)
        self.assertIn('ALIYUN_CENTRAL_MIRROR', prepare)
        self.assertIn('ALIYUN_GRADLE_PLUGIN_MIRROR', prepare)
        self.assertIn('pluginManagement', prepare)
        self.assertIn('dependencyResolutionManagement', prepare)
        self.assertIn('repositories_text', prepare)

    def test_android_vpn_background_channel_is_registered_and_packaged(self):
        native = (ROOT / 'android_src' / 'MainActivity.kt').read_text(encoding='utf-8')
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        self.assertIn('MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vpn/bg")', native)
        for method in ('"alive"', '"back"', '"vpnSettings"'):
            self.assertIn(method, native)
        self.assertIn("shutil.copy('android_src/MainActivity.kt', os.path.join(ka, 'MainActivity.kt'))", prepare)
        self.assertIn("old_java_main = os.path.join(ja, 'MainActivity.java')", prepare)
        self.assertIn("os.remove(old_java_main)", prepare)

    def test_background_supervisor_is_initialized_with_its_own_dispatcher(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn("import 'king_ai_background.dart';", main)
        self.assertIn('KingAiBackgroundSupervisor.initialize()', main)
        self.assertNotIn('cancelAll()', main)

    def test_background_supervisor_apis_exist_and_verify_installed_model(self):
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        worker = (ROOT / 'lib' / 'king_ai_background.dart').read_text(encoding='utf-8')
        for method in (
            'setBackgroundRepairPullNumber',
            'getBackgroundRepairPullNumber',
            'clearBackgroundRepairPullNumber',
            'setBackgroundAutoDiscovery',
            'isBackgroundAutoDiscoveryEnabled',
            'loadInstalledModelForBackground',
            'findOpenPullRequestWithCiFailures',
            'findOpenPullRequestForHeadBranch',
        ):
            self.assertIn(f'{method}(', ai)
            self.assertIn(f'.{method}(', worker)
        load_start = ai.index('Future<bool> loadInstalledModelForBackground()')
        load_end = ai.index('Future<ModelManager> _modelManager()', load_start)
        loader = ai[load_start:load_end]
        self.assertIn('decoded[\'sha256\'] != modelSha256', loader)
        self.assertIn('decoded[\'sizeBytes\'] != modelSizeBytes', loader)
        self.assertIn('sha256.bind(modelFile.openRead())', loader)
        self.assertIn('resolveSymbolicLinks()', loader)
        self.assertIn('repairFromFailedCiAutonomous(', worker)

    def test_king_voice_commands_support_persian_speech_service_fallback(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        workflow = (ROOT / '.github' / 'workflows' / 'build.yml').read_text(encoding='utf-8')
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        self.assertIn("import 'package:speech_to_text/speech_to_text.dart' as stt;", main)
        start = main.index('Future<void> _toggleSmartCommandSpeech()')
        end = main.index('Future<void> _loadSmartCommandFilters()', start)
        voice = main[start:end]
        self.assertIn('Permission.microphone.request()', voice)
        self.assertIn("startsWith('fa')", voice)
        self.assertIn('onDevice: true', voice)
        self.assertIn('onDevice: false', voice)
        self.assertIn('_startSmartCommandOnlineFallback()', voice)
        self.assertIn('_requestSmartCommandOnlineFallback()', voice)
        self.assertIn('اجازه تشخیص گفتار آنلاین؟', voice)
        self.assertIn('if (result.finalResult) _smartSpeechOnDeviceAttempt = false;', voice)
        self.assertIn('تشخیص گفتار آفلاین', voice)
        chat = (ROOT / 'lib' / 'king_chat_page.dart').read_text(encoding='utf-8')
        self.assertIn('Future<void> _send()', chat)
        self.assertIn('KingLocalAi.instance.ask(prompt', chat)
        self.assertIn('KingVoiceOutput.instance.speakPersian(answer)', chat)
        self.assertIn('result.finalResult', chat)
        self.assertIn('onDevice: true', chat)
        self.assertIn('onDevice: false', chat)
        self.assertIn('_startChatSpeechOnlineFallback()', chat)
        self.assertIn('_requestChatSpeechOnlineFallback()', chat)
        self.assertIn('_voiceTurn = false;', chat)
        self.assertIn('اجازه تشخیص گفتار آنلاین؟', chat)
        self.assertIn('if (result.finalResult) _onDeviceSpeechAttempt = false;', chat)
        self.assertIn('تشخیص گفتار آفلاین', chat)
        self.assertIn('_smartSpeechInitialized = _smartSpeechAvailable;', voice)
        self.assertIn('if (s != AppLifecycleState.resumed && _smartSpeech.isListening)', main)
        self.assertIn('_smartCommandController.value = TextEditingValue(', voice)
        self.assertNotIn('_runSmartCommand(', voice)
        self.assertIn('speech_to_text:^7.4.0', workflow)
        self.assertIn('android.permission.RECORD_AUDIO', prepare)
        self.assertIn("if 'android.permission.RECORD_AUDIO' not in m:", prepare)
        self.assertIn('android.speech.RecognitionService', prepare)
        self.assertIn("if 'android.speech.RecognitionService' not in m:", prepare)
        self.assertIn("if '<queries>' in m:", prepare)
        self.assertIn("m.replace('<queries>', '<queries>' + speech_intent, 1)", prepare)

    def test_owner_console_is_reachable_from_command_panel_and_code_requests_are_gated(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        extras = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        self.assertIn("import 'king_ai_console.dart';", main)
        self.assertIn("import 'king_ai_owner_auth.dart';", main)
        self.assertIn('const KingAiConsolePage()', main)
        self.assertIn('final codeRequest = !KingCommandSafety.isQuestionRequest(command) && RegExp(', main)
        self.assertIn('if (codeRequest)', main)
        self.assertIn('KingAiOwnerAuth.instance.lock()', main)
        self.assertIn('KingAiOwnerAuth.instance.hasActiveSession', extras)
        self.assertIn('بازکردن پنل امن مالک و کینگ', extras)

    def test_ci_pipelines_propagate_failures_through_tee(self):
        workflow = (ROOT / '.github' / 'workflows' / 'build.yml').read_text(encoding='utf-8')
        self.assertGreaterEqual(workflow.count('set -o pipefail'), 3)


    def test_home_screen_exposes_one_unified_pilot_action(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        pilot_ui = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        self.assertIn('_smartCommandPanel()', main)
        self.assertIn('اتصال خلبان', main)
        self.assertIn('await startLocalPilot();', main)
        # Command-only home: the legacy hero connect control is intentionally absent.
        self.assertIn('UiHero(', main)
        self.assertIn('onTap: null,', main)
        self.assertNotIn("label: const Text('جستجوی سرور با نت ملی')", main)
        self.assertNotIn('Widget aiBar()', pilot_ui)
        self.assertNotIn('PilotCommandBar', pilot_ui)
        self.assertNotIn('_runPilotCommand(', pilot_ui)

    def test_local_pilot_rechecks_network_after_link_changes(self):
        pilot = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        tick_start = pilot.index('Future<void> localPilotTick(')
        tick_end = pilot.index('void _localReschedule()', tick_start)
        tick = pilot[tick_start:tick_end]
        self.assertIn('if (!connected)', tick)
        self.assertIn('await _pilotDetectNetworkMode();', tick)
        detect_start = pilot.index('Future<NatNetworkClass> _pilotDetectNetworkMode()')
        detect_end = pilot.index('void ensureLocalPilotRunning()', detect_start)
        detect = pilot[detect_start:detect_end]
        self.assertIn('PilotNetworkProbe.refresh()', detect)
        self.assertNotIn('PilotNetworkProbe.refresh(force: true)', detect)
        self.assertNotIn('NatNetworkDiagnosis.refresh', detect)
        self.assertNotIn('autoTuneNow()', tick)


    def test_pilot_scanner_and_ip_ranges_are_isolated_from_general_scanners(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        pilot = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        national = (ROOT / 'lib' / 'national_engine.dart').read_text(encoding='utf-8')
        self.assertIn('class PilotNetworkProbe', national)
        self.assertIn('domesticTargets', national)
        self.assertIn('globalTargets', national)
        self.assertIn('SecureSocket.connect(host, 443', national)
        self.assertIn("command.contains('بازه') && command.contains('خلبان')", main)
        self.assertIn("command.contains('اسکن') && command.contains('خلبان')", main)
        self.assertNotIn("label: const Text('بازه‌های IP اختصاصی خلبان')", main)
        self.assertNotIn("label: const Text('پویش IP اختصاصی خلبان')", main)
        self.assertIn('_smartCommandPanel()', main)
        self.assertIn('مرکز فرمان هوشمند', main)
        self.assertIn('_runSmartCommand', main)
        self.assertIn("king_pilot_ip_ranges_v1", main)
        self.assertIn("_pilotRangesValid(c.text)", main)
        self.assertIn("bool _pilotRangesValid(String raw)", main)
        self.assertIn("king_pilot_scan_results_v1", main)
        self.assertIn('bool _pilotRangeCancelRequested = false;', main)
        command_start = main.index('Future<void> _runSmartCommand')
        command_end = main.index('Widget _smartCommandPanel()', command_start)
        command_parser = main[command_start:command_end]
        self.assertIn('_pilotRangeCancelRequested = true;', command_parser)
        self.assertLess(command_parser.index('_pilotRangeCancelRequested = true;'),
                        command_parser.index('if (command.isEmpty || _smartCommandRunning) {'))
        pilot_scan_start = main.index('Future<void> _pilotScanOnly()')
        pilot_scan_end = main.index('// اسکن IP بدون تغییر تنظیمات دیگر', pilot_scan_start)
        pilot_scan = main[pilot_scan_start:pilot_scan_end]
        self.assertNotIn('natRangeScanStep', pilot_scan)
        self.assertNotIn('natRanges', pilot_scan)
        self.assertNotIn('abort', pilot_scan)
        self.assertIn('_pilotRangeCancelRequested', pilot_scan)
        self.assertIn('Socket.connect(host, 443', pilot_scan)
        self.assertIn('_pilotRangesDialog(context)', main)
        self.assertIn('_pilotScanOnly()', main)
        self.assertIn('_smartCountryCode(command)', main)
        self.assertIn("'germany': 'DE'", main)
        self.assertNotIn('label: Text(selCountry == null', main)
        self.assertNotIn("for (final pr in ['all', 'vmess'", main)
        self.assertNotIn('pickEngineThenStart(() => connect(s, gid)', main)
        self.assertEqual(main.count('extension ProjectNatSweep on _HomePageState'), 1)
        self.assertNotIn('_natRangesDialog(context)', main[main.index('Future<void> _pilotScanOnly()'):main.index('// اسکن IP بدون تغییر تنظیمات دیگر')])
        self.assertNotIn('UiTools(items: [', main[main.index('Widget build(BuildContext context)', main.index('class _HomePageState')):])
        keep_start = main.index('Future<void> _natKeep()')
        keep_end = main.index('void _natRangesDialog', keep_start)
        keep = main[keep_start:keep_end]
        self.assertIn('localPilotOn', keep)
        self.assertIn('if (localPilotOn && cpuHot == 0', keep)
        detect_start = pilot.index('Future<NatNetworkClass> _pilotDetectNetworkMode()')
        detect_end = pilot.index('void ensureLocalPilotRunning()', detect_start)
        self.assertNotIn('NatNetworkDiagnosis', pilot[detect_start:detect_end])
        self.assertIn('PilotNetworkProbe.refresh()', pilot[detect_start:detect_end])
        self.assertNotIn('PilotNetworkProbe.refresh(force: true)', pilot[detect_start:detect_end])
        self.assertIn('checks.where((ok) => ok).length >= 2', pilot)
        self.assertIn('_pilotPendingPositiveSamples >= 2', pilot)
        self.assertIn("'switch_best' => snap.connected", pilot)
        self.assertIn("'connect' => !_pilotPendingWasConnected && snap.connected", pilot)
        self.assertIn('Duration(seconds: 10)', pilot)
        self.assertIn('_pilotExperienceOperatorKey(s.operatorKey)', pilot)
        self.assertIn("'domestic' : 'global'", pilot)
        self.assertIn('total >= 5', pilot)
        self.assertIn('winRate >= 0.75', pilot)
        self.assertIn('king_pilot_experience_v1', pilot)
        self.assertIn('_pilotReconcileExperience(snap)', pilot)
        self.assertIn('_pilotSaveExperience()', pilot)
        self.assertNotIn("_localOpWins[k] = (_localOpWins[k] ?? 0) + 1;", pilot)
        nat_detect_start = main.index('Future<void> _natDetect()')
        nat_detect_end = main.index('DateTime? _checkSavedAt', nat_detect_start)
        nat_detect = main[nat_detect_start:nat_detect_end]
        self.assertIn('PilotNetworkProbe.refresh()', nat_detect)
        self.assertNotIn('dnsxAutoPick(', nat_detect)
        self.assertNotIn('ipAutoBackground(', nat_detect)
        connect_start = main.index('Future<void> _doConnect(')
        connect_end = main.index('void _cancelNow()', connect_start)
        connect = main[connect_start:connect_end]
        self.assertIn('if (localPilotOn)', connect)
        self.assertIn('PilotNetworkProbe.refresh()', connect)
        self.assertLess(connect.index('if (localPilotOn)'), connect.index('NatNetworkDiagnosis.refresh()'))

    def test_local_ai_research_updates_pilot_brain_and_repairs_are_review_gated(self):
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        self.assertIn('Duration(hours: 24)', ai)
        self.assertIn('_relevantResearchMemory(safePrompt)', ai)
        self.assertIn('notes.take(2)', ai)
        self.assertIn('not live telemetry', ai)
        self.assertIn("'draft': true", ai)
        self.assertIn('repairUntilGreen', ai)
        self.assertIn('No automatic merge or release is performed.', ai)
        self.assertIn('This updates research memory, not model weights.', ai)

    def test_weather_and_current_queries_use_live_public_research(self):
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        self.assertIn('هوا|دمای|بارش|باد', ai)
        self.assertIn('researchGoogle(publicQuery, maxResults: 3)', ai)

    def test_smart_command_chat_receives_bounded_live_vpn_context(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        self.assertIn('appContext: liveContext', main)
        self.assertIn('Last failure:', main)
        self.assertIn('LIVE KING VPN APP STATE (untrusted telemetry; evidence only', ai)
        self.assertIn('_redactConversationSecrets(appContext.trim())', ai)

    def test_voice_commands_receive_voice_responses_and_text_stays_text(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        voice = (ROOT / 'lib' / 'king_voice_output.dart').read_text(encoding='utf-8')
        workflow = (ROOT / '.github' / 'workflows' / 'build.yml').read_text(encoding='utf-8')
        self.assertIn('flutter_tts', workflow)
        self.assertIn('_smartSpeechVoiceInput', main)
        self.assertIn('if (voiceResponse) await _speakSmartCommandResponse(voiceReply ?? status)', main)
        self.assertIn('onChanged: (_) => _smartSpeechVoiceInput = false', main)
        self.assertIn('setLanguage', voice)
        self.assertIn('fa-IR', voice)

    def test_national_runtime_optimization_is_not_misclassified_as_code(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = main.index('final codeRequest = !KingCommandSafety.isQuestionRequest(command) && RegExp(')
        end = main.index(').hasMatch(command);', start)
        code_request = main[start:end]
        self.assertIn('(کل اپ|کل برنامه|کل پروژه)', code_request)
        self.assertIn('قابلیت.{0,12}(اضافه کن|بساز|ایجاد کن)', code_request)
        self.assertNotIn('(اینترنت ایران|نت ملی).{0,30}(بهینه|ارتقا', code_request)

    def test_voice_chat_uses_local_persian_tts_and_owner_task_prefill(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        console = (ROOT / 'lib' / 'king_ai_console.dart').read_text(encoding='utf-8')
        voice = (ROOT / 'lib' / 'king_voice_output.dart').read_text(encoding='utf-8')
        self.assertIn('if (voiceResponse) await _speakSmartCommandResponse(voiceReply ?? status)', main)
        self.assertIn('onChanged: (_) => _smartSpeechVoiceInput = false', main)
        self.assertIn('initialFeatureRequest: command', main)
        self.assertIn('speakResponses: voiceResponse', main)
        self.assertIn('widget.initialFeatureRequest', console)
        self.assertIn('widget.speakResponses', console)
        self.assertIn("setLanguage('fa-IR')", voice)

    def test_flutter_artifact_path_matches_arm64_split_release_apk_build(self):
        workflow = (ROOT / '.github' / 'workflows' / 'build.yml').read_text(encoding='utf-8')
        self.assertIn('flutter build apk --release --obfuscate --split-debug-info=build/symbols --target-platform android-arm64 --split-per-abi', workflow)
        self.assertIn('Upload Dart obfuscation symbols', workflow)
        self.assertIn('repair-evidence/gradle-build-tail.txt', workflow)
        self.assertIn('repair-evidence/lint/', workflow)
        self.assertIn('king-vpn-symbols-${{ github.run_number }}', workflow)
        self.assertIn('build_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk', workflow)
        self.assertIn('Report optimized APK size', workflow)
        self.assertIn('king-vpn-arm64-release-${{ github.run_number }}', workflow)
        self.assertIn('king-vpn-full-source-${{ github.run_number }}.zip', workflow)
        self.assertIn('build_app/android/local.properties', workflow)
        self.assertIn('Upload complete project ZIP', workflow)
        self.assertIn('${{ runner.temp }}', workflow)

    def test_android_toolchain_matches_flutter_350_and_kotlin_2420(self):
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        self.assertIn("AGP_VERSION = '9.3.1'", prepare)
        self.assertIn("GRADLE_VERSION = '9.5.0'", prepare)
        self.assertIn("Kotlin 2.4.20", prepare)

    def test_flutter_sdk_included_build_resolves_kotlin_plugin_transitives(self):
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        self.assertIn("packages/flutter_tools/gradle", prepare)
        self.assertIn("flutter_settings = os.path.join(", prepare)
        self.assertIn("FLUTTER_ROOT", prepare)
        self.assertIn("mavenCentral()", prepare)
        self.assertIn("gradlePluginPortal()", prepare)

    def test_plugin_dart_parser_hardening_is_part_of_build_patch(self):
        patch = (ROOT / 'patch_plugin.py').read_text(encoding='utf-8')
        for name in ('patch_url_dart', 'patch_vmess_dart', 'patch_vless_dart',
                     'patch_trojan_dart', 'patch_shadowsocks_dart'):
            self.assertIn(name, patch)
        parser_base = (ROOT / 'plugin_source_reference' / 'dart' / 'lib' / 'url' / 'url.dart').read_text(encoding='utf-8')
        self.assertIn('String fallbackSni(', parser_base)


    def test_flutter_included_build_resolves_kotlin_plugins_from_maven(self):
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        self.assertIn("packages/flutter_tools/gradle", prepare)
        self.assertIn(r"pm = re.search(r'pluginManagement\s*\{', flutter_settings_text)", prepare)
        self.assertIn("if not pm:", prepare)
        self.assertIn(r"'        mavenCentral()\n'", prepare)
        self.assertIn(r"'        gradlePluginPortal()\n'", prepare)
        self.assertIn("MAVEN_CENTRAL_MIRROR", prepare)
        self.assertIn("dependencyResolutionManagement", prepare)
        self.assertIn("def add_maven_mirror_to_scope", prepare)
        self.assertIn("root_mirror_entry", prepare)
        self.assertIn("matching_brace", prepare)
        self.assertIn("maven-central.storage-download.googleapis.com/maven2/", prepare)


    def test_android_host_does_not_request_unneeded_all_files_access(self):
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertNotIn('android.permission.MANAGE_EXTERNAL_STORAGE', prepare)
        self.assertNotIn('Permission.manageExternalStorage', main)


    def test_owner_idea_analysis_is_separate_and_owner_gated(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        console = (ROOT / 'lib' / 'king_ai_console.dart').read_text(encoding='utf-8')
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        start = main.index('Future<void> _runSmartCommand')
        end = main.index('Widget _smartCommandPanel()', start)
        dispatcher = main[start:end]
        self.assertIn('analysisOnlyRequest', dispatcher)
        self.assertIn('analysisOnlyRequest && KingAiOwnerAuth.instance.hasActiveSession', dispatcher)
        self.assertIn('initialIdeaAnalysis: command', dispatcher)
        self.assertIn('speakResponses: voiceResponse', dispatcher)
        self.assertIn('Future<String> analyzeOwnerIdea', ai)
        idea_start = ai.index('Future<String> analyzeOwnerIdea')
        idea_end = ai.index('Future<String> _askCoding', idea_start)
        idea_flow = ai[idea_start:idea_end]
        self.assertIn('hasActiveSession', idea_flow)
        self.assertNotIn('_createRepairPullRequest', idea_flow)
        self.assertIn('فقط تحلیل ایده (بدون تغییر کد)', console)



    def test_voice_idea_analysis_speaks_raw_text_not_json_quoted_string(self):
        console = (ROOT / 'lib' / 'king_ai_console.dart').read_text(encoding='utf-8')
        self.assertIn('final rendered = result is String', console)
        self.assertIn('final summary = result is String', console)
        self.assertIn('KingVoiceOutput.instance.speakPersian(summary)', console)



    def test_server_reachability_uses_generic_public_endpoints_not_gemini(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = main.index('Future<bool> internetEndpointsOpen(')
        end = main.index('String buildPersonalLink(', start)
        probe = main[start:end]
        for endpoint in (
            'https://www.google.com/generate_204',
            'https://www.youtube.com/generate_204',
            'https://cp.cloudflare.com/generate_204',
        ):
            self.assertIn(endpoint, probe)
        self.assertIn('HttpStatus.noContent', probe)
        self.assertNotIn('gemini.google.com', main)
        self.assertNotIn('generativelanguage.googleapis.com', main)
        self.assertNotIn('geminiOpens(', main)
        self.assertNotIn('_gemSkip(', main)

    def test_connected_auto_analysis_uses_only_loaded_local_king_model(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = main.index('Future<void> _aiRunAuto()')
        end = main.index('Future<void> _aiLoop(', start)
        auto = main[start:end]
        self.assertIn('aiAnalyze(auto: true)', auto)
        self.assertNotIn('geminiKey', auto)
        extras = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        start = extras.index('Future<String> aiAsk(String prompt)')
        end = extras.index('void aiShow(', start)
        dispatcher = extras[start:end]
        self.assertIn("aiProvider = 'local';", dispatcher)
        self.assertIn('KingLocalAi.instance.ask(prompt)', dispatcher)
        self.assertNotIn('geminiAsk(', dispatcher)
        self.assertNotIn('grokAsk(', dispatcher)


    def test_legacy_remote_llm_providers_are_purged_and_never_called(self):
        extras = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        for forbidden in (
            'generativelanguage.googleapis.com',
            'gemini.google.com',
            'api.x.ai',
            'api.anthropic.com',
            'api.openai.com',
            'api.deepseek.com',
            'Future<String> geminiAsk(',
            'Future<String> grokAsk(',
            'startGrokPilot(',
            'grokPilotPrompt(',
        ):
            self.assertNotIn(forbidden, extras + main)
        self.assertIn('loadLocalAiPrefs(p)', main)
        self.assertIn('Future<void> loadLocalAiPrefs(SharedPreferences prefs)', extras)
        for legacy_key in ('gem_key', 'grok_key', 'claude_key', 'openai_key', 'deepseek_key'):
            self.assertIn(legacy_key, extras)  # deleted from both prefs and secure storage
        self.assertIn('aiAsk(aiPrompt())', extras)
        self.assertIn('KingLocalAi.instance.ask(prompt)', extras)


    def test_unified_pilot_starts_and_stops_local_king_advisory_safely(self):
        extras = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        start = extras.index('Future<void> startLocalPilot({bool pinNetworkMode = false})')
        end = extras.index('Map<String, Object?> _takePilotSnap()', start)
        pilot_start = extras[start:end]
        self.assertIn('ensureLocalPilotRunning();', pilot_start)
        self.assertIn('await NationalNetworkIntelligence.load();', pilot_start)
        self.assertIn('if (_hasAnyAiKey)', pilot_start)
        self.assertIn('aiSession = true;', pilot_start)
        self.assertIn('aiAutopilotStart();', pilot_start)
        stop_start = extras.index('void stopLocalPilot()')
        stop_end = extras.index('\n  }', stop_start) + 4
        stop = extras[stop_start:stop_end]
        self.assertIn('stopAiSession();', stop)
        self.assertNotIn('stopGrokPilot', extras)
        self.assertIn('aiAsk(aiPrompt())', extras)


    def test_all_source_merges_remain_owner_reviewed(self):
        workflows = ROOT / '.github' / 'workflows'
        self.assertFalse((workflows / 'king-ai-safe-automerge.yml').exists())
        for workflow in workflows.glob('*.yml'):
            content = workflow.read_text(encoding='utf-8')
            self.assertNotIn('github.rest.pulls.merge', content)
            self.assertNotIn('gh pr merge', content)
        policy = (ROOT / 'lib' / 'king_ai_autonomy_policy.dart').read_text(encoding='utf-8')
        self.assertIn('KingAiAutonomyOperation.applySourceChanges', policy)
        self.assertIn('evidence.ownerAuthenticated', policy)
        self.assertIn('evidence.ownerCommandAuthorizedForCandidate', policy)


    def test_legacy_ai_server_flags_are_revalidated_as_generic_web_evidence(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn('s.ai = null; // force revalidation', main)
        self.assertNotIn("s.ai = j['a'] as bool?;", main)
        self.assertIn("RowDef('ai', '🌐 سرورهای دارای دسترسی وب'", main)
        for old_provider in ('Gemini', 'Grok', 'Claude', 'gemini', 'grok', 'claude'):
            self.assertNotIn(old_provider, main)

    def test_local_king_uses_real_network_evidence_and_bounded_tuning(self):
        extras = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        prompt_start = extras.index('String aiPrompt()')
        prompt_end = extras.index('Future<void> aiAnalyze(', prompt_start)
        prompt = extras[prompt_start:prompt_end]
        self.assertIn('PilotNetworkProbe.current', prompt)
        self.assertIn('NatNetworkDiagnosis.current', prompt)
        self.assertIn('NationalNetworkIntelligence.scoreFor', prompt)
        self.assertIn('not proof of VPN data-plane', prompt)
        self.assertIn('fastWorkers, 1, 20', extras)
        self.assertIn('bgWorkers, 1, 3', extras)
        self.assertIn('speedTopN, 1, 10', extras)

    def test_stopping_pilot_invalidates_pending_local_ai_and_manual_analysis_is_non_mutating(self):
        extras = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        analyze_start = extras.index('Future<void> aiAnalyze(')
        analyze_end = extras.index('void autoAiAfterConnect()', analyze_start)
        analyze = extras[analyze_start:analyze_end]
        self.assertIn('if (auto && (!aiSession || !localPilotOn)) return;', analyze)
        self.assertIn('if (auto && aiSession && localPilotOn) applyAiSuggest();', analyze)
        self.assertNotIn('\n      applyAiSuggest();', analyze)
        delayed_start = extras.index('void autoAiAfterConnect()')
        delayed_end = extras.index('void aiAutopilotStart()', delayed_start)
        delayed = extras[delayed_start:delayed_end]
        self.assertIn('!aiSession || !localPilotOn', delayed)
        tick_start = extras.index('Future<void> aiAutopilotTick()')
        tick_end = extras.index('Future<void> aiRunAction()', tick_start)
        tick = extras[tick_start:tick_end]
        self.assertIn('final answer = await aiAsk(aiPrompt());', tick)
        self.assertIn('if (!mounted || !aiSession || !localPilotOn) return;', tick)
        self.assertIn('if (!aiSession || !localPilotOn) return;', tick)
        action_start = extras.index('Future<void> aiRunAction()')
        action_end = extras.index('void applyAiSuggest()', action_start)
        self.assertIn('if (!aiSession || !localPilotOn || a.isEmpty', extras[action_start:action_end])

    def test_legacy_provider_cleanup_has_one_bounded_timeout(self):
        extras = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        start = extras.index('Future<void> loadLocalAiPrefs(')
        end = extras.index('Future<String> aiAsk(', start)
        loader = extras[start:end]
        self.assertIn('Future.wait(legacyKeys.map((key) => prefs.remove(key)))', loader)
        self.assertIn('Future.wait(legacyKeys.map((key) => _secure.delete(key: key)))', loader)
        self.assertIn('Duration(seconds: 5)', loader)
        self.assertNotIn('for (final key in legacyKeys)', loader)


    def test_general_king_chat_persists_bounded_redacted_context_without_code_authority(self):
        ai = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        ask_start = ai.index('Future<String> ask(')
        ask_end = ai.index('Future<String> _askCoding(', ask_start)
        chat = ai[ask_start:ask_end]
        self.assertIn('_conversationSystemPrompt', chat)
        self.assertIn('_loadConversationMemory()', chat)
        self.assertIn('_saveConversationMemory()', chat)
        self.assertIn('_looksLikeCodeGenerationRequest(prompt)', chat)
        self.assertIn("king_ai_conversation_memory_v2", ai)
        self.assertIn('_secure.read(key: _conversationMemoryKey)', ai)
        self.assertIn('_secure.write(', ai)
        self.assertIn('_redactConversationSecrets', ai)
        self.assertIn('length > 12', chat)
        self.assertIn('_relevantResearchMemory(safePrompt)', chat)
        self.assertIn('_needsLiveResearch(safePrompt)', chat)
        self.assertIn('isSafeKingAiPublicResearchQuery(safePrompt)', chat)
        self.assertIn('researchGoogle(publicQuery, maxResults: 3)', chat)
        self.assertIn('redactedQuery.length > 400', chat)
        self.assertIn('var research = needsLiveResearch', chat)
        self.assertIn('Never pass old cached pages as if they were current information.', chat)
        self.assertIn('Fetched: $fetchedAt', ai)
        selector_start = ai.index('Future<List<String>> _selectRelevantPaths')
        selector_end = ai.index('/// Reads a small, relevant Dart/Python source subset', selector_start)
        selector = ai[selector_start:selector_end]
        self.assertIn('words.intersection(pathWords)', selector)
        self.assertNotIn('await ask(', selector)
        self.assertIn('hasActiveSession', ai[ai.index('Future<Map<String, Object?>> proposeRepair'):])

    def test_owner_only_background_maintenance_and_research_allowlist(self):
        background = (ROOT / 'lib' / 'king_ai_background.dart').read_text(encoding='utf-8')
        policy = (ROOT / 'lib' / 'king_ai_research_policy.dart').read_text(encoding='utf-8')
        docs = (ROOT / 'docs' / 'KING_AI_AUTONOMOUS_MAINTENANCE.md').read_text(encoding='utf-8')
        self.assertIn('_requireOwnerSession();', background)
        self.assertIn('enableAutonomousMaintenance()', background)
        self.assertIn('https', policy)
        self.assertIn('isTrustedKingAiResearchUri', policy)
        self.assertIn('fresh owner-password proof', docs)
        self.assertIn('owner review', docs)
        self.assertIn('green CI', docs)
        self.assertIn('package installer still asks the user to confirm installation', docs)

    def test_stable_success_requires_fresh_multi_destination_tunnel_traffic(self):
        national = (ROOT / 'lib' / 'national_engine.dart').read_text(encoding='utf-8')
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn('Future<bool> Function() verifyStableTraffic', national)
        self.assertIn('if (await verifyStableTraffic()) await recordStable(endpointKey);', national)
        self.assertIn('Future<bool> _stableTunnelTrafficOk(Server server)', main)
        self.assertIn('_siteOpens(url, viaCore: true)', main)
        self.assertIn('passed >= 2', main)
        self.assertIn('() => _stableTunnelTrafficOk(s)', main)


    def test_every_privileged_code_operation_requires_fresh_owner_proof(self):
        auth = (ROOT / 'lib' / 'king_ai_owner_auth.dart').read_text(encoding='utf-8')
        console = (ROOT / 'lib' / 'king_ai_console.dart').read_text(encoding='utf-8')
        self.assertIn('sessionLifetime = Duration(minutes: 2)', auth)
        self.assertIn('_reauthenticateOwnerForCodeChange()', console)
        for method in ('_submitFeatureRequest', '_repair', '_enableBackground',
                       '_enableAutomaticDiscovery', '_saveToken', '_clearToken'):
            start = console.index('Future<void> ' + method)
            end = console.find('\n  Future<void> ', start + 1)
            if end < 0:
                end = console.find('\n  @override', start + 1)
            self.assertIn('_reauthenticateOwnerForCodeChange()', console[start:end], method)
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn('if (s != AppLifecycleState.resumed) KingAiOwnerAuth.instance.lock();', main)

    def test_apk_updater_streams_hash_verification_and_uses_android_fileprovider(self):
        update = (ROOT / 'lib' / 'update_check.dart').read_text(encoding='utf-8')
        integrity = (ROOT / 'lib' / 'update_integrity.dart').read_text(encoding='utf-8')
        native = (ROOT / 'android_src' / 'MainActivity.kt').read_text(encoding='utf-8')
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn('verifySha256File(file, sha256Expected)', update)
        self.assertIn('client.send(request)', update)
        self.assertIn('..followRedirects = false', update)
        self.assertIn('resolveAllowedUpdateRedirect(currentUri, location)', update)
        self.assertIn('response.stream.listen((_) {}).cancel()', update)
        self.assertNotIn('streamed.request?.url', update)
        self.assertIn('Uri? resolveAllowedUpdateRedirect', integrity)
        self.assertIn('_kingUpdateChannel.invokeMethod', update)
        self.assertNotIn('Uri.file(file.path)', update)
        self.assertIn('PackageInfo.fromPlatform()', update)
        self.assertIn('Future<bool> verifySha256File(File file', integrity)
        self.assertIn('FileProvider.getUriForFile', native)
        self.assertIn('ACTION_MANAGE_UNKNOWN_APP_SOURCES', native)
        self.assertIn('REQUEST_INSTALL_PACKAGES', prepare)
        self.assertIn('king_file_paths.xml', prepare)
        self.assertIn('package_info_plus', main)

    def test_training_dataset_never_pushes_directly_to_main(self):
        workflow = (ROOT / '.github' / 'workflows' / 'king-ai-repair-dataset.yml').read_text(encoding='utf-8')
        self.assertIn('gh pr create', workflow)
        self.assertIn('Review and merge are required', workflow)
        self.assertNotIn('git push origin HEAD:main', workflow)
        self.assertNotIn('git push origin HEAD:refs/heads/main', workflow)


    def test_autonomous_source_audit_rechecks_owner_opt_in_in_worker(self):
        background = (ROOT / 'lib' / 'king_ai_background.dart').read_text(encoding='utf-8')
        audit_start = background.index('if (task == _auditTaskName)')
        audit_end = background.index('await ai.createAutonomousMaintenanceProposal(', audit_start)
        audit = background[audit_start:audit_end]
        self.assertIn('isBackgroundAutoDiscoveryEnabled()', audit)
        self.assertIn('return true;', audit)
        self.assertLess(audit.index('isBackgroundAutoDiscoveryEnabled()'),
                        audit.index('hasGitHubToken()'))
        self.assertLess(audit.index('hasGitHubToken()'),
                        audit.index('loadInstalledModelForBackground()'))


    def test_generated_fileprovider_manifest_uses_real_xml_newlines(self):
        source = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        start = source.index('UPDATE_PROVIDER =')
        end = source.index("if 'androidx.core.content.FileProvider'", start)
        provider = source[start:end]
        self.assertIn(r'FileProvider"\n', provider)
        self.assertNotIn(r'FileProvider"\\n', provider)
        self.assertIn('@xml/king_file_paths', provider)

    def test_explicit_network_command_pins_smart_pilot_mode_for_session(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        pilot = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        command_start = main.index('} else if (requestedNetworkMode != null && wantsConnect)')
        command_end = main.index("} else if (!negatesScan && command.contains('بازه')", command_start)
        command = main[command_start:command_end]
        self.assertIn('await startLocalPilot(pinNetworkMode: true);', command)
        self.assertIn('bool _pilotNetworkModePinned = false;', pilot)
        detect_start = pilot.index('Future<NatNetworkClass> _pilotDetectNetworkMode() async')
        detect_end = pilot.index('void ensureLocalPilotRunning()', detect_start)
        detection = pilot[detect_start:detect_end]
        self.assertIn('if (!_pilotNetworkModePinned)', detection)
        self.assertIn('PILOT-MODE-PINNED', detection)
        start = pilot.index('Future<void> startLocalPilot({bool pinNetworkMode = false})')
        stop = pilot.index('void stopLocalPilot()', start)
        lifecycle = pilot[start:stop]
        self.assertIn('_pilotNetworkModePinned = pinNetworkMode;', lifecycle)
        self.assertIn('_pilotNetworkModePinned = false;', lifecycle)
        self.assertIn('_pilotNetworkModePinned = false;', pilot[stop:stop + 220])
        self.assertIn('final disconnectIntent = KingCommandSafety.isDisconnectIntent(normalizedCommand);', main)
        self.assertIn('if (disconnectIntent)', main)
        self.assertNotIn("else if (RegExp(r'(قطع اتصال|قطع|disconnect|خاموش کردن اتصال)'", main)


    def test_failed_endpoint_checks_invalidate_stale_ping_evidence(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        record_start = main.index('void _record(Server s, int? d)')
        record_end = main.index('// TCP prefilter', record_start)
        self.assertIn('s.ping = null;', main[record_start:record_end])

        standby_start = main.index('Future<void> _recheckStandby()')
        standby_end = main.index('// SPEEDSWITCHPATCH', standby_start)
        standby = main[standby_start:standby_end]
        self.assertIn('if (d == null) {\n          s.ping = null;', standby)

        ping_start = main.index('Future<List<Server>> _pingRecheck()')
        ping_end = main.index('// manual = started by the user', ping_start)
        ping_recheck = main[ping_start:ping_end]
        self.assertIn('if (d == null) {\n        s.ping = null;', ping_recheck)

        stable_start = main.index('Future<void> _stableCheck()')
        stable_end = main.index('Future<void> _stableSwap(', stable_start)
        stable = main[stable_start:stable_end]
        self.assertIn('if (d == null) {\n            c.ping = null;', stable)
        self.assertIn('if (r.length < 3) {\n        // A partial/failed confirmation', stable)
        self.assertIn('t.ping = null;', stable)

    def test_national_pilot_uses_per_server_verified_learning(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        pilot = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        self.assertIn('void _nnieBeginAttempt(Server server)', main)
        self.assertIn('int? _nnieFinishAttempt(Server server)', main)
        self.assertIn('elapsedMs: nnieElapsedMs ?? max(0, s.ping ?? 0)', main)
        success_start = main.index('// NNIE records end-to-end successes in BOTH domestic and global modes.')
        success_end = main.index('if (mounted) setState(() {})', success_start)
        success_record = main[success_start:success_end]
        self.assertIn('NationalNetworkIntelligence.record(', success_record)
        self.assertIn('NationalNetworkIntelligence.armStable(', success_record)
        self.assertNotIn('if (nationalMode)', success_record)
        self.assertIn('final failedElapsedMs = _nnieFinishAttempt(s) ?? 0;', main)
        self.assertNotIn('_nnieTapAt', main)
        tunnel_fail = main.index('// Record a server-level failure only after the same-server')
        tunnel_fail_end = main.index("final ip1 = await resolveHostIp(s.host);", tunnel_fail)
        failure_record = main[tunnel_fail:tunnel_fail_end]
        self.assertIn('NationalNetworkIntelligence.record(', failure_record)
        self.assertIn('success: false', failure_record)
        self.assertIn('if (!abort && wantVpn)', failure_record)
        self.assertIn('await NationalNetworkIntelligence.load();', pilot)
        self.assertIn('NationalNetworkIntelligence.scoreFor(', pilot)
        standby_start = pilot.index('Server? _pilotBestStandby()')
        standby_end = pilot.index('Future<void> _pilotLoadExperience()', standby_start)
        standby = pilot[standby_start:standby_end]
        self.assertIn('double _pilotStandbyScore(Server s)', pilot)
        self.assertIn('final learned = NationalNetworkIntelligence.scoreFor(', pilot)
        self.assertIn('final pingSuccessfulFresh = pingFresh && s.ping != null && s.ping! > 0;', pilot)
        self.assertIn('if (pingSuccessfulFresh && s.svc >= 0)', pilot)
        self.assertNotIn('if (pingFresh && s.svc >= 0)', pilot)
        self.assertIn('isFresh(s.checkedAt, const Duration(minutes: 4))', pilot)
        self.assertIn('isFresh(s.speedAt, const Duration(minutes: 5))', pilot)
        self.assertIn('if (pingFresh && ping != null && ping > 0)', pilot)
        self.assertIn('if (speedFresh && (s.speed ?? 0) > 0)', pilot)
        self.assertIn('bestScore < _pilotStandbyScore(active) + 12.0', standby)
        self.assertNotIn('if (nationalMode)', standby)


    def test_smart_command_uses_safe_disconnect_intent_and_voice_answer(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = main.index('Future<void> _runSmartCommand')
        end = main.index('Widget _smartCommandPanel()', start)
        dispatcher = main[start:end]
        self.assertIn('KingCommandSafety.isDisconnectIntent(normalizedCommand)', dispatcher)
        self.assertNotIn("RegExp(r'(قطع اتصال|قطع|disconnect|خاموش کردن اتصال)')", dispatcher)
        self.assertIn('voiceReply = answer;', dispatcher)
        self.assertIn('_speakSmartCommandResponse(voiceReply ?? status)', dispatcher)


    def test_local_chat_and_pilot_share_a_serialized_inference_queue(self):
        local = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        self.assertIn('Future<void> _generationQueue = Future<void>.value();', local)
        self.assertIn('Future<T> _runSerializedGeneration<T>', local)
        self.assertIn('return _runSerializedGeneration(() async {', local)
        self.assertEqual(local.count('engine.generate('), 2)
        self.assertNotIn("if (_busy) throw StateError('Local AI is already generating');", local)


    def test_check_host_inputs_are_validated_and_query_encoded(self):
        source = (ROOT / 'lib' / 'king_extras2.dart').read_text(encoding='utf-8')
        start = source.index('Future<CheckHostResult?> checkHostTcp(')
        end = source.index('class ', start)
        fn = source[start:end]
        self.assertIn("Uri.https('check-host.net', '/check-tcp'", fn)
        self.assertIn("Uri.https('check-host.net', '/check-result/$requestId')", fn)
        self.assertIn("RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(requestId)", fn)
        self.assertIn("'host': '$queryHost:$port'", fn)
        self.assertNotIn('host=$host:$port', fn)

        start = source.index("const String _kCfWorkerTemplate = r'''")
        end = source.index('class CfDeployResult', start)
        worker = source[start:end]
        self.assertIn('let initialBuffer = new Uint8Array(0);', worker)
        self.assertIn('function parseVlessHeader(buffer)', worker)
        self.assertIn('if (uuid !== UUID_HEX) throw new Error(\'Invalid UUID\');', worker)
        self.assertIn('if (buffer.length < 18) return null;', worker)
        self.assertIn('VLESS request header can span multiple WebSocket frames.', worker)
        self.assertIn("if (initialBuffer.length > 1024)", worker)
        self.assertNotIn('if (chunk.length < 24)', worker)

    def test_failed_plugin_start_stops_partially_running_core(self):
        patch = (ROOT / 'patch_plugin.py').read_text(encoding='utf-8')
        start = patch.index('private boolean failStart(String reason)')
        end = patch.index('P1-27 start failure state and timer reset', start)
        failure = patch[start:end]
        self.assertIn('coreController.getIsRunning()', failure)
        self.assertIn('coreController.stopLoop();', failure)

    def test_v2ray_connected_delay_handoff_is_process_safe(self):
        patch = (ROOT / 'patch_plugin.py').read_text(encoding='utf-8')
        self.assertIn('P1-33 delay URL handoff and receiver-before-dispatch', patch)
        self.assertIn('P1-33 VPN service receives delay URL', patch)
        self.assertIn('P1-33 ProxyOnly service receives delay URL', patch)
        self.assertIn('check_delay.putExtra("DELAY_URL", AppConfigs.DELAY_URL);', patch)
        self.assertIn('Register before dispatch so a fast service response cannot be missed.', patch)
        self.assertIn('P1-33 use flagged receiver overload only on API 33+', patch)
        self.assertIn('Build.VERSION_CODES.TIRAMISU', patch)

    def test_hot_cache_uses_shared_future_and_scoped_storage_permission(self):
        source = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        self.assertIn('Future<void>? _hotEnsureFuture;', source)
        self.assertIn('await active;', source)
        self.assertIn('Future<void> _natHotEnsureImpl({bool force = false}) async', source)
        self.assertIn('final seenKeys = <String>{};', source)
        self.assertIn('if (!seenKeys.add(cfg)) continue;', source)
        fill_start = source.index('Future<void> hotAutoFill() async')
        fill_end = source.index('Future<void> hotAutoStart()', fill_start)
        self.assertNotIn('manageExternalStorage', source[fill_start:fill_end])
        ensure_start = source.index('Future<void> natHotEnsure({bool force = false})')
        ensure_end = source.index('Future<void> _natHotEnsureImpl', ensure_start)
        self.assertNotIn('hotStorageAllow', source[ensure_start:ensure_end])
        export_start = source.index('Future<void> hotExportToDownload() async')
        export_end = source.index('List<String> natHotUrls()', export_start)
        self.assertIn('await hotStorageAllow()', source[export_start:export_end])

    def test_active_v2ray_plugin_lifecycle_patch_is_fail_closed(self):
        patch = (ROOT / 'patch_plugin.py').read_text(encoding='utf-8')
        self.assertIn('Lifecycle foreground promotion reports success/failure', patch)
        self.assertIn('P1-27 start failure state and timer reset', patch)
        self.assertIn('P1-31 VPN foreground before TUN/core startup', patch)
        self.assertIn('P1-31 proxy foreground before core startup', patch)
        self.assertIn("'P1-28 ' + svc_name + ' STOP always cleans up service'", patch)
        self.assertIn("'P1-28 ' + svc_name + ' STOP always cleans up service'", patch)
        self.assertIn('P1-30 VPN revoke always releases TUN/service', patch)
        self.assertIn("src.replace('this.onDestroy();', 'stopAllProcess();')", patch)
        self.assertIn('refusing to start core', patch)

    def test_vpn_service_promotes_before_queuing_sticky_restart_or_stop(self):
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = service.index('public int onStartCommand(Intent intent')
        end = service.index('/** Runs a task on the single worker thread', start)
        command = service[start:end]
        restart = command[command.index('if (intent == null)'):command.index('String action = intent.getAction()')]
        stop = command[command.index('if (ACTION_STOP.equals(action))'):command.index('if (!ACTION_START.equals(action))')]
        self.assertLess(restart.index('startForegroundSafe('), restart.index('submit(this::resumeSaved)'))
        self.assertLess(stop.index('startForegroundSafe('), stop.index('submit(this::stopEverything)'))

    def test_vpn_service_serializes_worker_submission_and_shutdown(self):
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        submit_start = service.index('private void submit(Runnable r)')
        submit_end = service.index('/** Worker side of ACTION_START', submit_start)
        submit = service[submit_start:submit_end]
        self.assertIn('synchronized (workerLock)', submit)
        self.assertIn('ex.execute(r)', submit)
        self.assertIn('RejectedExecutionException', submit)
        self.assertIn('worker unavailable; dropping task after shutdown', submit)
        self.assertNotIn('runFallback(r)', submit)

        destroy_start = service.index('public void onDestroy()')
        destroy_end = service.index('private static String orEmpty', destroy_start)
        destroy = service[destroy_start:destroy_end]
        self.assertIn('synchronized (workerLock)', destroy)
        self.assertIn('ex.execute(this::stopEverything)', destroy)
        self.assertLess(destroy.index('ex.execute(this::stopEverything)'), destroy.index('ex.shutdown()'))
        self.assertIn('if (fallbackStop) runFallback(this::stopEverything);', destroy)


    def test_android_backup_excludes_vpn_credentials_and_local_ai_secrets(self):
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        backup = (ROOT / 'android_src' / 'king_backup_rules.xml').read_text(encoding='utf-8')
        extraction = (ROOT / 'android_src' / 'king_data_extraction_rules.xml').read_text(encoding='utf-8')
        self.assertIn("('allowBackup', 'false')", prepare)
        self.assertIn("('fullBackupContent', 'false')", prepare)
        self.assertIn("('dataExtractionRules', '@xml/king_data_extraction_rules')", prepare)
        self.assertIn("king_backup_rules.xml", prepare)
        self.assertIn("king_data_extraction_rules.xml", prepare)
        for domain in ('root', 'file', 'database', 'sharedpref', 'external'):
            self.assertIn(f'domain="{domain}" path="."', backup)
            self.assertIn(f'domain="{domain}" path="."', extraction)
        self.assertIn('<device-transfer>', extraction)
        self.assertIn('<cloud-backup>', extraction)

    def test_test_methods_are_unique(self):
        import ast
        source = Path(__file__).read_text(encoding='utf-8')
        tree = ast.parse(source)
        duplicates = []
        for node in tree.body:
            if isinstance(node, ast.ClassDef):
                names = [item.name for item in node.body
                         if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef))
                         and item.name.startswith('test_')]
                duplicates.extend(sorted({name for name in names if names.count(name) > 1}))
        self.assertEqual([], duplicates, f'duplicate test methods: {duplicates}')


    def test_android_builds_include_required_webview_and_arm64_split(self):
        build = (ROOT / '.github' / 'workflows' / 'build.yml').read_text(encoding='utf-8')
        release = (ROOT / '.github' / 'workflows' / 'signed-release.yml').read_text(encoding='utf-8')
        orchestrator = (ROOT / 'tools' / 'repair_orchestrator.py').read_text(encoding='utf-8')
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        for source in (build, release, orchestrator):
            self.assertIn('webview_flutter', source)
        self.assertNotIn('abiFilters += listOf', prepare)
        self.assertNotIn('abiFilters "arm64-v8a"', prepare)
        self.assertNotIn('armeabi-v7a', prepare)
        self.assertIn('--split-per-abi', build)
        self.assertIn('--split-per-abi', release)
        self.assertIn('app-arm64-v8a-release.apk', build)
        self.assertIn('app-arm64-v8a-release.apk', release)
        self.assertIn("java-version: '21'", build)
        self.assertIn("java-version: '21'", release)
        self.assertIn("--obfuscate --split-debug-info=build/symbols", release)
        self.assertIn("king-vpn-signed-symbols-", release)




    def test_connected_national_range_scan_is_bounded_and_cancellable(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = main.index('Future<void> _natKeep()')
        end = main.index('// NATIONALPATCH: is the international internet cut', start)
        keep = main[start:end]
        self.assertIn('maxAddrs: 2048', keep)
        self.assertIn('conc: min(2, natAdaptiveWorkers())', keep)
        self.assertIn('budget: const Duration(seconds: 90)', keep)
        for condition in ('!mounted', '!connected', '!wantVpn', '!nationalMode',
                          '!localPilotOn', 'appGone', 'abort'):
            self.assertIn(condition, keep)
        self.assertIn('Do not publish stale discoveries after the tunnel/pilot stops.', keep)


    def test_backup_restore_has_single_hardened_exporter(self):
        backup = (ROOT / 'lib' / 'backup_restore.dart').read_text(encoding='utf-8')
        self.assertEqual(backup.count('Future<String> bkpExportJson() async {'), 1)
        exporter_start = backup.index('Future<String> bkpExportJson() async {')
        importer_start = backup.index('Future<int> bkpImportJson(String text)')
        exporter = backup[exporter_start:importer_start]
        self.assertIn('_bkpKeyAllowed(k)', exporter)
        self.assertIn('utf8.encode(encoded).length > _bkpMaxBytes', exporter)

    def test_backup_restore_bounds_and_validates_all_entries_before_writes(self):
        backup = (ROOT / 'lib' / 'backup_restore.dart').read_text(encoding='utf-8')
        self.assertIn('const int _bkpMaxBytes = 2 * 1024 * 1024;', backup)
        self.assertIn('const int _bkpMaxEntries = 500;', backup)
        self.assertIn('final RegExp _bkpAllowedKey', backup)
        self.assertIn('final RegExp _bkpSensitiveKey', backup)
        self.assertIn('if (utf8.encode(text).length > _bkpMaxBytes)', backup)
        self.assertIn('final staged = <String, Object>{};', backup)
        self.assertIn('No preferences are changed until every key and value has passed validation.', backup)
        import_start = backup.index('Future<int> bkpImportJson(String text)')
        import_end = backup.index('extension BkpExt', import_start)
        importer = backup[import_start:import_end]
        self.assertLess(importer.index('for (final entry in rawData.entries)'), importer.index('final p = await SharedPreferences.getInstance();'))
        self.assertIn('throw const FormatException', importer)
        self.assertIn('if (!ok)', importer)


if __name__ == '__main__':
    unittest.main()
