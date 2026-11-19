import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class KingVpnSourceGuardTests(unittest.TestCase):
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
        self.assertIn('_assistantSystemPrompt', public_ask)
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
        code_start = main.index('final codeRequest = RegExp(')
        code_end = main.index(').hasMatch(command);', code_start)
        self.assertIn('کدشو بنویس', main[code_start:code_end])
        self.assertIn('قابلیت اضافه', main[code_start:code_end])

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
        self.assertIn("_ownerConfigured && !await _requireOwnerSession('تغییر کلید GitHub')", console)
        for action in ('فعال‌سازی ترمیم خودکار پس‌زمینه','فعال‌سازی کشف خودکار مخزن','توقف ترمیم پس‌زمینه','پاک‌کردن کلید GitHub'):
            self.assertIn(f"_requireOwnerSession('{action}')", console)

    def test_national_network_optimization_requests_enter_owner_code_flow(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn("r'(نت ملی|اینترنت ایران).{0,40}(بهینه|ارتقا|بروز|به روز|خودکار|هوشمند|توسعه|تقویت)|'", main)
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
        self.assertIn('await _scheduleOfficialResearch();', worker)
        self.assertIn("const String _researchTaskName = 'kingAiIranNetworkResearch';", worker)
        self.assertIn('researchGoogle(_researchQuery, maxResults: 2)', worker)
        self.assertIn('frequency: const Duration(hours: 6)', worker)
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
        self.assertIn('!negatesConnection;', main)
        self.assertIn('KingCommandSafety.negatesScan(command)', main)
        self.assertIn("!negatesScan && command.contains('اسکن')", main)
        self.assertIn("!negatesScan && (command.contains('اسکنر dns')", main)
        self.assertIn("!negatesScan && (command.contains('اسکن ip')", main)
        self.assertIn("!negatesScan && (command.contains('اسکن sni')", main)

    def test_command_safety_helper_is_used_and_has_dart_unit_coverage(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        helper = (ROOT / 'lib' / 'king_command_safety.dart').read_text(encoding='utf-8')
        tests = (ROOT / 'test' / 'king_command_safety_test.dart').read_text(encoding='utf-8')
        self.assertIn("import 'king_command_safety.dart';", main)
        self.assertIn('KingCommandSafety.negatesConnection(command)', main)
        self.assertIn('KingCommandSafety.negatesScan(command)', main)
        self.assertIn('static bool negatesConnection(String command)', helper)
        self.assertIn('static bool negatesScan(String command)', helper)
        self.assertIn("test('negative connect commands are blocked'", tests)
        self.assertIn("test('negative scan commands are blocked'", tests)

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

    def test_king_voice_commands_are_persian_on_device_and_user_confirmed(self):
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
        self.assertIn('final codeRequest = RegExp(', main)
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

    def test_voice_commands_receive_voice_responses_and_text_stays_text(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        voice = (ROOT / 'lib' / 'king_voice_output.dart').read_text(encoding='utf-8')
        workflow = (ROOT / '.github' / 'workflows' / 'build.yml').read_text(encoding='utf-8')
        self.assertIn('flutter_tts', workflow)
        self.assertIn('_smartSpeechVoiceInput', main)
        self.assertIn('if (voiceResponse) await _speakSmartCommandResponse(status)', main)
        self.assertIn('onChanged: (_) => _smartSpeechVoiceInput = false', main)
        self.assertIn('setLanguage', voice)
        self.assertIn('fa-IR', voice)

    def test_national_runtime_optimization_is_not_misclassified_as_code(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = main.index('final codeRequest = RegExp(')
        end = main.index(').hasMatch(command);', start)
        code_request = main[start:end]
        self.assertIn('(کل اپ|کل برنامه|کل پروژه)', code_request)
        self.assertIn('(قابلیت جدید|امکانات جدید|افزودن|اضافه|کدنویسی|سورس|کد)', code_request)
        self.assertNotIn('(اینترنت ایران|نت ملی).{0,30}(بهینه|ارتقا', code_request)

    def test_voice_chat_uses_local_persian_tts_and_owner_task_prefill(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        console = (ROOT / 'lib' / 'king_ai_console.dart').read_text(encoding='utf-8')
        voice = (ROOT / 'lib' / 'king_voice_output.dart').read_text(encoding='utf-8')
        self.assertIn('if (voiceResponse) await _speakSmartCommandResponse(status)', main)
        self.assertIn('onChanged: (_) => _smartSpeechVoiceInput = false', main)
        self.assertIn('initialFeatureRequest: command', main)
        self.assertIn('speakResponses: voiceResponse', main)
        self.assertIn('widget.initialFeatureRequest', console)
        self.assertIn('widget.speakResponses', console)
        self.assertIn("setLanguage('fa-IR')", voice)

    def test_flutter_artifact_path_matches_non_split_apk_build(self):
        workflow = (ROOT / '.github' / 'workflows' / 'build.yml').read_text(encoding='utf-8')
        self.assertIn('flutter build apk --debug --target-platform android-arm64', workflow)
        self.assertIn('build_app/build/app/outputs/flutter-apk/app-debug.apk', workflow)
        self.assertNotIn('app-arm64-v8a-debug.apk', workflow)
        self.assertIn('king-vpn-full-source-${{ github.run_number }}.zip', workflow)
        self.assertIn('build_app/android/local.properties', workflow)
        self.assertIn('Upload complete project ZIP', workflow)
        self.assertIn('${{ runner.temp }}', workflow)

    def test_flutter_sdk_included_build_resolves_kotlin_plugin_transitives(self):
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        self.assertIn("packages/flutter_tools/gradle/settings.gradle.kts", prepare)
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


if __name__ == '__main__':
    unittest.main()
