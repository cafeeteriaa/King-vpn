import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class KingVpnSourceGuardTests(unittest.TestCase):
    def test_auto_scan_sheet_forwards_live_vpn_guards(self):
        source = (ROOT / 'lib' / 'auto_scanners.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> autoScanSheet(')
        body = source[start:]
        self.assertIn('isVpnActive: isVpnActive, isVpnWanted: isVpnWanted', body)

    def test_auto_sni_scan_refuses_to_compete_with_live_vpn(self):
        auto = (ROOT / 'lib' / 'auto_scanners.dart').read_text(encoding='utf-8')
        start = auto.index('Future<void> autoScanRun(')
        end = auto.index('Future<void> autoScanSheet(', start)
        body = auto[start:end]
        connected_guard = body.index('if (vpnActive() || vpnWanted())')
        lock = body.index('_autoScanRunning = true;')
        shared_lock = body.index('dnsxManualBusy = true;', lock)
        self.assertLess(connected_guard, lock)
        self.assertLess(lock, shared_lock)
        self.assertIn('ابتدا VPN را قطع کنید', body[connected_guard:lock])

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
        self.assertLess(loader.index('_busy = true;'), loader.index('await getApplicationSupportDirectory()'))
        self.assertIn('finally {', loader)
        self.assertIn('_busy = false;', loader)
        dispose_start = ai.index('Future<void> dispose()')
        dispose_end = ai.index('\n  }', dispose_start)
        dispose_body = ai[dispose_start:dispose_end]
        self.assertIn('finally {', dispose_body)
        self.assertIn('final previous = _generationQueue;', dispose_body)
        self.assertIn('await previous;', dispose_body)
        self.assertLess(dispose_body.index('await previous;'), dispose_body.index('if (_busy)'))
        self.assertIn('_busy = true;', dispose_body)
        self.assertIn('release.complete();', dispose_body)
        self.assertLess(dispose_body.index('engine.dispose()'), dispose_body.index('models.dispose()'))
        self.assertIn('sha256.bind(modelFile.openRead())', loader)
        self.assertIn('resolveSymbolicLinks()', loader)
        self.assertIn('repairFromFailedCiAutonomous(', worker)

    def test_chat_speech_listener_stops_after_widget_disposal(self):
        source = (ROOT / 'lib' / 'king_chat_page.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> _listen() async {')
        end = source.index('Future<void> _clearMemory() async {', start)
        listen = source[start:end]
        permission = listen.index('final permission = await Permission.microphone.request();')
        self.assertGreater(listen.index('if (!mounted) return;', permission), permission)
        initialize = listen.index('_speechReady = await _speech.initialize(')
        initialize_end = listen.index('if (!mounted) return;', initialize)
        self.assertLess(initialize, initialize_end)
        locales = listen.index('final locales = await _speech.locales();')
        self.assertGreater(listen.index('if (!mounted) return;', locales), locales)
        self.assertIn("} catch (error) {", listen)
        self.assertGreater(listen.index('if (!mounted) return;', listen.index('} catch (error) {')), listen.index('} catch (error) {'))


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
        self.assertIn("'android.permission.RECORD_AUDIO',", prepare)
        self.assertIn('for permission in required_permissions:', prepare)
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

    def test_async_sheet_callbacks_recheck_context_after_await(self):
        backup = (ROOT / 'lib' / 'backup_restore.dart').read_text(encoding='utf-8')
        ip_scan = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        self.assertIn('if (!mounted || !ctx0.mounted) return;', backup)
        self.assertIn('if (!mounted || !ctx0.mounted || !ctx.mounted) return;', backup)
        self.assertIn('await Clipboard.setData(ClipboardData(text: s));', backup)
        self.assertIn('await Clipboard.setData(ClipboardData(text: txt));', ip_scan)
        self.assertIn("await Clipboard.setData(ClipboardData(text: h.replaceAll('|', ':')));", ip_scan)
        self.assertGreaterEqual(ip_scan.count('if (!ctx0.mounted) return;'), 2)

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


    def test_native_apk_installer_accepts_only_the_verified_private_cache_asset(self):
        native = (ROOT / 'android_src' / 'MainActivity.kt').read_text(encoding='utf-8')
        start = native.index('"installApk" -> {')
        end = native.index('else -> result.notImplemented()', start)
        installer = native[start:end]
        self.assertIn('File(path).canonicalFile', installer)
        self.assertIn('File(cacheDir, "king_updates").canonicalFile', installer)
        self.assertIn('apk.parentFile != expectedUpdateDir', installer)
        self.assertIn('apk.name != "king-vpn-update.apk"', installer)
        self.assertIn('apkSize !in 1L..(300L * 1024L * 1024L)', installer)
        self.assertLess(installer.index('apk.parentFile != expectedUpdateDir'),
                        installer.index('FileProvider.getUriForFile'))

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
        resolve = main.index("final ip1 = await resolveHostIp(s.host);", tunnel_fail)
        resolve_guard = main.index('if (abort || !wantVpn)', resolve)
        record = main.index('NationalNetworkIntelligence.record(', resolve)
        failure_record = main[tunnel_fail:record]
        self.assertIn('if (abort || !wantVpn)', failure_record)
        self.assertLess(resolve, resolve_guard)
        self.assertLess(resolve_guard, record)
        self.assertIn('success: false', main[record:record + 500])
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
        self.assertIn("RegExp(r'^[A-Za-z0-9_-]{1,128}$')", fn)
        self.assertIn('hasMatch(requestId)', fn)
        self.assertIn("'host': '$queryHost:$port'", fn)
        self.assertIn('port > 65535', fn)

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

    def test_plugin_start_requires_native_core_running_before_connected(self):
        patch = (ROOT / 'patch_plugin.py').read_text(encoding='utf-8')
        start = patch.index("exact_replace(core, '''            coreController.startLoop(config, tunFd);")
        end = patch.index("'P1-34 verify native core running before connected'", start)
        block = patch[start:end]
        replacement_start = block.index("''', '''") + len("''', '''")
        replacement = block[replacement_start:]
        self.assertIn('if (!isV2rayCoreRunning())', replacement)
        self.assertIn('return failStart("native core did not enter running state");', replacement)
        self.assertLess(replacement.index('coreController.startLoop(config, tunFd);'),
                        replacement.index('if (!isV2rayCoreRunning())'))
        self.assertLess(replacement.index('if (!isV2rayCoreRunning())'),
                        replacement.index('V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_CONNECTED;'))
        self.assertLess(replacement.index('V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_CONNECTED;'),
                        replacement.index('showNotification(v2rayConfig);'))

    def test_v2ray_duration_timer_interval_and_rollover_are_correct(self):
        patch = (ROOT / 'patch_plugin.py').read_text(encoding='utf-8')
        self.assertIn('P1-35 duration timer interval is two hours', patch)
        self.assertIn('P1-35 duration clock uses full minute and day boundaries', patch)
        timer_start = patch.index("exact_replace(core, '''        countDownTimer = new CountDownTimer(7200, 1000) {")
        timer_end = patch.index("'P1-35 duration timer interval is two hours'", timer_start)
        timer_block = patch[timer_start:timer_end]
        self.assertIn('new CountDownTimer(7200L * 1000L, 1000L)', timer_block)

        rollover_start = patch.index("exact_replace(core, '''                seconds++;", timer_end)
        rollover_end = patch.index("'P1-35 duration clock uses full minute and day boundaries'", rollover_start)
        rollover_block = patch[rollover_start:rollover_end]
        replacement_start = rollover_block.index("''', '''") + len("''', '''")
        rollover = rollover_block[replacement_start:]
        self.assertIn('if (seconds >= 60)', rollover)
        self.assertIn('if (minutes >= 60)', rollover)
        self.assertIn('if (hours >= 24)', rollover)
        self.assertNotIn('seconds == 59', rollover)
        self.assertNotIn('minutes == 59', rollover)

    def test_v2ray_connected_delay_handoff_is_process_safe(self):
        patch = (ROOT / 'patch_plugin.py').read_text(encoding='utf-8')
        self.assertIn('P1-33 delay URL handoff and receiver-before-dispatch', patch)
        self.assertIn('P1-33 VPN service receives delay URL', patch)
        self.assertIn('P1-33 ProxyOnly service receives delay URL', patch)
        self.assertIn('check_delay.putExtra("DELAY_URL", AppConfigs.DELAY_URL);', patch)
        self.assertIn('Register before dispatch so a fast service response cannot be missed.', patch)
        self.assertIn('if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)', patch)
        self.assertIn('Build.VERSION_CODES.TIRAMISU', patch)

    def test_hot_cache_uses_shared_future_and_scoped_storage_permission(self):
        source = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        self.assertIn('Future<void>? _hotEnsureFuture;', source)
        self.assertIn('await active;', source)
        self.assertIn('Future<void> _natHotEnsureImpl({bool force = false}) async', source)
        self.assertIn('final seenKeys = <String>{};', source)
        self.assertIn('if (!seenKeys.add(config)) continue;', source)
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
        self.assertIn('P1-30 VPN revoke always releases TUN/service', patch)
        self.assertIn("src.replace('this.onDestroy();', 'stopAllProcess();')", patch)
        self.assertIn('refusing to start core', patch)

        promote_start = patch.index('public boolean promoteForStop(Service service)')
        promote_end = patch.index('Lifecycle foreground promotion reports success/failure', promote_start)
        promote = patch[promote_start:promote_end]
        self.assertIn('if (service == null) return false;', promote)
        self.assertIn('if (nm == null) return false;', promote)
        self.assertIn('service.startForeground(NOTIFICATION_ID, n);', promote)
        self.assertIn('return true;', promote)
        self.assertIn('return false;', promote)

        for label in (
            'P1-31 VPN foreground before TUN/core startup',
            'P1-31 proxy foreground before core startup',
        ):
            start = patch.index(label)
            block = patch[max(0, start - 1600):start]
            self.assertIn('if (!V2rayCoreManager.getInstance().promoteForStop(this))', block)
            promoted = block.index('promoteForStop(this)')
            self.assertLess(promoted, block.index('isV2rayCoreRunning()', promoted))

        revoke_start = patch.index('public void onRevoke()')
        revoke_end = patch.index('# 7) Delay probe', revoke_start)
        revoke = patch[revoke_start:revoke_end]
        self.assertIn('finally {', revoke)
        self.assertIn('stopAllProcess();', revoke)

        stop_cleanup = """finally {
                AppConfigs.V2RAY_CONFIG = null;
                stopAllProcess();
            }"""
        self.assertIn(stop_cleanup, patch)

        proxy_destroy_start = patch.index("exact_replace(proxy_svc, '''    @Override\n    public void onDestroy()")
        proxy_destroy_end = patch.index("'P1-29 proxy-only service cleanup helper')", proxy_destroy_start)
        proxy_destroy = patch[proxy_destroy_start:proxy_destroy_end]
        self.assertIn('isV2rayCoreRunning()', proxy_destroy)
        self.assertIn('V2rayCoreManager.getInstance().stopCore();', proxy_destroy)
        self.assertIn('stopForeground(true);', proxy_destroy)
        old_destroy = proxy_destroy.index('public void onDestroy()')
        new_destroy = proxy_destroy.index('public void onDestroy()', old_destroy + 1)
        proxy_on_destroy = proxy_destroy[new_destroy:]
        self.assertLess(proxy_on_destroy.index('stopCore();'), proxy_on_destroy.index('stopForeground(true);'))

    def test_vpn_notification_stop_uses_foreground_pending_intent_on_android_o_plus(self):
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        self.assertIn('PendingIntent.getForegroundService(this, 1, stop, flags)', service)
        self.assertIn('PendingIntent.getService(this, 1, stop, flags)', service)
        self.assertIn('Build.VERSION.SDK_INT >= Build.VERSION_CODES.O', service)
        stop = service[service.index('if (ACTION_STOP.equals(action))'):
                       service.index('if (!ACTION_START.equals(action))')]
        self.assertLess(stop.index('startForegroundSafe('), stop.index('requestStop()'))

    def test_vpn_service_promotes_before_queuing_sticky_restart_or_stop(self):
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = service.index('public int onStartCommand(Intent intent')
        end = service.index('/** Runs a task on the single worker thread', start)
        command = service[start:end]
        restart = command[command.index('if (intent == null)'):command.index('String action = intent.getAction()')]
        stop = command[command.index('if (ACTION_STOP.equals(action))'):command.index('if (!ACTION_START.equals(action))')]
        self.assertLess(restart.index('startForegroundSafe('), restart.index('submit(this::resumeSaved)'))
        self.assertLess(stop.index('startForegroundSafe('), stop.index('submit(this::stopEverything)'))

    def test_vpn_service_refuses_start_when_foreground_promotion_fails(self):
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = service.index('public int onStartCommand(Intent intent')
        end = service.index('/** Runs a task on the single worker thread', start)
        command = service[start:end]
        restart = command[command.index('if (intent == null)'):command.index('String action = intent.getAction()')]
        action_start = command[command.index('if (!ACTION_START.equals(action))'):]

        self.assertIn('private boolean startForegroundSafe(String remark)', service)
        self.assertIn('private boolean updateNotification(String text)', service)
        self.assertIn('return true;', service[service.index('private boolean updateNotification'):])
        self.assertIn('return false;', service[service.index('private boolean updateNotification'):])
        self.assertLess(restart.index('if (!startForegroundSafe('), restart.index('submit(this::resumeSaved)'))
        self.assertIn('requestStop();', restart)
        self.assertIn('submit(this::stopEverything);', restart)
        self.assertLess(action_start.index('if (!startForegroundSafe(first.remark))'),
                        action_start.index('submit(() -> startFlow(first, backups, attempt))'))
        failure = action_start[action_start.index('if (!startForegroundSafe(first.remark))'):
                               action_start.index('final int attempt = activeAttemptId')]
        self.assertIn('emit("FAILED", lastError, activeAttemptId);', failure)
        self.assertIn('return START_NOT_STICKY;', failure)
        self.assertIn('Unable to enter foreground mode', failure)


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


    def test_vpn_watchdog_survives_core_state_query_exceptions(self):
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = service.index('private void checkOnce()')
        end = service.index('private void rescheduleNormal()', start)
        watchdog = service[start:end]
        self.assertIn('try {', watchdog)
        self.assertIn('coreUp = core.isV2rayCoreRunning();', watchdog)
        self.assertIn('catch (Throwable stateError)', watchdog)
        self.assertIn('retaining current tunnel', watchdog)
        self.assertIn('if (active && !stopping) rescheduleNormal();', watchdog)
        self.assertLess(watchdog.index('catch (Throwable stateError)'),
                        watchdog.index('ProbeResult pr = coreUp ? probeResult()'))

    def test_vpn_service_defers_tun_close_until_native_stop_is_verified(self):
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = service.index('private boolean stopCoreNow()')
        end = service.index('/**\n     * Worker-side start of one attempt.', start)
        stop = service[start:end]
        self.assertIn('closeTunAfterCoreStop = true;', stop)
        self.assertGreaterEqual(stop.count('core.isV2rayCoreRunning()'), 3)
        self.assertIn('if (!stillRunning && closeTunAfterCoreStop)', stop)
        self.assertIn('native core remains running; retaining TUN', stop)
        self.assertIn('could not verify native core stop; retaining TUN', stop)
        self.assertIn('could not read core state before stop', stop)
        self.assertIn('could not verify native core stop', stop)
        self.assertLess(stop.index('core.stopCore();'), stop.index('if (!stillRunning && closeTunAfterCoreStop)'))
        self.assertLess(stop.index('if (coreStopping)'), stop.index('final boolean running;'))

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

    def test_ip_auto_background_only_advances_retry_clock_after_complete_scan(self):
        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        start = source.index('Future<bool> _ipAutoRunOnce(')
        end = source.index('Future<void> ipAutoSheet', start)
        scan = source[start:end]
        self.assertIn('if (halted()) return false;', scan)
        self.assertIn('return true;', scan)
        bg_start = source.index('Future<void> ipAutoBackground()')
        bg_end = source.index('/// دلیل رد شدن شروع اسکن', bg_start)
        background = source[bg_start:bg_end]
        completed = background.index('final completed = await _ipAutoRunOnce(')
        timestamp = background.index('await p.setString(_ipAutoAtKey, now.toString());')
        self.assertIn('if (completed && !_ipAutoHalt(modeSnapshot: runNationalMode))', background)
        self.assertLess(completed, timestamp)

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


    def test_custom_vpn_service_is_system_bindable_but_permission_protected(self):
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        start = prepare.index('KSVC = (')
        end = prepare.index("if 'com.kingvpn.king_vpn.KingVpnService'", start)
        service = prepare[start:end]
        self.assertIn('android.permission.BIND_VPN_SERVICE', service)
        self.assertIn('android:exported="true"', service)

    def test_android_manifest_permissions_and_proxy_service_are_independently_idempotent(self):
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        self.assertIn('for permission in required_permissions:', prepare)
        self.assertIn('if f\'android:name="{permission}"\' not in m:', prepare)
        self.assertNotIn("if 'QUERY_ALL_PACKAGES' not in m:", prepare)
        self.assertIn("if proxy_service_name not in m and '</application>' in m:", prepare)
        self.assertIn("if service_match and 'android:foregroundServiceType=' not in service_match.group(0):", prepare)
        self.assertIn(r'r"<service\b(?=[^>]*android:name=', prepare)
        self.assertNotIn(r'\\n    ', prepare)

    def test_signed_release_retries_only_transient_build_failures_and_verifies_signer(self):
        release = (ROOT / '.github' / 'workflows' / 'signed-release.yml').read_text(encoding='utf-8')
        self.assertIn('for attempt in 1 2 3;', release)
        self.assertIn('built=false', release)
        self.assertIn('if [ "$built" != true ]; then', release)
        self.assertIn('SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"', release)
        self.assertIn("Error on ZipFile unknown archive|NDK.*(corrupt|not found)", release)
        self.assertIn('APK_SIGNATURE_REPORT="$("$APKSIGNER" verify --verbose --print-certs "$APK")"', release)
        self.assertIn('KEY_CERT_SHA256="$(keytool -exportcert', release)
        self.assertIn('APK_CERT_SHA256" != "$KEY_CERT_SHA256"', release)
        self.assertIn('does not match the protected production keystore', release)

    def test_signed_release_does_not_persist_checkout_token_into_build_environment(self):
        release = (ROOT / '.github' / 'workflows' / 'signed-release.yml').read_text(encoding='utf-8')
        checkout = release[release.index('uses: actions/checkout@v4'):release.index('- name:', release.index('uses: actions/checkout@v4'))]
        self.assertIn('persist-credentials: false', checkout)
        self.assertIn('GH_TOKEN: ${{ github.token }}', release)
        self.assertNotIn('GH_TOKEN:', checkout)

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
        self.assertIn('maxAddrs: 256', keep)
        self.assertIn('conc: min(2, natAdaptiveWorkers())', keep)
        self.assertNotIn('budget: const Duration(seconds: 90)', keep)
        for condition in ('!mounted', '!connected', '!wantVpn', '!nationalMode',
                          '!localPilotOn', 'appGone', 'abort'):
            self.assertIn(condition, keep)
        self.assertIn('Persist partial results even when the tunnel stops', keep)


    def test_nat_range_scan_preserves_partial_hits_without_committing_incomplete_cursors(self):
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = nat.index('Future<List<String>> _natRangeScanStepBody(')
        end = nat.index('List<String> userListUrls = [];', start)
        body = nat[start:end]
        self.assertIn('final modeSnapshot = nationalMode;', body)
        self.assertIn('bool shouldAbort() =>', body)
        hot = body.index('await natHotNext(800, fetch: false)')
        hot_guard = body.index('if (shouldAbort()) return const <String>[];', hot)
        compute = body.index('await compute(_genAddrsIso, args)')
        compute_guard = body.index('if (shouldAbort()) return const <String>[];', compute)
        scan = body.index('await natScanIps(')
        cancel = body.index('cancelled: shouldAbort,', scan)
        scan_guard = body.index('if (shouldAbort() || scanExpired()) return out;', scan)
        cursor_commit = body.index('cursorStore\n    ..clear()')
        self.assertLess(hot, hot_guard)
        self.assertLess(compute, compute_guard)
        self.assertLess(compute_guard, scan)
        self.assertLess(cancel, scan_guard)
        self.assertLess(scan_guard, cursor_commit)
        self.assertIn('return out;', body[scan:cursor_commit])
        self.assertIn('natNationalTemplateSeeds = seeds.toList(growable: false);', body)
        self.assertIn('natGlobalTemplateSeeds = seeds.toList(growable: false);', body)
        scan_only_start = main.index('Future<void> _natScanOnly()')
        scan_only_end = main.index('// NATFIRSTFAST:', scan_only_start)
        scan_only = main[scan_only_start:scan_only_end]
        self.assertIn('if (nationalMode == runNationalMode) await _natRangeAdd(ips);', scan_only)
        self.assertIn('if (abort || nationalMode != runNationalMode) return;', scan_only)
        self.assertLess(scan_only.index('if (abort || nationalMode != runNationalMode) return;'),
                        scan_only.index('await _natRangeAdd(ips);'))
        escalate_start = main.index('Future<void> _natEscalate(int round)')
        escalate_end = main.index('// CRITICAL for نت ملی: do NOT destroy existing configs.', escalate_start)
        escalate = main[escalate_start:escalate_end]
        self.assertIn('stop: () => abort || modeChanged(),', escalate)
        self.assertIn('if (abort || modeChanged()) return;', escalate)
        self.assertLess(escalate.index('if (abort || modeChanged()) return;', escalate.index('await natRangeScanStep(')),
                        escalate.index('await _natRangeAdd(ips);'))

    def test_connect_loop_cancellation_does_not_penalize_or_accept_server(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = main.index('Future<bool> _connectLoop(')
        end = main.index('// REAL speed test right after connecting', start)
        body = main[start:end]
        verify = body.index('final verifyBudget')
        ping_loop = body.index('for (var i = 0;', verify)
        ping_guard = body.index('if (abort || !wantVpn) {', ping_loop)
        ping_log = body.index('dbg(p == null', ping_loop)
        self.assertLess(ping_guard, ping_log)
        null_branch = body.index('if (p == null) {', ping_loop)
        stop = body.index('await _stopV2();', null_branch)
        stop_guard = body.index('if (abort || !wantVpn) {', stop)
        ladder = body.index('final ladderOk = await _natLadder', null_branch)
        ladder_guard = body.index('if (abort || !wantVpn) {', ladder)
        connected = body.index('_onConnected(s);', ladder)
        self.assertLess(stop, stop_guard)
        self.assertLess(stop_guard, ladder)
        self.assertLess(ladder, ladder_guard)
        self.assertLess(ladder_guard, connected)
        resolve = body.index('final ip1 = await resolveHostIp(s.host);', null_branch)
        resolve_guard = body.index('if (abort || !wantVpn) {', resolve)
        record = body.index('NationalNetworkIntelligence.record(', resolve)
        bad_at = body.index('s.badAt = DateTime.now();', resolve)
        self.assertLess(resolve, resolve_guard)
        self.assertLess(resolve_guard, record)
        self.assertLess(record, bad_at)
        restore = body.index('if (!await _start(s)) {', body.index('if (!sub) {'))
        restore_guard = body.index('if (abort || !wantVpn) {', restore)
        restore_penalty = body.index('siteSkips++;', restore)
        self.assertLess(restore_guard, restore_penalty)

    def test_vpn_service_start_is_compatible_with_pre_oreo_android(self):
        activity = (ROOT / 'android_src' / 'MainActivity.kt').read_text(encoding='utf-8')
        self.assertIn('import androidx.core.content.ContextCompat', activity)
        self.assertIn('ContextCompat.startForegroundService(this, i)', activity)
        self.assertNotIn('startForegroundService(i)', activity)

    def test_generated_android_host_installs_vpn_background_method_channel(self):
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        activity = (ROOT / 'android_src' / 'MainActivity.kt').read_text(encoding='utf-8')
        self.assertIn("shutil.copy('android_src/MainActivity.kt', os.path.join(ka, 'MainActivity.kt'))", prepare)
        self.assertIn('MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vpn/bg")', activity)
        self.assertIn('"vpnSettings" ->', activity)
        self.assertIn('"alive" ->', activity)
        self.assertIn('engineAttached && !isFinishing && !isDestroyed', activity)
        self.assertIn('VPN_SETTINGS_UNAVAILABLE', activity)

    def test_android_ndk_archive_failure_has_bounded_retry_and_cleanup(self):
        workflow = (ROOT / '.github' / 'workflows' / 'build.yml').read_text(encoding='utf-8')
        self.assertIn("grep -Eq 'Error on ZipFile unknown archive|NDK.*(corrupt|not found)'", workflow)
        self.assertIn('rm -rf "$SDK_ROOT/ndk/28.2.13676358" "$SDK_ROOT/.temp"', workflow)
        self.assertIn('for attempt in 1 2 3;', workflow)
        self.assertIn('Transient Android NDK archive failure', workflow)

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
        self.assertIn('final previous = <String, Object?>{', importer)
        self.assertIn('for (final key in attempted.reversed)', importer)
        self.assertIn('rollbackFailures', importer)
        self.assertIn('await _bkpWriteValue(p, entry.key, entry.value)', importer)
        self.assertIn(').whenComplete(restoreC.dispose);', backup)


    def test_dialog_text_controllers_are_reused_and_disposed(self):
        dns = (ROOT / 'lib' / 'dns_scanner.dart').read_text(encoding='utf-8')
        groups = (ROOT / 'lib' / 'sub_groups.dart').read_text(encoding='utf-8')
        iran = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        npv = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        self.assertIn('extraC.dispose();', dns)
        self.assertIn('nameC.dispose();', groups)
        self.assertIn('urlC.dispose();', groups)
        self.assertIn(').whenComplete(c.dispose);', iran)
        self.assertIn('tokenC.dispose();', iran)
        self.assertIn('taskC.dispose();', iran)
        self.assertNotRegex(npv, r'controller:\s*TextEditingController\(text: customDnsAddr\)')
        self.assertIn('controller: customDnsC,', npv)
        self.assertIn('customDnsC.dispose();', npv)
        self.assertIn(').whenComplete(c.dispose);', npv)


    def test_backup_export_enforces_cumulative_budget_during_collection(self):
        backup = (ROOT / 'lib' / 'backup_restore.dart').read_text(encoding='utf-8')
        self.assertIn('void _bkpEnsureExportWithinBudget(', backup)
        exporter_start = backup.index('Future<String> bkpExportJson() async {')
        exporter_end = backup.index('Future<bool> _bkpWriteValue(', exporter_start)
        exporter = backup[exporter_start:exporter_end]
        self.assertIn('final timestamp = DateTime.now().toIso8601String();', exporter)
        self.assertIn('_bkpEnsureExportWithinBudget(encodedEntryBytes);', exporter)
        self.assertLess(exporter.index('_bkpEnsureExportWithinBudget(encodedEntryBytes);'),
                        exporter.index('final encoded = JsonEncoder.withIndent'))
        self.assertIn('const formattingReserve = 32 * 1024;', backup)
        self.assertIn('const envelopeReserve = 512;', backup)
        self.assertIn('encodedEntryBytes += utf8.encode(jsonEncode({k: entry})).length;', exporter)
        self.assertIn('_bkpMaxBytes - formattingReserve - envelopeReserve', backup)

    def test_ai_token_save_does_not_touch_disposed_controller(self):
        iran = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        start = iran.index('Future<void> saveToken() async {')
        end = iran.index('Future<void> createRepair() async {', start)
        save_token = iran[start:end]
        self.assertIn('final token = tokenC.text;', save_token)
        self.assertLess(save_token.index('if (!ctx.mounted) return;'),
                        save_token.index('tokenC.clear();'))


    def test_update_check_retries_when_remote_config_is_not_a_map(self):
        update = (ROOT / 'lib' / 'update_check.dart').read_text(encoding='utf-8')
        start = update.index('final decoded = jsonDecode(response.body);')
        end = update.index('final map = Map<String, dynamic>.from(decoded);', start)
        malformed_config = update[start:end]
        self.assertIn('if (decoded is! Map)', malformed_config)
        self.assertIn('_updateChecked = false;', malformed_config)
        self.assertLess(malformed_config.index('_updateChecked = false;'), malformed_config.index('return;'))

    def test_apk_update_download_has_a_total_deadline_and_idle_timeout(self):
        update = (ROOT / 'lib' / 'update_check.dart').read_text(encoding='utf-8')
        start = update.index('Future<void> _downloadAndInstallApk(')
        end = update.index('Future<void> _continuePendingUpdateInstall()', start)
        download = update[start:end]
        self.assertIn('const totalDownloadBudget = Duration(minutes: 6);', download)
        self.assertIn('final downloadClock = Stopwatch()..start();', download)
        self.assertGreaterEqual(download.count('downloadClock.elapsed >= totalDownloadBudget'), 2)
        self.assertIn('totalDownloadBudget - downloadClock.elapsed', download)
        self.assertIn('client.send(request).timeout(requestTimeout)', download)
        self.assertIn('StreamIterator<List<int>>(streamed.stream)', download)
        self.assertIn('iterator.moveNext().timeout(streamWait)', download)
        self.assertIn('const streamIdleTimeoutCap = Duration(seconds: 45);', download)
        self.assertIn('remainingStreamBudget < streamIdleTimeoutCap', download)
        self.assertIn('await iterator.cancel();', download)
        self.assertLess(download.index('await iterator.cancel();'),
                        download.index('await sink.close();'))
        self.assertIn('client.close();', download)

    def test_apk_update_download_and_install_are_serialized(self):
        update = (ROOT / 'lib' / 'update_check.dart').read_text(encoding='utf-8')
        for guard in (
            'if (_updateDownloadBusy) return;',
            '_updateDownloadBusy = true;',
            '_updateDownloadBusy = false;',
            'if (_updateInstallBusy) return;',
            '_updateInstallBusy = true;',
            '_updateInstallBusy = false;',
        ):
            self.assertIn(guard, update)
        download_start = update.index('Future<void> _downloadAndInstallApk(')
        install_start = update.index('Future<void> _continuePendingUpdateInstall()', download_start)
        positions = [
            update.index('if (_updateDownloadBusy) return;', download_start),
            update.index('_updateDownloadBusy = true;', download_start),
            update.index('_updateDownloadBusy = false;', download_start),
            update.index('if (_updateInstallBusy) return;', install_start),
            update.index('_updateInstallBusy = true;', install_start),
            update.index('_updateInstallBusy = false;', install_start),
        ]
        self.assertEqual(positions, sorted(positions))

    def test_update_check_releases_guard_when_page_is_disposed(self):
        update = (ROOT / 'lib' / 'update_check.dart').read_text(encoding='utf-8')
        start = update.index('Future<void> checkForUpdate()')
        end = update.index('Future<void> _downloadAndInstallApk(', start)
        check = update[start:end]
        self.assertEqual(check.count('if (!mounted) {'), 3)
        response = check.index('final response = await http')
        response_guard = check.index('if (!mounted) {', response)
        remote_heal = check.index('_applyRemoteHeal();')
        self.assertLess(response, response_guard)
        self.assertLess(response_guard, remote_heal)
        for block in check.split('if (!mounted) {')[1:]:
            branch = block.split('}', 1)[0]
            self.assertIn('_updateChecked = false;', branch)
            self.assertIn('return;', branch)

    def test_king_extras2_has_one_complete_declaration_set(self):
        source = (ROOT / 'lib' / 'king_extras2.dart').read_text(encoding='utf-8')
        self.assertIn("import 'dart:io';", source)
        for declaration in (
            'class CheckHostResult',
            'bool _checkHostNodeReached',
            'class KingExtrasPage',
            'Future<CfDeployResult> cloudflareAutoDeploy',
            'class CloudflareAutoDeployPage',
        ):
            self.assertEqual(source.count(declaration), 1, declaration)
        self.assertNotIn(').hasMatch(normalizedHost);\\n    if (normalizedHost.isEmpty', source)


    def test_cloudflare_deploy_guards_state_after_async_token_and_folder_writes(self):
        source = (ROOT / 'lib' / 'king_extras2.dart').read_text(encoding='utf-8')
        deploy_start = source.index('Future<void> _deploy() async {')
        batch_start = source.index('Future<void> _deployBatch() async {', deploy_start)
        copy_start = source.index('Future<void> _copyLink() async {', batch_start)
        deploy = source[deploy_start:batch_start]
        batch = source[batch_start:copy_start]

        for name, method in (('_deploy', deploy), ('_deployBatch', batch)):
            saved = method.index('await _saveToken(token);')
            guard = method.index('if (!mounted) return;', saved)
            state = method.index('setState(() {', guard)
            self.assertLess(saved, guard, name)
            self.assertLess(guard, state, name)

        folder_write = deploy.index('await addToPersonalFolder([r.link]);')
        folder_guard = deploy.index('if (!mounted) return;', folder_write)
        final_state = deploy.index('setState(() => _link = r.link);', folder_write)
        self.assertLess(folder_write, folder_guard)
        self.assertLess(folder_guard, final_state)


    def test_home_page_cancels_background_refresh_and_personal_watch_timers(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        init_start = source.index('void initState() {', source.index('class _HomePageState'))
        init_end = source.index('void dispose() {', init_start)
        init = source[init_start:init_end]
        dispose_start = source.index('void dispose() {', init_end)
        dispose_end = source.index('Future<void> _runBusy(', dispose_start)
        dispose = source[dispose_start:dispose_end]
        self.assertIn('_natHotInitialTimer = Timer(', init)
        self.assertIn('_natHotRefreshTimer = Timer.periodic(', init)
        self.assertIn('if (mounted) unawaited(natHotEnsure());', init)
        self.assertIn('_natHotInitialTimer?.cancel();', dispose)
        self.assertIn('_natHotRefreshTimer?.cancel();', dispose)
        self.assertIn('_personalPingT?.cancel();', dispose)


    def test_king_ai_console_guards_async_controller_access_after_dispose(self):
        source = (ROOT / 'lib' / 'king_ai_console.dart').read_text(encoding='utf-8')
        setup_start = source.index('Future<void> _setupOwnerPassword() async {')
        setup_end = source.index('Future<void> _unlockOwner() async {', setup_start)
        setup = source[setup_start:setup_end]
        self.assertIn('if (mounted) {', setup)
        self.assertLess(setup.index('if (mounted) {'), setup.index('_ownerPasswordController.clear();'))
        change_start = source.index('Future<void> _changeOwnerPassword() async {')
        change_end = source.index('Future<void> _lockOwner() async {', change_start)
        change = source[change_start:change_end]
        self.assertIn('if (mounted) {', change)
        self.assertLess(change.index('if (mounted) {'), change.index('_ownerNewPasswordController.clear();'))
        token_start = source.index('Future<void> _saveToken() async {')
        token_end = source.index('Future<void> _maybeAnalyzeInitialIdea() async {', token_start)
        token = source[token_start:token_end]
        self.assertIn('if (!mounted) return;', token)
        self.assertIn('if (mounted) _tokenController.clear();', token)
        self.assertLess(token.index('if (!mounted) return;', token.index('_reauthenticateOwnerForCodeChange')), token.index('_tokenController.text.trim();'))
        feature_start = source.index('Future<void> _submitFeatureRequest(')
        feature_end = source.index('Future<void> _loadModel() async {', feature_start)
        feature = source[feature_start:feature_end]
        self.assertIn('if (!mounted) return;', feature)
        self.assertIn("result['status'] == 'review_pr_created' && mounted", feature)
        self.assertIn('return valid && mounted;', source)
        analyze_start = source.index('Future<void> _analyzeFeatureRequest() async {')
        analyze_end = source.index('Future<bool> _reauthenticateOwnerForCodeChange()', analyze_start)
        self.assertIn('if (!mounted) return;', source[analyze_start:analyze_end])
        self.assertLess(feature.index('if (!mounted) return;', feature.index('_reauthenticateOwnerForCodeChange')), feature.index('_featureRequestController.text.trim();'))
        self.assertIn('if (!mounted || _initialIdeaAnalysisSubmitted ||', source)
        self.assertIn('if (!mounted || _initialRequestSubmitted ||', source)


    def test_chat_send_stops_after_disposal_before_controller_access(self):
        source = (ROOT / 'lib' / 'king_chat_page.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> _send() async {')
        end = source.index('void _handleSpeechResult', start)
        send = source[start:end]
        self.assertLess(send.index('if (!mounted) return;'),
                        send.index('final prompt = _input.text.trim();'))
        self.assertIn('if (mounted && (_speak || voice))', send)


    def test_chat_send_stops_after_disposal_during_local_inference(self):
        source = (ROOT / 'lib' / 'king_chat_page.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> _send() async {')
        end = source.index('void _handleSpeechResult', start)
        send = source[start:end]
        inference = send.index('final answer = await KingLocalAi.instance.ask(prompt, maxTokens: 1400);')
        disposed_guard = send.index('if (!mounted) return;', inference)
        add_answer = send.index('_add(answer, true);', inference)
        voice_output = send.index('KingVoiceOutput.instance.speakPersian(answer)')
        self.assertLess(inference, disposed_guard)
        self.assertLess(disposed_guard, add_answer)
        self.assertLess(disposed_guard, voice_output)

    def test_delayed_speech_send_is_cancelled_after_chat_disposal(self):
        source = (ROOT / 'lib' / 'king_chat_page.dart').read_text(encoding='utf-8')
        start = source.index('void _handleSpeechResult(dynamic result)')
        end = source.index('Future<void> _startChatSpeech(', start)
        handler = source[start:end]
        self.assertIn('if (mounted) unawaited(_send());', handler)
        self.assertIn('Duration(milliseconds: 250)', handler)


    def test_fresh_resources_refresh_checks_mounted_before_set_state(self):
        source = (ROOT / 'lib' / 'fresh_resources_page.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> _refresh() async {')
        end = source.index('Future<void> _importText()', start)
        refresh = source[start:end]
        self.assertLess(refresh.index('if (!mounted) return;'),
                        refresh.index('setState(() => _busy = true);'))

    def test_fresh_resources_import_stops_after_disposal(self):
        source = (ROOT / 'lib' / 'fresh_resources_page.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> _importText() async {')
        end = source.index('Future<void> _copyAll()', start)
        method = source[start:end]
        merge = method.index('final total = await FreshResourceStore.merge')
        guard = method.index('if (!mounted) return;', merge)
        clear = method.index('_importController.clear();', merge)
        self.assertLess(merge, guard)
        self.assertLess(guard, clear)

    def test_fresh_resources_clear_stops_after_disposal(self):
        source = (ROOT / 'lib' / 'fresh_resources_page.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> _clear() async {')
        end = source.index('Widget build(BuildContext context)', start)
        method = source[start:end]
        accepted = method.index('final accepted = await showDialog<bool>(')
        first_guard = method.index('if (accepted != true || !mounted) return;', accepted)
        clear = method.index('await FreshResourceStore.clear();', first_guard)
        second_guard = method.index('if (!mounted) return;', clear)
        refresh = method.index('await _refresh();', second_guard)
        final_guard = method.index('if (!mounted) return;', refresh)
        self.assertLess(accepted, first_guard)
        self.assertLess(first_guard, clear)
        self.assertLess(clear, second_guard)
        self.assertLess(second_guard, refresh)
        self.assertLess(refresh, final_guard)



    def test_help_page_describes_local_ai_without_obsolete_external_providers(self):
        source = (ROOT / 'lib' / 'help_page.dart').read_text(encoding='utf-8')
        for obsolete in ('Gemini', 'Grok', 'Claude', 'DeepSeek', 'x.ai',
                         'anthropic.com', 'deepseek.com', 'کلید Gemini'):
            self.assertNotIn(obsolete, source)
        self.assertIn('هوش داخلی King AI', source)
        self.assertIn('مدل نصب‌شده روی دستگاه', source)
        self.assertIn('کلید API، اشتراک پولی یا سرویس هوش مصنوعی بیرونی لازم نیست', source)
        self.assertIn('سرورهای دارای دسترسی وب', source)



    def test_personal_server_builder_points_to_local_king_ai(self):
        source = (ROOT / 'lib' / 'king_extras2.dart').read_text(encoding='utf-8')
        self.assertIn('هوش داخلی King AI', source)
        self.assertIn('راهنمای داخل برنامه', source)
        self.assertNotIn('هوش مصنوعی Claude', source)


    def test_v2ray_duration_ticker_starts_only_after_core_connects_and_stops_before_disconnect_broadcast(self):
        patch = (ROOT / 'patch_plugin.py').read_text(encoding='utf-8')
        self.assertIn('P1-36 cancel duration ticker before disconnect broadcast', patch)
        self.assertIn('P1-36 remove late duration ticker cancellation', patch)

        start_patch = patch.index("'P1-27 start failure state and timer reset'")
        connected_patch = patch.index("'P1-34 verify native core running before connected'")
        connected_start = patch.rfind("exact_replace(core, '''            coreController.startLoop(config, tunFd);", 0, connected_patch)
        startup = patch[start_patch:connected_start]
        self.assertNotIn('makeDurationTimer(', startup)
        connected_block = patch[connected_start:connected_patch]
        replacement_start = connected_block.index("''', '''") + len("''', '''")
        connected_replacement = connected_block[replacement_start:]
        self.assertLess(connected_replacement.index('if (!isV2rayCoreRunning())'),
                        connected_replacement.index('V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_CONNECTED;'))
        self.assertLess(connected_replacement.index('V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_CONNECTED;'),
                        connected_replacement.index('makeDurationTimer('))
        self.assertLess(connected_replacement.index('makeDurationTimer('),
                        connected_replacement.index('showNotification(v2rayConfig);'))

        disconnect_start = patch.index("exact_replace(core, '''    private void sendDisconnectedBroadCast() {")
        disconnect_end = patch.index("'P1-36 remove late duration ticker cancellation'", disconnect_start)
        disconnect = patch[disconnect_start:disconnect_end]
        disconnect_replacement_start = disconnect.index("''', '''") + len("''', '''")
        disconnect_replacement = disconnect[disconnect_replacement_start:]
        self.assertLess(disconnect_replacement.index('countDownTimer.cancel();'),
                        disconnect_replacement.index('V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_DISCONNECTED;'))
        self.assertIn('countDownTimer = null;', disconnect_replacement)


    def test_v2ray_duration_timer_callbacks_are_serialized_and_identity_safe(self):
        patch = (ROOT / 'patch_plugin.py').read_text(encoding='utf-8')
        for marker in (
            'P1-37 duration timer lifecycle lock',
            'P1-37 timer creation serialized and state-gated',
            'P1-37 tick verifies timer identity and live connection',
            'P1-37 finish callback is identity-safe and serialized',
            'P1-37 disconnect serializes timer cancellation and state change',
        ):
            self.assertIn(marker, patch)
        self.assertIn('private final Object durationTimerLock = new Object();', patch)
        self.assertIn('countDownTimer != this', patch)
        self.assertIn('V2RAY_STATE != AppConfigs.V2RAY_STATES.V2RAY_CONNECTED', patch)
        self.assertIn('V2RAY_STATE == AppConfigs.V2RAY_STATES.V2RAY_CONNECTED', patch)
        finish_start = patch.index('public void onFinish() {\n                synchronized (durationTimerLock)')
        finish_end = patch.index('\n            }\n        }.start();', finish_start)
        finish = patch[finish_start:finish_end]
        self.assertNotIn('countDownTimer.cancel();', finish)
        self.assertIn('if (countDownTimer != this)', finish)
        self.assertIn('countDownTimer = null;', finish)
        disconnect = patch[patch.index('P1-37 disconnect serializes timer cancellation and state change')-900:
                           patch.index('P1-37 disconnect serializes timer cancellation and state change')]
        self.assertIn('synchronized (durationTimerLock)', disconnect)
        self.assertLess(disconnect.index('countDownTimer.cancel();'),
                        disconnect.index('V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_DISCONNECTED;'))


    def test_v2ray_connection_and_disconnect_broadcast_share_one_lifecycle_lock(self):
        patch = (ROOT / 'patch_plugin.py').read_text(encoding='utf-8')
        self.assertIn('P1-38 keep disconnect lock through broadcast', patch)

        connected_start = patch.index("'P1-34 verify native core running before connected'")
        connected_block_start = patch.rfind("exact_replace(core,", 0, connected_start)
        connected_block = patch[connected_block_start:connected_start]
        connected_replacement_start = connected_block.index("''', '''") + len("''', '''")
        connected_replacement = connected_block[connected_replacement_start:]
        self.assertIn('synchronized (durationTimerLock)', connected_replacement)
        self.assertLess(connected_replacement.index('synchronized (durationTimerLock)'),
                        connected_replacement.index('V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_CONNECTED;'))
        self.assertLess(connected_replacement.index('V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_CONNECTED;'),
                        connected_replacement.index('makeDurationTimer('))

        self.assertIn("        }\n        }\n    }\n\n    private String createNotificationChannelID", patch)


    def test_subscription_sheet_rechecks_context_after_async_work(self):
        groups = (ROOT / 'lib' / 'sub_groups.dart').read_text(encoding='utf-8')
        self.assertIn('if (!mounted || !ctx0.mounted) return;', groups)
        self.assertIn('if (ctx.mounted) setS(() {});', groups)
        self.assertIn('if (!d.mounted) return;', groups)
        self.assertGreaterEqual(groups.count('if (!ctx.mounted) return;'), 3)
        self.assertIn('if (ctx0.mounted) {', groups)
        self.assertIn('await sgrpFetchOne(g);', groups)
        self.assertIn('await sgrpRefreshAll(groups);', groups)

    def test_relay_dialog_checks_dialog_context_after_save(self):
        extras = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        self.assertRegex(
            extras,
            r'await _saveSettings\(\);\s*if \(!mounted \|\| !ctx\.mounted\) return;\s*Navigator\.pop\(ctx\);',
        )

    def test_network_diagnostic_disposes_notifier_and_guards_late_results(self):
        diag = (ROOT / 'lib' / 'net_diag.dart').read_text(encoding='utf-8')
        method = diag[diag.index('Future<void> netDiagDialog()'): ]
        self.assertIn('var dialogOpen = true;', method)
        self.assertIn('if (!mounted) return;\n      var res = t;', method)
        self.assertIn('if (dialogOpen) out.value = res;', method)
        self.assertIn("if (dialogOpen) out.value = 'خطا: $e';", method)
        self.assertRegex(method, r'finally \{\s*dialogOpen = false;\s*out\.dispose\(\);\s*\}')


    def test_subscription_import_stops_if_page_disposed_after_fetch(self):
        source = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> importSubscription(BuildContext ctx, String url) async {')
        end = source.index('void subDialog()', start)
        method = source[start:end]
        fetch = method.index('final list = (await fetchSubscription(url)).take(300).toList();')
        guard = method.index('if (!mounted) return;', fetch)
        mutation = method.index('favs[s.key] = s.link;', fetch)
        self.assertLess(fetch, guard)
        self.assertLess(guard, mutation)

    def test_ai_repair_checks_dialog_after_token_lookup(self):
        source = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> createRepair() async {')
        end = source.index('setS(() => working = true);', start)
        method = source[start:end]
        lookup = method.index('final hasToken = await KingLocalAi.instance.hasGitHubToken();')
        guard = method.index('if (!ctx.mounted) return;', lookup)
        branch = method.index('if (!hasToken)', lookup)
        self.assertLess(lookup, guard)
        self.assertLess(guard, branch)


    def test_initial_feature_request_can_retry_after_reauthentication_cancel(self):
        source = (ROOT / 'lib' / 'king_ai_console.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> _maybeSubmitInitialFeatureRequest() async {')
        end = source.index('Future<void> _submitFeatureRequest(', start)
        method = source[start:end]
        claimed = method.index('_initialRequestSubmitted = true;')
        auth = method.index('if (!await _reauthenticateOwnerForCodeChange()) {', claimed)
        reset = method.index('_initialRequestSubmitted = false;', auth)
        submit = method.index('await _submitFeatureRequest(ownerReauthenticated: true);', auth)
        self.assertLess(claimed, auth)
        self.assertLess(auth, reset)
        self.assertLess(reset, submit)


    def test_dns_manual_scan_does_not_restart_after_sheet_closes_during_load(self):
        source = (ROOT / 'lib' / 'dns_scanner.dart').read_text(encoding='utf-8')
        start = source.index('void dnsxSheet(BuildContext ctx0)')
        end = source.index('\n  }\n}', start)
        method = source[start:end]
        self.assertIn('var sheetOpen = true;', method)
        load = method.index('final saved = await goldDnsList();')
        guard = method.index('if (!mounted || !sheetOpen) return;', load)
        reset = method.index('stopFlag = false;')
        self.assertLess(reset, load)
        self.assertLess(load, guard)
        self.assertNotIn('stopFlag = false;', method[guard:])
        close = method.index('sheetOpen = false;', method.index(').then((_) {'))
        cancel = method.index('stopFlag = true;', close)
        self.assertLess(close, cancel)

    def test_opening_ip_auto_sheet_does_not_clear_active_scan_cancellation(self):
        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        sheet = source.index('Future<void> ipAutoSheet(BuildContext ctx0) async {')
        load = source.index('await ipAutoLoad();', sheet)
        mounted = source.index('if (!ctx0.mounted) return;', load)
        start_scan = source.index('Future<void> start() async {', mounted)
        reset = source.index('ipAutoStopFlag = false;', start_scan)
        self.assertLess(load, mounted)
        self.assertLess(mounted, start_scan)
        self.assertLess(start_scan, reset)
        self.assertNotIn('ipAutoStopFlag = false;', source[load:start_scan])


    def test_closing_ip_auto_sheet_stops_only_its_own_manual_scan(self):
        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> ipAutoSheet(BuildContext ctx0) async {')
        body = source[start:]
        running = body.index('var sheetScanRunning = false;')
        start_scan = body.index('sheetScanRunning = true;')
        reset = body.index('sheetScanRunning = false;', start_scan)
        close = body.index('if (sheetScanRunning) ipAutoStopFlag = true;')
        self.assertLess(running, start_scan)
        self.assertLess(start_scan, reset)
        self.assertLess(reset, close)
        self.assertNotIn('if (!nationalMode) ipAutoStopFlag = true;', body)


    def test_ip_range_expanders_reject_non_positive_limits(self):
        scan = (ROOT / 'lib' / 'nat_ip_scan.dart').read_text(encoding='utf-8')
        ultra = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        self.assertIn('if (maxPerBlock <= 0) return const [];', scan)
        self.assertIn('if (maxCount <= 0) return const [];', scan)
        start = ultra.index('List<String> natExpandAny(')
        self.assertIn('if (maxPerBlock <= 0) return const [];', ultra[start:start + 180])

    def test_auto_tls_probes_bound_handshake_and_always_close_sockets(self):
        source = (ROOT / 'lib' / 'auto_scanners.dart').read_text(encoding='utf-8')
        sni_start = source.index('Future<int?> _autoSniOk(')
        alpn_start = source.index('Future<String?> _autoAlpnOk(', sni_start)
        port_start = source.index('Future<bool> _autoPortOk(', alpn_start)
        sni = source[sni_start:alpn_start]
        alpn = source[alpn_start:port_start]
        for body in (sni, alpn):
            self.assertIn('.timeout(const Duration(seconds: 4))', body)
            self.assertIn('finally', body)
            self.assertIn('secure?.destroy()', body)
            self.assertIn('raw?.destroy()', body)
        tls_start = source.index('final tlsHits = <String>[];')
        tls_end = source.index("await goldAddScans(", tls_start)
        tls = source[tls_start:tls_end]
        ip_loop = tls.index('for (final ip in ips) {')
        stop_check = tls.index('if (cancelled()) break;', ip_loop)
        probe = tls.index('final sel = await _autoAlpnOk', ip_loop)
        self.assertLess(ip_loop, stop_check)
        self.assertLess(stop_check, probe)

    def test_ip_auto_storage_load_and_save_are_mode_isolated_across_awaits(self):
        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        load_start = source.index('Future<void> ipAutoLoad() async {')
        save_start = source.index('Future<void> _ipAutoSave() async {', load_start)
        load = source[load_start:save_start]
        save_end = source.index('/// خودکار فقط IPهای دقیق', save_start)
        save = source[save_start:save_end]
        self.assertLess(load.index('final loadNationalMode = nationalMode;'),
                        load.index('await SharedPreferences.getInstance();'))
        self.assertIn('if (nationalMode != loadNationalMode) return;', load)
        self.assertIn('ipAutoCursors\n      ..clear()\n      ..addAll(loadedCursors);', load)
        self.assertLess(save.index('final saveNationalMode = nationalMode;'),
                        save.index('await SharedPreferences.getInstance();'))
        self.assertIn('final hitsKey = saveNationalMode ? _ipAutoKeyNat : _ipAutoKeyGlob;', save)
        self.assertIn('if (nationalMode != saveNationalMode ||', save)

    def test_ip_auto_background_acquires_shared_locks_before_async_work(self):
        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> ipAutoBackground() async {')
        end = source.index('/// دلیل رد شدن شروع اسکن', start)
        body = source[start:end]
        lock = body.index('ipAutoBusy = true;')
        dns_lock = body.index('dnsxManualBusy = true;', lock)
        first_await = body.index('await ipAutoLoad();')
        prefs = body.index('await SharedPreferences.getInstance();')
        load_guard = body.index('_ipAutoHalt(modeSnapshot: runNationalMode)', first_await)
        prefs_guard = body.index('_ipAutoHalt(modeSnapshot: runNationalMode)', prefs)
        run = body.index('await _ipAutoRunOnce(')
        save = body.index('await _ipAutoSave();')
        unlock = body.index('ipAutoBusy = false;', save)
        self.assertLess(lock, first_await)
        self.assertLess(dns_lock, first_await)
        self.assertLess(first_await, load_guard)
        self.assertLess(load_guard, prefs)
        self.assertLess(prefs, prefs_guard)
        self.assertLess(prefs_guard, run)
        self.assertLess(run, save)
        self.assertLess(save, unlock)
        self.assertIn('if (completed && !_ipAutoHalt(modeSnapshot: runNationalMode))', body)

    def test_ip_auto_address_generation_does_not_commit_after_stop(self):
        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        start = source.index('Future<List<String>> _ipAutoNextAddrs(')
        end = source.index('extension IpAutoExt', start)
        body = source[start:end]
        compute = body.index('await compute(_genAddrsIso, args)')
        abort = body.index('if (nationalMode != modeSnapshot || (shouldAbort?.call() ?? false))')
        cursor_mutation = body.index('ipAutoCursors\n    ..clear()')
        position_mutation = body.index('ipAutoPos = start + slice.length;')
        self.assertLess(compute, abort)
        self.assertLess(abort, cursor_mutation)
        self.assertLess(abort, position_mutation)
        self.assertIn('bool Function()? shouldAbort', body)

    def test_ip_auto_scan_aborts_when_network_mode_changes_mid_run(self):
        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        self.assertIn('(modeSnapshot != null && nationalMode != modeSnapshot)', source)
        start = source.index('Future<bool> _ipAutoRunOnce(')
        end = source.index('Future<void> ipAutoSheet(', start)
        body = source[start:end]
        self.assertIn('final runNationalMode = nationalMode;', body)
        self.assertIn('bool halted() => _ipAutoHalt(modeSnapshot: runNationalMode);', body)
        self.assertIn('shouldAbort: halted,', body)
        self.assertIn('cancelled: halted,', body)
        self.assertIn('if (halted()) return false;', body)
        self.assertIn('final url = runNationalMode ? _natTestUrls.first : delayTestUrl;', body)

    def test_ip_auto_manual_scan_persists_before_releasing_shared_locks(self):
        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> start() async {', source.index('Future<void> ipAutoSheet('))
        end = source.index('\n          }', start) + len('\n          }')
        body = source[start:end]
        save = body.index('await _ipAutoSave();')
        ip_unlock = body.index('ipAutoBusy = false;')
        dns_unlock = body.index('dnsxManualBusy = false;')
        self.assertLess(save, ip_unlock)
        self.assertLess(save, dns_unlock)
        self.assertIn('await ipAutoLoad();', body)
        self.assertIn('_ipAutoHalt(modeSnapshot: runNationalMode)', body)

    def test_nat_ip_scan_uses_monotonic_budget_and_integer_concurrency(self):
        source = (ROOT / 'lib' / 'nat_ip_scan.dart').read_text(encoding='utf-8')
        self.assertIn('(cores * 4).clamp(16, 256).toInt()', source)
        self.assertIn('(cores * 2).clamp(8, 64).toInt()', source)
        self.assertIn('port < 1 || port > 65535', source)
        self.assertIn('final elapsed = Stopwatch()..start();', source)
        self.assertIn('if (budget != null && elapsed.elapsed >= budget) return;', source)
        self.assertNotIn('DateTime.now().add(budget)', source)

    def test_nat_ip_scan_discards_in_flight_results_after_cancellation(self):
        source = (ROOT / 'lib' / 'nat_ip_scan.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> worker() async {')
        end = source.index('\n  }', start)
        worker = source[start:end]
        probe = worker.index('final ms = await natTcpProbe(ip, port, timeout);')
        stale_guard = worker.index('if (aborted() || (budget != null && elapsed.elapsed >= budget))', probe)
        insert = worker.index('if (ms != null && (want == null || hits.length < want))', stale_guard)
        self.assertLess(probe, stale_guard)
        self.assertLess(stale_guard, insert)
        self.assertIn('return;', worker[stale_guard:insert])

    def test_tunnel_ping_respects_one_remaining_budget_and_cancellation(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        ping_start = main.index('Future<int?> pingProxy(')
        ping_end = main.index('Future<int?> pingAny(', ping_start)
        ping = main[ping_start:ping_end]
        self.assertIn('final sw = Stopwatch()..start();', ping)
        self.assertIn('return remaining.isNegative ? Duration.zero : remaining;', ping)
        self.assertLess(ping.index('try {'), ping.index('var useProxy = await _useCoreProxy('))
        self.assertIn('budget: left(),', ping)
        self.assertIn('cancelled: cancelled,', ping)
        self.assertIn('requestClient.getUrl(Uri.parse(url)).timeout(left())', ping)
        self.assertIn('client?.close(force: true);', ping)
        self.assertNotIn('const Duration(milliseconds: 200)', ping)
        any_start = ping_end
        any_end = main.index('Future<bool> internetEndpointsOpen(', any_start)
        any_ping = main[any_start:any_end]
        self.assertIn('bool Function()? cancelled', any_ping)
        self.assertGreaterEqual(any_ping.count('cancelled?.call() ?? false'), 2)
        connect_start = main.index('Future<bool> _connectLoop(')
        connect_end = main.index('Future<bool> ', connect_start + 20)
        connect = main[connect_start:connect_end]
        self.assertIn('final verifyClock = Stopwatch()..start();', connect)
        self.assertIn('Duration verifyRemaining() => verifyBudget - verifyClock.elapsed;', connect)
        self.assertIn('microseconds: max(1, remaining.inMicroseconds ~/ 2).toInt()', connect)
        self.assertIn('cancelled: () => abort || !wantVpn,', connect)
        self.assertIn('bool Function()? cancelled', ping)
        self.assertIn('Timer.periodic(const Duration(milliseconds: 100)', ping)
        self.assertIn('requestClient.close(force: true);', ping)
        self.assertIn('budget: left(),', ping)
        self.assertIn('final probeBudget = budget < const Duration(milliseconds: 150)', main)
        self.assertIn('return _coreProxyOpen(timeout: probeBudget);', main)
        self.assertIn('cancelled: cancelled,', ping)
        self.assertNotIn('DateTime.now().isBefore(verifyDeadline)', connect)
        self.assertNotIn('pingSec', connect)

    def test_nat_range_scan_uses_one_monotonic_budget_across_ports(self):
        source = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        start = source.index('Future<List<String>> _natRangeScanStepBody(')
        end = source.index('List<String> userListUrls', start)
        body = source[start:end]
        self.assertIn('final scanClock = Stopwatch()..start();', body)
        self.assertIn('bool scanExpired() => budget != null && scanClock.elapsed >= budget;', body)
        self.assertIn('budget == null ? null : budget - scanClock.elapsed', body)
        scan = body.index('final hits = await natScanIps(')
        self.assertIn('budget: remainingBudget,', body[scan:scan + 500])
        expiry = body.index('if (shouldAbort() || scanExpired()) return out;', scan)
        cursor = body.index('cursorStore\n    ..clear()')
        self.assertLess(scan, expiry)
        self.assertLess(expiry, cursor)
        self.assertNotIn('DateTime.now().add(budget)', body)

    def test_dns_wire_probe_cancellation_closes_pending_udp_work(self):
        core = (ROOT / 'lib' / 'nnie_core.dart').read_text(encoding='utf-8')
        start = core.index('static Future<NatDnsProbeResult> probe(')
        end = core.index('\n  }\n}', start)
        probe = core[start:end]
        self.assertIn('bool Function()? cancelled', probe)
        self.assertIn('Timer.periodic(const Duration(milliseconds: 100)', probe)
        self.assertIn('completer.completeError(const _NatDnsProbeCancelled())', probe)
        self.assertIn('await subscription?.cancel();', probe)
        self.assertIn('finally {\n        socket?.close();', probe)
        dns = (ROOT / 'lib' / 'dns_scanner.dart').read_text(encoding='utf-8')
        self.assertIn('cancelled: stop,', dns)
        self.assertIn('if (stop != null && stop()) return null;', dns)

    def test_nat_domain_first_scans_the_full_configured_endpoint_inventory(self):
        source = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        start = source.index('Future<List<String>> _natDomainFirst(')
        end = source.index('Future<List<String>> natDeviceHosts()', start)
        body = source[start:end]
        self.assertNotIn('scanBudget', body)
        self.assertNotIn('known.take(1200)', body)
        self.assertIn('for (final server in known)', body)
        self.assertIn('for (final address in addresses)', body)
        self.assertIn('await safeLookup(entry.key)', body)
        self.assertIn('final hits = await natScanIps(', body)
        self.assertIn('cancelled: cancelled,', body)
        self.assertNotIn('want: 50', body)
        self.assertNotIn('Duration(seconds: 5)', body)
        self.assertNotIn('address.type != InternetAddressType.IPv4', body)
        self.assertIn('return out;', body)

    def test_nat_ip_scan_only_applies_explicit_hit_and_time_limits(self):
        source = (ROOT / 'lib' / 'nat_ip_scan.dart').read_text(encoding='utf-8')
        start = source.index('Future<List<NatIpHit>> natScanIps(')
        body = source[start:]
        self.assertIn('if (ips.isEmpty || (want != null && want <= 0))', body)
        self.assertIn('if (want != null && hits.length >= want)', body)
        self.assertIn('if (budget != null && elapsed.elapsed >= budget)', body)
        self.assertIn('if (ms != null && (want == null || hits.length < want))', body)

    def test_auto_sni_scan_uses_shared_scanner_lock(self):
        source = (ROOT / 'lib' / 'auto_scanners.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> autoScanRun(')
        end = source.index('Future<void> autoScanSheet(', start)
        body = source[start:end]
        self.assertIn('dnsxManualBusy || _dnsxAutoBusy || ipAutoBusy || _natRangeScanBusy', body)
        self.assertIn('dnsxManualBusy = true;', body)
        self.assertIn('dnsxManualBusy = false;', body)
        self.assertLess(body.index('dnsxManualBusy = true;'), body.index('await goldLoad();'))
        self.assertLess(body.index('_autoScanRunning = false;'), body.index('dnsxManualBusy = false;'))

    def test_auto_sni_scan_uses_complete_inventory_without_fixed_deadline(self):
        source = (ROOT / 'lib' / 'auto_scanners.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> autoScanRun(')
        end = source.index('Future<void> autoScanSheet(', start)
        body = source[start:end]
        self.assertNotIn('scanBudget', body)
        self.assertNotIn('timedOut()', body)
        self.assertIn('for (final entry in _goldIps.values)', body)
        self.assertIn('...kAutoSniDomains', body)
        self.assertIn('...natFrontSnis', body)
        self.assertIn('for (final p in ports)', body)
        self.assertIn('shouldAbort: () => cancelled(),', body)
        self.assertNotIn('kAutoIpLimit', body)
        self.assertNotIn('kAutoFallbackIps', body)

    def test_sni_probes_reject_ip_literals_and_invalid_certificates(self):
        nip = (ROOT / 'lib' / 'nip_scan.dart').read_text(encoding='utf-8')
        auto = (ROOT / 'lib' / 'auto_scanners.dart').read_text(encoding='utf-8')
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        extras = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        diagnostics = (ROOT / 'lib' / 'net_diag.dart').read_text(encoding='utf-8')
        for source in (nip, auto, main, extras, diagnostics):
            self.assertNotIn('onBadCertificate: (_) => true', source)
        self.assertIn('InternetAddress.tryParse(sni.trim()) != null', nip)
        self.assertIn('InternetAddress.tryParse(value.trim()) == null', nip)
        self.assertIn('final List<String> natFrontSnis', nip)
        self.assertIn('...kAutoSniDomains', nip)

    def test_ip_grafting_preserves_host_and_the_actual_scanned_port(self):
        nip = (ROOT / 'lib' / 'nip_scan.dart').read_text(encoding='utf-8')
        self.assertIn('String? nipSwapLink(Server t, String ip, {int? port})', nip)
        self.assertIn("j['port'] = port.toString();", nip)
        self.assertIn('u.replace(host: ip, port: port ??', nip)
        self.assertIn('String? nipSwapSni(Server t, String ip, String sni, {int? port})', nip)
        self.assertIn('!t.tls || t.reality', nip)
        self.assertIn('|| server.reality', nip)

    def test_fragmentation_reaches_the_real_core_config_and_survives_sanitization(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        extras = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        self.assertIn('final base = natCfg(s, nv, reuse: true)', main)
        self.assertIn('sanitizeCfg(withIranRouting(withNpvAmCore(c)))', main)
        self.assertIn("if (dp != null && !tags.contains(dp))", main)
        self.assertIn("sockopt['dialerProxy'] = 'frag-out';", extras)
        self.assertIn("outs.removeWhere((entry) => entry is Map && entry['tag'] == 'frag-out')", extras)
        self.assertIn("'tag': 'frag-out'", extras)
        self.assertIn('for (final outbound in fragmentTargets)', extras)
        self.assertIn('_stripKingFragmentOutbound(cfg)', extras)
        self.assertIn("'packets': 'tlshello'", extras)

    def test_dns_policy_preserves_imported_resolvers_and_validates_dns_answers(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        dns = (ROOT / 'lib' / 'nnie_core.dart').read_text(encoding='utf-8')
        self.assertIn('final existingList = existing is List ? existing : const <dynamic>[];', main)
        self.assertIn('for (final item in [...existingList, ...globalDefaults])', main)
        self.assertIn("d['servers'] = merged;", main)
        self.assertIn('_probeDoh(query, expectedDomain:', nat)
        self.assertIn("qname != domain.toLowerCase()", dns)
        self.assertIn('allowedOwners.contains(rr.owner)', dns)

    def test_dns_scanner_uses_all_project_domains_and_saved_resolvers(self):
        dns = (ROOT / 'lib' / 'dns_scanner.dart').read_text(encoding='utf-8')
        self.assertIn('List<String> dnsxAutoDomains() => dnsxFullDomains();', dns)
        self.assertIn('...savedDns, ...(scanNationalMode ? kDnsxNationalDefaults : kDnsxDefaults)', dns)
        self.assertIn('final best = [for (final e in r) e.ip];', dns)
        self.assertNotIn('savedDns.take(40)', dns)
        self.assertNotIn('r.take(4)', dns)
        self.assertIn('...kDnsxGlobalDomains', dns)
        self.assertIn('...natIrDomains', dns)

    def test_nip_scan_has_no_implicit_hit_or_time_ceiling_and_resolves_all_addresses(self):
        nip = (ROOT / 'lib' / 'nip_scan.dart').read_text(encoding='utf-8')
        start = nip.index('Future<List<NipHit>> nipScan(')
        end = nip.index('/// فهرست بلوک‌های IPv4 ایران', start)
        scan = nip[start:end]
        self.assertIn('int? want,', scan)
        self.assertIn('Duration? budget,', scan)
        self.assertNotIn('Duration(minutes: 2)', scan)
        self.assertIn('if (budget != null && elapsed.elapsed >= budget)', scan)
        self.assertIn('if (cancelled != null && cancelled())', scan)
        resolver_start = nip.index('Future<List<String>> nipResolveAll(')
        resolver_end = nip.index('/// بلوک‌های هاست یک IP', resolver_start)
        resolver = nip[resolver_start:resolver_end]
        self.assertIn('InternetAddress.lookup(host)', resolver)
        self.assertIn('out.addAll(addresses.map', resolver)

    def test_full_ip_inventory_is_not_truncated_in_the_server_pipeline(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        ip_start = main.index('if (ipMode && !abort)')
        ip_end = main.index('return alive;', ip_start)
        self.assertNotIn('.take(40)', main[ip_start:ip_end])
        saved_start = main.index('Future<void> _checkSaved()')
        saved_end = main.index('Future<void> _natMemoryReuse()', saved_start)
        self.assertNotIn('take(80)', main[saved_start:saved_end])
        memory_start = saved_end
        memory_end = main.index('Future<void> _natRangeAdd(', memory_start)
        self.assertNotIn('take(40)', main[memory_start:memory_end])
        range_start = memory_end
        range_end = main.index('void _userListsDialog(', range_start)
        range_add = main[range_start:range_end]
        self.assertNotIn('.take(2)', range_add)
        self.assertNotIn('pending.length > 3000', range_add)
        self.assertIn('natRangeTemplateCursor', range_add)
        self.assertIn('for (final server in [...pending, ...natRestPending, ...natCurrentTemplateSeeds(), ...good])', range_add)
        self.assertNotIn('maxPerSource', main)

    def test_search_does_not_stop_after_a_fixed_batch_count(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertNotIn('maxBatches', main)
        self.assertNotIn('standbyBatches', main)
        self.assertNotIn('batches < maxB', main)
        self.assertIn('while (!abort &&', main)
        self.assertIn('quick source mode: parsing the complete returned list', main)
        self.assertIn('for (final l in lines)', main)

    def test_ip_and_domain_memory_is_file_backed_without_count_or_age_expiry(self):
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        self.assertIn('king_vpn_ip_inventory.jsonl', nat)
        self.assertIn('king_vpn_domain_inventory.jsonl', nat)
        self.assertIn('FileMode.append', nat)
        self.assertIn('_natReadInventory', nat)
        self.assertNotIn('_ipMemMax', nat)
        self.assertNotIn('_domMemMax', nat)
        self.assertNotIn('Duration(days: 14)', nat)

    def test_range_scan_has_no_hidden_port_or_address_hit_quota(self):
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        self.assertNotIn('natRanges.take(128)', nat)
        self.assertNotIn('known.take(100)', nat)
        self.assertNotIn('ports.take(10)', nat)
        self.assertNotIn('want: 50', nat)
        self.assertIn('addressBatchSize', nat)
        self.assertIn('min(256, remaining)', nat)
        self.assertIn('_natNationalRangeCursors', nat)
        self.assertIn('if (modeSnapshot) ...natRanges', nat)
        self.assertIn('Duration? budget,', nat)
        self.assertIn('final slice = (generated[\'addrs\'] as List).cast<String>();', nat)
        self.assertIn('BigInt _natIPv6ToBigInt', nat)
        self.assertIn('_natExpandIPv6Span', nat)
        self.assertIn('prefix < 32 || prefix > 128', nat)
        self.assertIn('Map<String, String> _natNationalRangeCursors', nat)

    def test_hot_source_inventory_is_disk_streamed_without_entry_ceilings(self):
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        self.assertNotIn('natHotPerSource', nat)
        self.assertNotIn('natHotMax', nat)
        self.assertNotIn('natHotFetchDeadline', nat)
        self.assertIn('final int lineCount;', nat)
        self.assertIn('final int byteLength;', nat)
        self.assertIn('file.openRead(offset)', nat)
        self.assertIn('_hotCursorOffset = offset;', nat)
        self.assertIn('await for (final _ in file', nat)

    def test_gold_inventory_is_file_backed_complete_and_keeps_historical_records(self):
        gold = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        self.assertIn('king_vpn_gold_inventory.json', gold)
        self.assertIn('await temp.writeAsString(_goldEncode(), flush: true)', gold)
        self.assertNotIn('kGoldIpCap', gold)
        self.assertNotIn('kGoldSrvCap', gold)
        self.assertNotIn('_goldTrimIps', gold)
        self.assertNotIn('_goldTrimSrv', gold)
        self.assertNotIn('cleanIps.take(10)', gold)
        self.assertNotIn('srvL.take(200)', gold)
        self.assertNotIn('ipL.take(200)', gold)
        self.assertNotIn('dnsL.take(200)', gold)
        self.assertNotIn('want: 1000', gold)
        self.assertNotIn('budget: Duration(minutes: userAddrs.length', gold)
        self.assertNotIn('timeout(const Duration(minutes: 2)', gold)
        self.assertIn('v.testAt = nowMs;', gold)
        self.assertIn('await _goldWrite();', gold)

    def test_global_and_national_ip_domain_and_template_inventories_are_isolated(self):
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        nip = (ROOT / 'lib' / 'nip_scan.dart').read_text(encoding='utf-8')
        self.assertIn('king_vpn_national_ip_inventory.jsonl', nat)
        self.assertIn('king_vpn_national_domain_inventory.jsonl', nat)
        self.assertIn('natGlobalTemplateSeeds', nat)
        self.assertIn('natNationalTemplateSeeds', nat)
        self.assertIn('_natNationalRangeCursors', nat)
        self.assertIn('_cfRangeCursors', nat)
        self.assertIn('if (modeSnapshot) ...natNationalIpMemHosts() else ...natIpMemHosts()', nat)
        self.assertIn('if (modeSnapshot) ...natRanges', nat)
        reuse_start = main.index('Future<void> _natMemoryReuse()')
        reuse_end = main.index('Future<void> _natRangeAdd(', reuse_start)
        reuse = main[reuse_start:reuse_end]
        self.assertIn('natNationalIpMem', reuse)
        self.assertNotIn('natIpMem', reuse)
        self.assertNotIn('natHotNext', reuse)
        hunt_start = nip.index('Future<bool> _natIpHunt()')
        hunt_end = nip.index('Future<bool> _natTryScan(', hunt_start)
        hunt = nip[hunt_start:hunt_end]
        self.assertIn('natNationalIpMemHosts()', hunt)
        self.assertNotIn('_goldIps', hunt)
        self.assertNotIn('goldLoad()', hunt)
        self.assertIn('natNationalDomMem', nat)

    def test_fragmentation_is_not_silently_disabled_and_targets_all_tls_outbounds(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        extras = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        self.assertEqual(main.count('fragEnabled = false;'), 1)
        self.assertIn("sockopt['dialerProxy'] = 'frag-out';", extras)
        self.assertIn("'packets': 'tlshello'", extras)
        self.assertIn('_stripKingFragmentOutbound(cfg)', extras)
        self.assertIn('for (final outbound in fragmentTargets)', extras)
        self.assertIn("outs.removeWhere((entry) => entry is Map && entry['tag'] == 'frag-out')", extras)

    def test_clean_ip_probe_requires_verified_cloudflare_tls_and_keeps_full_results(self):
        source = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        probe_start = source.index('Future<int?> _cfProbeMs(')
        probe_end = source.index('final ValueNotifier<int> cleanTick', probe_start)
        probe = source[probe_start:probe_end]
        self.assertIn('Socket.connect(ip, 443', probe)
        self.assertIn('SecureSocket.secure(', probe)
        self.assertIn('host: \'cloudflare.com\'', probe)
        self.assertIn('isValidCloudflareTraceResponse(response)', probe)
        self.assertNotIn('Socket.connect(ip, 80', probe)
        clean_start = source.index('Future<void> _doRefreshClean()')
        clean_end = source.index('Future<String?> pickCleanIp()', clean_start)
        clean = source[clean_start:clean_end]
        self.assertNotIn('res.length >= 20', clean)
        self.assertNotIn('res.take(20)', clean)
        self.assertNotIn('take(240)', clean)
        self.assertNotIn('Duration(seconds: 40)', clean)
        picker_start = source.index('Future<String?> pickCleanIp()')
        picker_end = source.index('const _iranMoreDomains', picker_start)
        picker = source[picker_start:picker_end]
        self.assertIn('natNationalIpMemLoad()', picker)
        self.assertNotIn('goldIpList()', picker)
        self.assertNotIn('cleanIps', picker[:picker.index('if (!_cleanLoaded')])

    def test_matrix_order_is_not_truncated_by_the_old_5000_variant_ceiling(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        self.assertNotIn('natMaxVariants', main)
        self.assertNotIn('natMaxVariants', nat)
        self.assertIn('_natOrder(s, full: _resFull).where((v) => v != 0)', main)

    def test_auto_sni_scan_aborts_when_network_mode_changes_mid_run(self):
        source = (ROOT / 'lib' / 'auto_scanners.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> autoScanRun(')
        end = source.index('Future<void> autoScanSheet(', start)
        body = source[start:end]
        snapshot = body.index('final scanNationalMode = nationalMode;')
        first_await = body.index('await goldLoad();')
        self.assertLess(snapshot, first_await)
        self.assertIn('bool cancelled() =>', body)
        self.assertIn('_autoScanStop || vpnActive() || vpnWanted() || nationalMode != scanNationalMode;', body)
        self.assertIn('await goldAddScans(', body)
        self.assertIn('shouldAbort: () => cancelled(),', body)
        self.assertNotIn('if (_autoScanStop)', body)

    def test_auto_sni_sheet_forwards_live_vpn_state(self):
        source = (ROOT / 'lib' / 'auto_scanners.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> autoScanSheet(')
        body = source[start:]
        self.assertIn('isVpnActive: isVpnActive, isVpnWanted: isVpnWanted', body)

    def test_auto_sni_scan_aborts_if_vpn_connects_mid_run(self):
        source = (ROOT / 'lib' / 'auto_scanners.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> autoScanRun(')
        end = source.index('Future<void> autoScanSheet(', start)
        body = source[start:end]
        self.assertIn('_autoScanStop || vpnActive() || vpnWanted() || nationalMode != scanNationalMode;', body)
        self.assertIn('با شروع اتصال VPN، اسکن برای جلوگیری از تداخل متوقف شد', body)
        self.assertIn('shouldAbort: () => cancelled(),', body)

    def test_dns_auto_scan_keeps_network_mode_snapshot_across_awaits(self):
        source = (ROOT / 'lib' / 'dns_scanner.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> dnsxAutoPick(')
        end = source.index('extension DnsxExt', start)
        body = source[start:end]
        snapshot = body.index('final scanNationalMode = nationalMode;')
        prefs = body.index('await SharedPreferences.getInstance();')
        first_guard = body.index('if (nationalMode != scanNationalMode) return;')
        saved_dns = body.index('final savedDns = await goldDnsList();')
        second_guard = body.index('if (nationalMode != scanNationalMode) return;', first_guard + 1)
        scan = body.index('final r = await dnsxScan(', saved_dns)
        self.assertLess(snapshot, prefs)
        self.assertLess(prefs, first_guard)
        self.assertLess(saved_dns, second_guard)
        self.assertLess(second_guard, scan)
        self.assertIn('stop: () => nationalMode != scanNationalMode', body)
        self.assertIn("await p.setStringList('dnsx_best_v1_$sfx', best);", body)
        self.assertIn('if (!shouldAbort())', body)
        self.assertNotIn("nationalMode ? 'nat' : 'glob'", body)


    def test_ip_auto_address_generation_does_not_apply_stale_mode_cursors(self):
        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        start = source.index('Future<List<String>> _ipAutoNextAddrs(')
        end = source.index('extension IpAutoExt', start)
        body = source[start:end]
        mode = body.index('final modeSnapshot = nationalMode;')
        position = body.index('final startPosSnapshot = ipAutoPos;')
        cursors = body.index('final cursorSnapshot = Map<String, int>.of(ipAutoCursors);')
        compute = body.index('await compute(_genAddrsIso, args)')
        guard = body.index('if (nationalMode != modeSnapshot || (shouldAbort?.call() ?? false))')
        mutation = body.index('ipAutoCursors\n    ..clear()')
        generated = body.index("final generatedCursors = Map<String, int>.from(gen['cursors'] as Map);")
        update_pos = body.index('ipAutoPos = start + slice.length;')
        self.assertLess(mode, compute)
        self.assertLess(position, compute)
        self.assertLess(cursors, compute)
        self.assertLess(compute, guard)
        self.assertLess(guard, generated)
        self.assertLess(generated, mutation)
        self.assertIn("'nationalMode': modeSnapshot", body)
        self.assertIn('final start = startPosSnapshot % all.length;', body)
        self.assertLess(mutation, update_pos)



    def test_auto_scan_dialog_close_requests_cancellation(self):
        auto = (ROOT / 'lib' / 'auto_scanners.dart').read_text(encoding='utf-8')
        start = auto.index('Future<void> autoScanSheet(')
        body = auto[start:]
        close = body.index('await showDialog<void>(')
        cancel = body.index('_autoScanStop = true;', close)
        closed = body.index('open = false;', cancel)
        self.assertLess(close, cancel)
        self.assertLess(cancel, closed)

    def test_manual_dns_sheet_acquires_scan_lock_before_async_load(self):
        dns = (ROOT / 'lib' / 'dns_scanner.dart').read_text(encoding='utf-8')
        start = dns.index('Future<void> start() async {', dns.index('extension DnsxExt'))
        end = dns.index('          return SafeArea(', start)
        body = dns[start:end]
        guard = body.index('if (running || dnsxManualBusy || _dnsxAutoBusy)')
        lock = body.index('dnsxManualBusy = true;', guard)
        await_load = body.index('await goldDnsList();', lock)
        scan = body.index('r = await dnsxScan(', await_load)
        unlock = body.index('dnsxManualBusy = false;', scan)
        self.assertLess(guard, lock)
        self.assertLess(lock, await_load)
        self.assertLess(await_load, scan)
        self.assertLess(scan, unlock)
        self.assertIn('stop: () => stopFlag || !sheetOpen,', body)

    def test_dns_probe_checks_cancellation_after_inter_batch_delay(self):
        dns = (ROOT / 'lib' / 'dns_scanner.dart').read_text(encoding='utf-8')
        start = dns.index('Future<DnsxHit?> dnsxProbe(')
        end = dns.index('Future<List<DnsxHit>> dnsxScan(', start)
        body = dns[start:end]
        delay = body.index('await Future.delayed(gap);')
        stop = body.index('if (stop != null && stop()) break;', delay)
        batch = body.index('final part = list.sublist(', stop)
        self.assertLess(delay, stop)
        self.assertLess(stop, batch)

    def test_dns_auto_persistence_waits_for_abort_safe_folder_write(self):
        dns = (ROOT / 'lib' / 'dns_scanner.dart').read_text(encoding='utf-8')
        start = dns.index('Future<void> dnsxAutoPick(')
        end = dns.index('extension DnsxExt', start)
        body = dns[start:end]
        abort = body.index('bool shouldAbort()')
        folder_save = body.index('if (r.isNotEmpty) {')
        saved = body.index('final saved = await goldAddDns(r, shouldAbort: shouldAbort);', folder_save)
        saved_guard = body.index('if (!saved || shouldAbort()) return;', saved)
        best = body.index("await p.setStringList('dnsx_best_v1_$sfx', best);")
        mode_guard = body.index('if (shouldAbort()) return;', best)
        last = body.index("await p.setInt('dnsx_at_v1_$sfx', now);", mode_guard)
        self.assertLess(abort, folder_save)
        self.assertLess(folder_save, saved)
        self.assertLess(saved, saved_guard)
        self.assertLess(saved_guard, best)
        self.assertLess(best, mode_guard)
        self.assertLess(mode_guard, last)

    def test_auto_scan_stop_never_persists_partial_results(self):
        auto = (ROOT / 'lib' / 'auto_scanners.dart').read_text(encoding='utf-8')
        extras = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        start = auto.index('Future<void> autoScanRun(')
        end = auto.index('Future<void> autoScanSheet(', start)
        body = auto[start:end]
        self.assertGreaterEqual(body.count("if (cancelled()) {"), 4)
        self.assertIn('say(cancellationMessage());', body)
        self.assertIn("final saved = await goldAddScans(", body)
        self.assertIn("shouldAbort: () => cancelled(),", body)
        self.assertIn("if (!saved)", body)
        self.assertNotIn("await goldAddScan('tls', tlsHits);", body)
        helper_start = extras.index('Future<bool> goldAddScans(')
        helper_end = extras.index('Future<void> goldAddScan(', helper_start)
        helper = extras[helper_start:helper_end]
        load = helper.index('await goldLoad();')
        abort = helper.index('if (shouldAbort?.call() ?? false) return false;', load)
        mutation = helper.index('for (final entry in updates.entries)')
        write = helper.index('await _goldWrite();')
        self.assertLess(load, abort)
        self.assertLess(abort, mutation)
        self.assertLess(mutation, write)
        self.assertIn('return true;', helper)
        self.assertIn('return false;', helper[helper.index('catch (e, stk)'):])

    def test_gold_write_serializes_atomic_file_snapshots_without_entry_caps(self):
        extras = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        start = extras.index('String _goldEncode()')
        end = extras.index('String goldInfo()', start)
        persistence = extras[start:end]
        self.assertIn('Future<void> _goldWrite()', persistence)
        self.assertIn('await temp.writeAsString(_goldEncode(), flush: true)', persistence)
        self.assertIn('await file.rename(backup.path)', persistence)
        self.assertIn('await temp.rename(file.path)', persistence)
        save = persistence[persistence.index('Future<void> goldSave()'):]
        self.assertIn('await _goldWrite();', save)
        self.assertNotIn("p.setString('gold_v1'", persistence)


    def test_national_yield_wait_is_cancellable_for_manual_scans(self):
        extras = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        auto = (ROOT / 'lib' / 'auto_scanners.dart').read_text(encoding='utf-8')
        dns = (ROOT / 'lib' / 'dns_scanner.dart').read_text(encoding='utf-8')
        start = extras.index('Future<void> natManualYield(')
        end = extras.index('// FOLDERALL:', start)
        yield_body = extras[start:end]
        self.assertIn('bool Function()? shouldAbort', yield_body)
        self.assertIn('!(shouldAbort?.call() ?? false)', yield_body)
        self.assertEqual(auto.count('natManualYield(shouldAbort: () => cancelled())'), 2)
        self.assertIn('if (cancelled()) break sniLoop;', auto)
        self.assertIn('if (cancelled()) break portLoop;', auto)
        self.assertIn('await natManualYield(shouldAbort: stop);', dns)
        self.assertIn('if (stop != null && stop()) break;', dns)


    def test_manual_range_scan_honors_cancel_during_national_yield(self):
        source = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> manualRangeScan(')
        end = source.index('\n}', start)
        body = source[start:end]
        wait = body.index('await natManualYield(shouldAbort: () => cancelled || !open);')
        before_scan = body.index('if (!cancelled) {', wait)
        scan = body.index('result = await natScanIps(', before_scan)
        after_scan = body.index('if (!cancelled && open && nationalMode == scanNationalMode)', scan)
        national_persist = body.index('await natNationalIpMemSave(', after_scan)
        global_persist = body.index('await goldMergeIps(', after_scan)
        self.assertLess(wait, before_scan)
        self.assertLess(before_scan, scan)
        self.assertLess(scan, after_scan)
        self.assertLess(after_scan, national_persist)
        self.assertLess(after_scan, global_persist)
        self.assertIn('cancelled: () => cancelled || !open,', body)


    def test_manual_range_scan_close_cancels_scan_and_blocks_late_persistence(self):
        source = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> manualRangeScan(')
        end = source.index('\n}', start)
        body = source[start:end]
        close = body.index('cancelled = true;', body.index("child: const Text('کپی IPها')"))
        close_pop = body.index('Navigator.pop(ctx);', close)
        completion = body.index('open = false;', body.index(').then((_) {'))
        completion_cancel = body.index('cancelled = true;', completion)
        scan = body.index('result = await natScanIps(')
        stop = body.index('cancelled: () => cancelled || !open,', scan)
        persist_guard = body.index('if (!cancelled && open && nationalMode == scanNationalMode)', scan)
        persist = body.index('await goldMergeIps(', persist_guard)
        abort = body.index('shouldAbort: () => cancelled || !open,', persist)
        self.assertLess(close, close_pop)
        self.assertLess(completion, completion_cancel)
        self.assertLess(scan, stop)
        self.assertLess(stop, persist_guard)
        self.assertLess(persist_guard, persist)
        self.assertLess(persist, abort)

    def test_gold_merge_ips_checks_abort_before_atomic_file_mutation(self):
        source = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> goldMergeIps(')
        end = source.index('\nFuture<Map<String, int?>> _goldProbe', start)
        body = source[start:end]
        load = body.index('await goldLoad();')
        abort = body.index('if (shouldAbort?.call() ?? false) return;', load)
        mutation = body.index('_goldIps[c.ip] =')
        write = body.index('await _goldWrite();')
        self.assertLess(load, abort)
        self.assertLess(abort, mutation)
        self.assertLess(mutation, write)

    def test_global_folder_dns_scan_cancels_on_dialog_close_and_yields_to_national_mode(self):
        source = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> goldShowList(BuildContext context) async {')
        end = source.index('Timer? _goldSaveT;', start)
        dialog = source[start:end]
        scan = dialog.index('final r = await dnsxScan(')
        manual = dialog.index('manual: true,', scan)
        stop = dialog.index('stop: () => cancelled || !open,', manual)
        guard = dialog.index('if (cancelled || !open)', stop)
        save = dialog.index('shouldAbort: () => cancelled || !open,', guard)
        close = dialog.index('cancelled = true;', save)
        self.assertLess(scan, manual)
        self.assertLess(manual, stop)
        self.assertLess(stop, guard)
        self.assertLess(guard, save)
        self.assertLess(save, close)
        self.assertIn('open = false;', dialog)


    def test_manual_dns_scan_does_not_persist_cancelled_partial_results(self):
        extras = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        dns = (ROOT / 'lib' / 'dns_scanner.dart').read_text(encoding='utf-8')
        helper_start = extras.index('Future<bool> goldAddDns(')
        helper_end = extras.index('Future<void> goldMergeIps(', helper_start)
        helper = extras[helper_start:helper_end]
        load = helper.index('await goldLoad();')
        last_abort = helper.index('if (shouldAbort?.call() ?? false) return false;', load)
        mutation = helper.index('_goldDns[h.ip] = h.avgMs;')
        write = helper.index('await _goldWrite();')
        self.assertLess(load, last_abort)
        self.assertLess(last_abort, mutation)
        self.assertLess(mutation, write)
        sheet = dns[dns.index('void dnsxSheet('):]
        scan = sheet.index('r = await dnsxScan(')
        guard = sheet.index('if (stopFlag || !sheetOpen)', scan)
        save = sheet.index('goldAddDns(r, shouldAbort: () => stopFlag || !sheetOpen)', guard)
        self.assertLess(scan, guard)
        self.assertLess(guard, save)


if __name__ == '__main__':
    unittest.main()