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

    def test_national_dns_config_prioritizes_the_selected_validated_domestic_provider(self):
        source = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn("const domesticProviders = {'shecan', 'electro', 'radar'};", source)
        self.assertIn("? dnsProv", source)
        self.assertIn(": 'shecan');", source)
        self.assertIn("_dnsUrls[nationalAutoProvider] ?? _dnsUrls['shecan']!", source)
        self.assertIn("final nationalCustom = dnsProv == 'custom' ? customDnsList() : null;", source)
        self.assertIn('...?nationalCustom', source)
        start = main.index('String _reliableVpnCfg(String cfg)')
        end = main.index('// completes when the VPN tunnel reports CONNECTED', start)
        builder = main[start:end]
        self.assertIn('final preferredDomestic = existingList', builder)
        self.assertIn('domesticSet.contains(item.toString().trim().toLowerCase())', builder)
        self.assertIn('[...preferredDomestic, ...domesticFirst, ...existingList]', builder)

    def test_national_dns_honors_manual_domestic_and_custom_resolvers(self):
        source = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        start = source.index('if (secureDns) {', source.index('String withNpvAmCore'))
        end = source.index("d['queryStrategy']", start)
        dns_builder = source[start:end]
        self.assertIn("dnsProv != 'auto'", dns_builder)
        self.assertIn('domesticProviders.contains(dnsProv)', dns_builder)
        self.assertIn("final nationalCustom = dnsProv == 'custom' ? customDnsList() : null;", dns_builder)
        self.assertIn('...?nationalCustom', dns_builder)
        self.assertIn('...(_dnsUrls[nationalAutoProvider] ?? _dnsUrls[\'shecan\']!)', dns_builder)

    def test_npv_core_preserves_structured_xray_dns_server_entries(self):
        source = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        start = source.index('void addResolver(dynamic raw)')
        end = source.index("d['queryStrategy']", start)
        resolver_builder = source[start:end]
        self.assertIn('if (raw is Map)', resolver_builder)
        self.assertIn('jsonEncode(raw)', resolver_builder)
        self.assertIn('structured.add(Map<String, dynamic>.from(raw))', resolver_builder)
        self.assertIn('for (final value in existingServers) { addResolver(value); }', resolver_builder)
        self.assertIn("d['servers'] = [...ips, ...doh, ...structured];", resolver_builder)
        self.assertNotIn('addResolver(value.toString())', resolver_builder)

    def test_dns_auto_resolver_probe_uses_one_stable_route_mode_snapshot(self):
        source = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        probe_start = source.index('Future<int?> _probeDnsIp(')
        probe_end = source.index('Future<String> pickBestDns(', probe_start)
        probe = source[probe_start:probe_end]
        self.assertIn('required bool nationalModeSnapshot', probe)
        self.assertIn("nationalModeSnapshot ? 'nic.ir' : 'google.com'", probe)
        picker_start = source.index('Future<String> pickBestDns(')
        picker_end = source.index('const _lanCidrs', picker_start)
        picker = source[picker_start:picker_end]
        self.assertIn('final modeSnapshot = nationalMode;', picker)
        self.assertIn('if (nationalMode != modeSnapshot) return dnsProvActive;', picker)
        self.assertIn('final selectedIpProbes = modeSnapshot', picker)
        self.assertIn('nationalModeSnapshot: modeSnapshot', picker)
        self.assertIn('if (networkAfterProbe != networkKey)', picker)

    def test_dns_auto_cache_is_network_operator_aware_and_discards_stale_probes(self):
        source = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        key_start = source.index('Future<String> _dnsNetworkKey()')
        key_end = source.index('const _fragLenOpts', key_start)
        network_key = source[key_start:key_end]
        self.assertIn('$natOpKey', network_key)
        self.assertIn('if (rows.isEmpty)', network_key)
        self.assertIn("|unknown';", network_key)
        pick_start = source.index('Future<String> pickBestDns(')
        pick_end = source.index('const _lanCidrs', pick_start)
        picker = source[pick_start:pick_end]
        self.assertIn('final networkAfterProbe = await _dnsNetworkKey();', picker)
        self.assertIn('if (networkAfterProbe != networkKey)', picker)
        self.assertIn('const Duration(seconds: 45)', picker)
        self.assertIn('_dnsPickLastSucceeded = true;', picker)
        self.assertIn('_dnsPickLastSucceeded = false;', picker)

    def test_nat_doh_cache_is_bound_to_network_operator_and_route_mode(self):
        source = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        start = source.index('Future<bool> natDohUsable(')
        end = source.index('String _natApplyTweaks(', start)
        probe = source[start:end]
        self.assertIn('final networkKey = await _dnsNetworkKey();', probe)
        self.assertIn("final cacheableNetwork = !networkKey.endsWith('|unknown');", probe)
        self.assertIn('_dohPreNetworkKey[v] == networkKey', probe)
        self.assertIn('final modeSnapshot = nationalMode;', probe)
        self.assertIn('final expectedDomain = modeSnapshot ?', probe)
        self.assertIn('final networkKeyAfter = await _dnsNetworkKey();', probe)
        self.assertIn('if (gen != _dohGen || networkKeyAfter != networkKey) return false;', probe)
        clear_start = source.index('void natDohCacheClear()')
        clear_end = source.index('Future<bool> natDohUsable(', clear_start)
        self.assertIn('_dohPreNetworkKey.clear();', source[clear_start:clear_end])

    def test_native_start_and_resume_suppress_late_events_after_user_stop(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private void startFlow(')
        end = source.index('private void resumeSaved(int startId)', start)
        flow = source[start:end]
        stop_guard = flow.index('if (stopping || startId != latestStartId)', flow.index('boolean connectedNow = connectFrom(0, startId);'))
        connected_event = flow.index('emit("CONNECTED"', stop_guard)
        failed_event = flow.index('emit("FAILED"', stop_guard)
        connected_branch = flow.index('if (connectedNow)', stop_guard)
        self.assertIn('if (stopping || startId != latestStartId) return;', flow[stop_guard:connected_branch])
        self.assertLess(stop_guard, connected_event)
        self.assertLess(stop_guard, failed_event)
        resume_start = source.index('private void resumeSaved(int startId)')
        resume_end = source.index('private boolean connectFrom(', resume_start)
        resume = source[resume_start:resume_end]
        guard = resume.index('if (stopping || startId != latestStartId)', resume.index('boolean connectedNow = connectFrom(currentIdx, startId);'))
        connected_branch = resume.index('if (connectedNow)', guard)
        self.assertIn('if (stopping || startId != latestStartId) return;', resume[guard:connected_branch])
        self.assertNotIn('saveState();', resume[guard:connected_branch])



    def test_new_native_start_invalidates_previous_watchdog_and_retry_work(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        on_start = source.index('public int onStartCommand(')
        on_start_end = source.index('private void submit(', on_start)
        start = source[on_start:on_start_end]
        self.assertIn('attemptSeq.incrementAndGet();', start)
        self.assertIn('active = false;', start)
        self.assertIn('retryWaiting = false;', start)

        connect_start = source.index('private boolean connectFrom(int first, int expectedStartId)')
        connect_end = source.index('private boolean bringUpWithTimeout(', connect_start)
        connect = source[connect_start:connect_end]
        self.assertIn('expectedStartId != latestStartId', connect)
        self.assertIn('if (stopping || expectedStartId != latestStartId) return false;', connect)

        retry_start = source.index('private void retryWholeListNow(')
        retry_end = source.index('private ProbeResult probeResult(', retry_start)
        retry = source[retry_start:retry_end]
        self.assertIn('connectFrom(0, expectedStartId)', retry)
        self.assertIn('if (stopping || expectedStartId != latestStartId) return;', retry)





    def test_native_stop_request_cannot_cancel_a_newer_start(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private void requestStop(int startId)')
        end = source.index('private boolean connectFrom(', start)
        stop = source[start:end]
        lifecycle = stop.index('synchronized (startLifecycleLock)')
        stale_check = stop.index('if (startId != latestStartId)', lifecycle)
        mutation = stop.index('latestStopRequestId = startId;', stale_check)
        self.assertLess(lifecycle, stale_check)
        self.assertLess(stale_check, mutation)
        self.assertIn('ignoring stale stop request', stop)
        self.assertLess(stale_check, stop.index('attemptSeq.incrementAndGet();'))


    def test_native_timeout_generation_check_is_atomic_with_start_and_stop(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private boolean bringUpWithTimeout(')
        end = source.index('private static void closeQuietly', start)
        attempt = source[start:end]
        lock = attempt.index('synchronized (startLifecycleLock)')
        check = attempt.index('if (expectedStartId == latestStartId && !stopping)', lock)
        increment = attempt.index('attemptSeq.incrementAndGet();', check)
        self.assertLess(lock, check)
        self.assertLess(check, increment)
        self.assertIn('boolean timeoutOwned = false;', attempt)
        self.assertIn('else if (stopping)', attempt)
        self.assertIn('discarding superseded VPN attempt', attempt)


    def test_superseded_native_start_does_not_wait_for_old_bringup_timeout(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        self.assertIn('private boolean bringUpWithTimeout(Srv s, int expectedStartId)', source)
        start = source.index('private boolean bringUpWithTimeout(')
        end = source.index('private static void closeQuietly', start)
        attempt = source[start:end]
        self.assertIn('expectedStartId != latestStartId', attempt)
        self.assertIn('if (done[0]) {', attempt)
        self.assertIn('return result[0] && !stopping && expectedStartId == latestStartId;', attempt)
        self.assertIn('if (expectedStartId == latestStartId && !stopping)', attempt)
        self.assertNotIn('attemptSeq.incrementAndGet();\n        if (stopping)', attempt)


    def test_native_watchdog_and_delayed_retry_are_bound_to_their_start_generation(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private void checkOnce()')
        end = source.index('private void rescheduleNormal()', start)
        watchdog = source[start:end]
        self.assertIn('final int healthStartId;', watchdog)
        self.assertIn('healthStartId = latestStartId;', watchdog)
        self.assertIn('if (latestStartId != healthStartId) return;', watchdog)

        retry_start = source.index('private void retryWholeListLater()')
        retry_end = source.index('private ProbeResult probeResult(', retry_start)
        retry = source[retry_start:retry_end]
        self.assertIn('final int retryStartId = latestStartId;', retry)
        self.assertIn('final int retryAttempt = attemptSeq.get();', retry)
        self.assertIn('retryWholeListNow(retryStartId, retryAttempt)', retry)
        self.assertIn('private void retryWholeListNow(int expectedStartId, int expectedAttempt)', retry)
        self.assertIn('expectedStartId != latestStartId', retry)
        self.assertIn('expectedAttempt != attemptSeq.get()', retry)
        flow_start = source.index('private void startFlow(')
        flow_end = source.index('private void resumeSaved(', flow_start)
        self.assertIn('retryWaiting = false;', source[flow_start:flow_end])


    def test_native_watchdog_scheduler_cannot_be_resurrected_after_destroy(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        self.assertIn('private final Object schedulerLock = new Object();', source)
        self.assertIn('private volatile boolean destroyed = false;', source)
        destroy_start = source.index('public void onDestroy()')
        destroy_end = source.index('private static String orEmpty', destroy_start)
        destroy = source[destroy_start:destroy_end]
        self.assertIn('synchronized (schedulerLock)', destroy)
        self.assertIn('destroyed = true;', destroy)
        self.assertLess(destroy.index('destroyed = true;'), destroy.index('scheduler = null;'))
        schedule_start = source.index('private void scheduleTask(')
        schedule_end = source.index('private void stopWatchdog()', schedule_start)
        schedule = source[schedule_start:schedule_end]
        self.assertIn('synchronized (schedulerLock)', schedule)
        self.assertIn('if (destroyed || stopping) return;', schedule)
        self.assertLess(schedule.index('if (destroyed || stopping) return;'),
                        schedule.index('s.schedule(task, delaySec, TimeUnit.SECONDS)'))
        stop_start = schedule_end
        stop_end = source.index('private void checkOnce()', stop_start)
        self.assertIn('synchronized (schedulerLock)', source[stop_start:stop_end])


    def test_native_watchdog_requires_corroborated_domestic_evidence_and_mode_snapshot(self):
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = service.index('private ProbeResult probeResult(boolean modeSnapshot)')
        end = service.index('private ProbeResult probeOne(', start)
        probe = service[start:end]
        self.assertIn('int required = modeSnapshot ? 2 : 1;', probe)
        self.assertIn('passed >= required', probe)
        self.assertIn('DOMESTIC_PROBE_URLS', probe)
        watchdog = service[service.index('private void checkOnce()'):start]
        self.assertIn('final boolean modeSnapshot = nationalMode;', watchdog)
        self.assertIn('probeResult(modeSnapshot)', watchdog)
        self.assertIn('if (nationalMode != modeSnapshot)', watchdog)
        self.assertIn('rescheduleNormal();', watchdog)

    def test_national_tunnel_acceptance_requires_multiple_independent_destinations(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = source.index('Future<bool> _tunnelTrafficOk()')
        end = source.index('Future<bool> _stableTunnelTrafficOk', start)
        body = source[start:end]
        self.assertIn('Future.wait(urls.map', body)
        self.assertIn('final required = modeSnapshot ? 2 : 1;', body)
        self.assertIn('nationalMode != modeSnapshot', body)
        self.assertIn('return passed >= required;', body)
        self.assertNotIn('if (ok) return true;', body)

    def test_nat_variant_winner_is_provisional_until_real_tunnel_confirmation(self):
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        delay_start = main.index('Future<int?> _delayOf(')
        delay_end = main.index('bool _lastDelayTimedOut', delay_start)
        delay = main[delay_start:delay_end]
        self.assertIn('natVarCandidateSet(s, v);', delay)
        self.assertNotIn('natVarSet(s, v);', delay)
        self.assertIn('void natVarCandidateConfirm(Server s)', nat)
        self.assertIn('void natVarCandidateDiscard(Server s)', nat)
        connect_start = main.index('Future<bool> _connectLoop(')
        connect_end = main.index('Future<void> _measureCurrent(', connect_start)
        connect = main[connect_start:connect_end]
        self.assertIn('if (!tunOk)', connect)
        self.assertIn('natVarCandidateDiscard(s);', connect)
        self.assertIn('natVarCandidateConfirm(s);', connect)
        self.assertLess(connect.index('natVarCandidateConfirm(s);'),
                        connect.index("dbg('اتصال: ${s.name} ترافیک تونل OK"))
        connected_start = main.index('void _onConnected(Server s)')
        connected_end = main.index('Future<void> _', connected_start)
        self.assertNotIn('natVarCandidateConfirm(s);', main[connected_start:connected_end])
        self.assertIn('natVarCandidates[_nk(s)] ?? natVar[_nk(s)]', nat)

    def test_front_sni_candidates_are_hostnames_and_all_matrix_indices_are_valid(self):
        nip = (ROOT / 'lib' / 'nip_scan.dart').read_text(encoding='utf-8')
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        self.assertNotIn("'1.1.1.1'", nip)
        self.assertIn('const [0, 2, 3, 6][sniIdx]', nat)
        self.assertIn("_NatSpec('SNI>divar.ir', sniSwap: 6)", nat)
        self.assertIn('if (sniIdx < 0 || sniIdx >= natFrontSnis.length) return cfg;', nat)

    def test_automatic_scan_is_not_a_subnet_or_all_port_sweep(self):
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        start = nat.index('List<String> natSeedBlocks(')
        end = nat.index('\nint natMemQueued', start)
        seed_block = nat[start:end]
        self.assertIn("InternetAddressType.IPv6", seed_block)
        self.assertIn("parsed.address}/128", seed_block)
        domain_start = nat.index('Future<List<String>> _natDomainFirst(')
        domain_end = nat.index('\nFuture<List<String>> natDeviceHosts()', domain_start)
        domain_scan = nat[domain_start:domain_end]
        self.assertNotIn('natIrDomains', domain_scan)
        self.assertNotIn('for (var p = 1; p < 65536; p++)', domain_scan)

    def test_reliable_config_preserves_iranian_geoip_resolution_strategy(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = main.index('String _reliableVpnCfg(String cfg)')
        end = main.index('// completes when the VPN tunnel reports CONNECTED', start)
        builder = main[start:end]
        self.assertIn('if (iranRoute && iranGeoip)', builder)
        self.assertIn("rt['domainStrategy'] = 'IPIfNonMatch';", builder)
        self.assertIn("rt['domainStrategy'] ??= 'AsIs';", builder)

    def test_reliable_config_applies_route_only_preference_to_all_inbounds(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = main.index('String _reliableVpnCfg(String cfg)')
        end = main.index('// completes when the VPN tunnel reports CONNECTED', start)
        builder = main[start:end]
        self.assertIn("sniffing['routeOnly'] = routeOnly;", builder)
        self.assertEqual(builder.count("'routeOnly': routeOnly"), 2)
        self.assertNotIn("'routeOnly': true", builder)

    def test_connection_fallback_keeps_plain_config_unmodified(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = main.index('final cfgTries = <String>[')
        end = main.index('var usedFallback = false;', start)
        candidates = main[start:end]
        self.assertIn('.map((c) => withErrLog(sanitizeCfg(c))).toList();', candidates)
        self.assertNotIn('withIranRouting(withNpvAmCore(c))', candidates)

    def test_connect_path_uses_mode_aware_tunnel_probe(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn('networkAware: true', main)
        self.assertIn('final urls = modeSnapshot ? _tunnelTestUrlsNational', main)

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

    def test_owner_lock_invalidates_in_flight_authentication_and_password_rotation(self):
        auth = (ROOT / 'lib' / 'king_ai_owner_auth.dart').read_text(encoding='utf-8')
        self.assertIn('int _sessionGeneration = 0;', auth)
        lock_start = auth.index('void lock()')
        lock_end = auth.index('Future<void> _requireRepositoryOwnerIdentity()', lock_start)
        self.assertIn('_sessionGeneration++;', auth[lock_start:lock_end])
        for signature, end_marker in [
            ('Future<void> setInitialPassword(', '/// Password changes'),
            ('Future<void> changePassword(', 'Future<bool> authenticate('),
            ('Future<bool> authenticate(', 'void lock()'),
        ]:
            start = auth.index(signature)
            end = auth.index(end_marker, start)
            method = auth[start:end]
            self.assertIn('final sessionGeneration = _sessionGeneration;', method)
            if signature.startswith('Future<bool> authenticate'):
                self.assertIn('if (sessionGeneration != _sessionGeneration) return false;', method)
            else:
                self.assertIn('sessionGeneration == _sessionGeneration', method)

        enrollment = auth[auth.index('Future<void> setInitialPassword('):auth.index('/// Password changes')]
        rotation = auth[auth.index('Future<void> changePassword('):auth.index('Future<bool> authenticate(')]
        self.assertIn('Owner enrollment was cancelled by app backgrounding.', enrollment)
        self.assertIn('Owner password change was cancelled by app backgrounding.', rotation)
        self.assertIn('await _storage.delete(key: _saltKey);', enrollment)
        self.assertIn('await _storage.write(key: _saltKey, value: oldSalt);', rotation)

    def test_owner_auth_rejects_corrupt_or_truncated_stored_credentials(self):
        auth = (ROOT / 'lib' / 'king_ai_owner_auth.dart').read_text(encoding='utf-8')
        start = auth.index('Future<bool> authenticate(String password)')
        end = auth.index('void lock()', start)
        authenticate = auth[start:end]
        self.assertIn('on FormatException', authenticate)
        self.assertIn('salt.length != 16 || expected.length != 32', authenticate)
        self.assertIn('_sessionClock = null;', authenticate)
        self.assertIn('return false;', authenticate)

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
        code_start = main.index('final codeRequest = projectRequest || (!KingCommandSafety.isQuestionRequest(command) && RegExp(')
        code_end = main.index(').hasMatch(command));', code_start)
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
        self.assertIn("initialFeatureRequest: projectRequest ? null : command", main)

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
        self.assertIn('final codeRequest = projectRequest || (!KingCommandSafety.isQuestionRequest(command) && RegExp(', main)
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
        self.assertIn('InternetAddress.tryParse(host)', pilot_scan)
        self.assertIn('address.type != InternetAddressType.IPv4', pilot_scan)
        self.assertIn('address.type != InternetAddressType.IPv6', pilot_scan)
        self.assertIn('Socket.connect(address, 443', pilot_scan)
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
        start = main.index('final codeRequest = projectRequest || (!KingCommandSafety.isQuestionRequest(command) && RegExp(')
        end = main.index(').hasMatch(command));', start)
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
        self.assertIn('initialFeatureRequest: projectRequest ? null : command', main)
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
        self.assertIn('if (await verifyStableTraffic()) {', national)
        self.assertIn('await recordStable(endpointKey, stillValid: stillValid);', national)
        stable_record_start = national.index('static Future<void> recordStable(')
        stable_record_end = national.index('static Future<void> _save()', stable_record_start)
        stable_record = national[stable_record_start:stable_record_end]
        self.assertIn('await load();', stable_record)
        self.assertIn('if (stillValid != null && !stillValid()) return;', stable_record)
        self.assertIn('Future<bool> _stableTunnelTrafficOk(Server server)', main)
        self.assertIn('_siteOpens(url, viaCore: true)', main)
        self.assertIn('passed >= 2', main)
        stable_start = main.index('final nnieGeneration = _connGen;')
        stable_end = main.index('if (mounted) setState(() {})', stable_start)
        stable_probe = main[stable_start:stable_end]
        self.assertIn('NationalNetworkIntelligence.armStable(', stable_probe)
        self.assertIn('final trafficOk = await _stableTunnelTrafficOk(s);', stable_probe)
        self.assertIn('return trafficOk &&', stable_probe)
        post_probe = stable_probe.index('final trafficOk = await _stableTunnelTrafficOk(s);')
        self.assertGreater(stable_probe.index('nnieGeneration == _connGen', post_probe),
                           post_probe)
        self.assertIn('identical(s, current)', stable_probe)


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

    def test_local_chat_turns_and_memory_clear_are_serialized_as_one_transaction(self):
        local = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        self.assertIn('Future<void> _conversationQueue = Future<void>.value();', local)
        self.assertIn('Future<T> _runSerializedConversation<T>', local)
        ask_start = local.index('Future<String> ask(String prompt,')
        ask_end = local.index('Future<String> _askConversationTurn(', ask_start)
        public_ask = local[ask_start:ask_end]
        self.assertIn('_runSerializedConversation(() => _askConversationTurn(', public_ask)
        turn_start = ask_end
        turn_end = local.index('/// Private coding entry point.', turn_start)
        turn = local[turn_start:turn_end]
        self.assertLess(turn.index('await _loadConversationMemory();'), turn.index('final history ='))
        self.assertLess(turn.index('await _saveConversationMemory();'), turn.index('return answer;'))
        clear_start = local.index('Future<void> clearConversationMemory()')
        clear_end = local.index('bool _needsLiveResearch(', clear_start)
        clear = local[clear_start:clear_end]
        self.assertIn('_runSerializedConversation(() async {', clear)
        self.assertIn('_conversationTurns.clear();', clear)

    def test_local_model_download_uses_the_shared_lifecycle_guard(self):
        local = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        download_start = local.index('Future<String> downloadModel(')
        download_end = local.index('Future<String> _downloadModelUnlocked(', download_start)
        download = local[download_start:download_end]
        self.assertIn("if (_busy) throw StateError('Local AI is already busy');", download)
        self.assertLess(download.index('_busy = true;'), download.index('_downloadModelUnlocked('))
        self.assertIn('finally {', download)
        self.assertIn('_busy = false;', download)
        unlocked_start = download_end
        unlocked_end = local.index('Future<void> loadModel(', unlocked_start)
        unlocked = local[unlocked_start:unlocked_end]
        self.assertIn('await manager.init();', unlocked)
        load_start = unlocked_end
        load_end = local.index('Future<String> askPilot(', load_start)
        loader = local[load_start:load_end]
        self.assertIn('_busy = true;', loader)
        self.assertIn('_downloadModelUnlocked(onProgress: onProgress)', loader)
        self.assertNotIn('downloadModel(onProgress: onProgress)', loader)


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
        self.assertIn('if (!seenKeys.add(cfg)) continue;', source)
        impl_start = source.index('Future<void> _natHotEnsureImpl({bool force = false}) async')
        impl_end = source.index('bool natHotReady()', impl_start)
        refresh = source[impl_start:impl_end]
        cleanup = refresh.index('for (final path in [...parts, extraPath])')
        fetch = refresh.index('await pool<int>')
        self.assertLess(cleanup, fetch)
        self.assertIn('final stalePart = File(path);', refresh[cleanup:fetch])
        self.assertIn('await stalePart.delete();', refresh[cleanup:fetch])
        self.assertIn('if (await stalePart.exists()) rethrow;', refresh[cleanup:fetch])
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
        self.assertIn("src.replace('this.onDestroy();', 'stopCoreAndReleaseService();')", patch)
        self.assertIn('P1-39 stop native core before invalid-start TUN cleanup', patch)
        self.assertIn('Failed to stop core before releasing TUN', patch)
        self.assertIn('Failed to stop core before service cleanup', patch)
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
        self.assertLess(stop.index('startForegroundSafe('), stop.index('requestStop(startId)'))

    def test_vpn_service_promotes_before_queuing_sticky_restart_or_stop(self):
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = service.index('public int onStartCommand(Intent intent')
        end = service.index('/** Runs a task on the single worker thread', start)
        command = service[start:end]
        restart = command[command.index('if (intent == null)'):command.index('if (ACTION_STOP.equals(action))')]
        stop = command[command.index('if (ACTION_STOP.equals(action))'):command.index('if (!ACTION_START.equals(action))')]
        self.assertLess(restart.index('startForegroundSafe('), restart.index('submit(() -> resumeSaved(startId))'))
        self.assertLess(stop.index('startForegroundSafe('), stop.index('submit(() -> stopEverything(startId))'))

    def test_vpn_service_refuses_start_when_foreground_promotion_fails(self):
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = service.index('public int onStartCommand(Intent intent')
        end = service.index('/** Runs a task on the single worker thread', start)
        command = service[start:end]
        restart = command[command.index('if (intent == null)'):command.index('if (ACTION_STOP.equals(action))')]
        action_start = command[command.index('if (!ACTION_START.equals(action))'):]

        self.assertIn('private boolean startForegroundSafe(String remark)', service)
        self.assertIn('private boolean updateNotification(String text)', service)
        self.assertIn('return true;', service[service.index('private boolean updateNotification'):])
        self.assertIn('return false;', service[service.index('private boolean updateNotification'):])
        self.assertLess(restart.index('if (!startForegroundSafe('), restart.index('submit(() -> resumeSaved(startId))'))
        self.assertIn('requestStop(startId);', restart)
        self.assertIn('submit(() -> stopEverything(startId));', restart)
        self.assertLess(action_start.index('if (!startForegroundSafe(first.remark))'),
                        action_start.index('submit(() -> startFlow(first, backups, attempt, startId))'))
        failure = action_start[action_start.index('if (!startForegroundSafe(first.remark))'):
                               action_start.index('final int attempt = activeAttemptId')]
        self.assertIn('emit("FAILED", lastError, activeAttemptId);', failure)
        self.assertIn('return START_NOT_STICKY;', failure)
        self.assertIn('Unable to enter foreground mode', failure)
        empty_config = action_start[action_start.index('if (json == null || json.isEmpty())'):
                                    action_start.index('Srv first = new Srv(')]
        self.assertIn('submit(() -> stopEverything(startId));', empty_config)
        self.assertNotIn('submit(this::stopEverything);', action_start)



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
        self.assertIn('readCoreRunningWithWatchdog(core, "health-watchdog-state")', watchdog)
        self.assertIn('if (coreState == null)', watchdog)
        self.assertIn('Unknown native state is not evidence of a broken tunnel.', watchdog)
        self.assertIn('if (active && !stopping) rescheduleNormal();', watchdog)
        self.assertLess(watchdog.index('if (coreState == null)'),
                        watchdog.index('ProbeResult pr = coreUp ? probeResult(modeSnapshot)'))

    def test_vpn_service_defers_tun_close_until_native_stop_is_verified(self):
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = service.index('private boolean stopCoreNow()')
        end = service.index('/**\n     * Worker-side start of one attempt.', start)
        stop = service[start:end]
        self.assertIn('closeTunAfterCoreStop = true;', stop)
        self.assertEqual(stop.count('core.isV2rayCoreRunning()'), 1)
        self.assertIn('readCoreRunningWithWatchdog(core, "stopCore-preflight")', stop)
        self.assertIn('boolean verified = false;', stop)
        self.assertIn('verified = !stillRunning;', stop)
        self.assertIn('if (verified && closeTunAfterCoreStop)', stop)
        self.assertIn('else if (!verified || stillRunning)', stop)
        self.assertIn('native core remains running; retaining TUN', stop)
        self.assertIn('could not verify native core stop; retaining TUN', stop)
        self.assertLess(stop.index('core.stopCore();'), stop.index('verified = !stillRunning;'))
        self.assertLess(stop.index('endNative();'), stop.index('coreStopping = false;'))
        self.assertLess(stop.index('if (coreStopping)'), stop.index('final Boolean runningState'))

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
        self.assertIn('package_info_plus', build)
        self.assertIn('package_info_plus', release)
        self.assertIn('package_info_plus', orchestrator)
        self.assertIn("CGO_LDFLAGS", orchestrator)
        self.assertIn("max-page-size=16384", orchestrator)
        self.assertIn("'--release'", orchestrator)
        self.assertIn("'--obfuscate'", orchestrator)
        self.assertIn("'--split-per-abi'", orchestrator)
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


    def test_nat_ip_memory_cache_is_validated_deduplicated_and_capped(self):
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        start = nat.index('Future<void> natIpMemLoad() async {')
        end = nat.index('const String _domMemKey', start)
        loader = nat[start:end]
        self.assertIn('decoded.take(_ipMemMax * 4)', loader)
        self.assertIn('address.type != InternetAddressType.IPv4', loader)
        self.assertIn('port < 1', loader)
        self.assertIn('port > 65535', loader)
        self.assertIn('timestamp < cutoff', loader)
        self.assertIn('if (!seen.add(key)) continue;', loader)
        self.assertIn('if (natIpMem.length >= _ipMemMax) break;', loader)
        self.assertIn('await p.setString(_ipMemKey, jsonEncode(natIpMem));', loader)
        self.assertIn('final decoded = jsonDecode(raw);', loader)
        self.assertIn('catch (e, stk)', loader)

    def test_configured_nat_ranges_are_normalized_and_sync_expansion_is_bounded(self):
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        normalize_start = nat.index('List<String> _natNormalizeConfiguredRanges(')
        normalize_end = nat.index("/// Next bounded sample", normalize_start)
        normalize = nat[normalize_start:normalize_end]
        self.assertIn('InternetAddressType.IPv4', normalize)
        self.assertIn('prefix < 8', normalize)
        self.assertIn('prefix > 32', normalize)
        self.assertIn('if (out.length >= 128) break;', normalize)
        self.assertIn('_natNormalizeConfiguredRanges(', nat[nat.index('Future<void> natRangesSave'):])
        self.assertIn("RegExp(r'[\\r\\n,; ]+')", nat[nat.index('Future<void> natRangesSave'):])
        self.assertIn("natRanges.join('\\n')", nat[nat.index('Future<void> natRangesSave'):])
        batch_start = nat.index('({List<String> addresses, int nextCursor}) _natConfiguredRangeBatch(')
        batch_end = nat.index('Future<void> natRangesSave(', batch_start)
        batch = nat[batch_start:batch_end]
        self.assertIn('final candidateCap = min(limit * 4, 131072);', batch)
        self.assertIn('min(1024, remaining)', batch)
        self.assertIn('natRanges.take(128)', batch)

    def test_nat_range_scan_discards_cancelled_batches_without_advancing_cursors(self):
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
        scan_guard = body.index('if (shouldAbort() || scanExpired()) return const <String>[];', scan)
        cursor_commit = body.index('_cfRangeCursors\n    ..clear()')
        configured_commit = body.index('_natConfiguredRangeCursor = configuredBatch.nextCursor;')
        self.assertLess(hot, hot_guard)
        self.assertLess(compute, compute_guard)
        self.assertLess(compute_guard, scan)
        self.assertLess(cancel, scan_guard)
        self.assertLess(scan_guard, cursor_commit)
        self.assertLess(cursor_commit, configured_commit)
        helper_start = nat.index('({List<String> addresses, int nextCursor}) _natConfiguredRangeBatch(')
        helper_end = nat.index('Future<void> natRangesSave(', helper_start)
        helper = nat[helper_start:helper_end]
        self.assertIn('nextCursor: (start + count) % values.length', helper)
        self.assertNotIn('SharedPreferences.getInstance()', helper)
        scan_only_start = main.index('Future<void> _natScanOnly()')
        scan_only_end = main.index('// NATFIRSTFAST:', scan_only_start)
        scan_only = main[scan_only_start:scan_only_end]
        self.assertIn('stop: () => abort || nationalMode != runNationalMode,', scan_only)
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
        load = source.index('await ipAutoLoad(skipIfBusy: true);', sheet)
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


    def test_nat_cidr_expansion_supports_bounded_ipv6_with_bigint(self):
        source = (ROOT / 'lib' / 'nat_ip_scan.dart').read_text(encoding='utf-8')
        self.assertIn('return natExpandIpv6Cidr(cidr, maxPerBlock: limit);', source)
        self.assertIn('List<String> natExpandIpv6Cidr(', source)
        self.assertIn('InternetAddressType.IPv6', source)
        self.assertIn('BigInt.one << hostBits', source)
        self.assertIn('final limit = min(maxPerBlock, 65536);', source)
        self.assertIn('InternetAddress.fromRawAddress(', source)

    def test_nat_ip_scan_uses_ip_literals_without_system_dns(self):
        scan = (ROOT / 'lib' / 'nat_ip_scan.dart').read_text(encoding='utf-8')
        parse_start = scan.index('InternetAddress? _natParseIpLiteral(')
        probe_start = scan.index('Future<int?> natTcpProbe(', parse_start)
        probe_end = scan.index('/// Clamp a user-supplied', probe_start)
        parser = scan[parse_start:probe_start]
        probe = scan[probe_start:probe_end]
        self.assertIn('InternetAddress.tryParse(value.trim())', parser)
        self.assertIn('InternetAddressType.IPv4', parser)
        self.assertIn('InternetAddressType.IPv6', parser)
        self.assertIn('Socket.connect(address, port, timeout: timeout)', probe)
        self.assertNotIn('Socket.connect(ip, port', probe)
        scan_start = scan.index('Future<List<NatIpHit>> natScanIps(')
        scan_body = scan[scan_start:]
        self.assertIn('_natParseIpLiteral(raw)', scan_body)
        self.assertIn('seen.add(address.address)', scan_body)

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
        load_start = source.index('Future<void> ipAutoLoad({bool skipIfBusy = false}) async {')
        save_start = source.index('Future<bool> _ipAutoSave() async {', load_start)
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

    def test_ip_auto_address_generation_stages_cursors_until_full_scan_succeeds(self):
        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        start = source.index('Future<_IpAutoAddressBatch?> _ipAutoNextAddrs(')
        end = source.index('extension IpAutoExt', start)
        body = source[start:end]
        compute = body.index('await compute(_genAddrsIso, args)')
        abort = body.index('if (nationalMode != modeSnapshot || (shouldAbort?.call() ?? false))')
        self.assertLess(compute, abort)
        self.assertNotIn('..clear()', body)
        self.assertNotIn('ipAutoPos =', body)
        self.assertIn('return _IpAutoAddressBatch(', body)

    def test_ip_auto_commits_address_cursors_only_after_uncancelled_scan(self):
        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        start = source.index('Future<bool> _ipAutoRunOnce(')
        end = source.index('Future<void> ipAutoSheet(', start)
        body = source[start:end]
        completion = body.rindex("if (halted()) {")
        commit = body.index('ipAutoCursors', completion)
        position = body.index('ipAutoPos = addressBatch.nextPosition;', completion)
        self.assertLess(completion, commit)
        self.assertLess(commit, position)
        self.assertIn('addressBatch.cursors', body)
        self.assertIn('addressBatch.nextPosition', body)

    def test_ip_auto_save_treats_legacy_mirrors_as_best_effort_after_atomic_commit(self):
        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        start = source.index('Future<bool> _ipAutoSave()')
        end = source.index('/// خودکار فقط IPهای دقیق', start)
        save = source[start:end]
        primary = save.index("await p.setString(stateKey, jsonEncode(checkpoint))")
        mirror_try = save.index('try {', primary)
        mirror_write = save.index("await p.setString(hitsKey")
        self.assertIn(r"hits.join('\n')", save)
        self.assertIn(r"pending.join('\n')", save)
        self.assertNotIn(r"pending.join('\\n')", save)
        mirror_catch = save.index('} catch (e, stk)', mirror_write)
        success = save.index('return true;', mirror_catch)
        self.assertLess(primary, mirror_try)
        self.assertLess(mirror_try, mirror_write)
        self.assertLess(mirror_write, mirror_catch)
        self.assertLess(mirror_catch, success)

    def test_ip_auto_scan_rolls_back_advanced_cursor_when_atomic_checkpoint_fails(self):
        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        start = source.index('Future<bool> _ipAutoRunOnce(')
        end = source.index('Future<void> ipAutoSheet(', start)
        scan = source[start:end]
        self.assertIn('final previousPending = List<String>.of(ipAutoPendingCore);', scan)
        self.assertIn('final previousCursors = Map<String, int>.of(ipAutoCursors);', scan)
        self.assertIn('final previousPosition = ipAutoPos;', scan)
        self.assertIn('final checkpointSaved = await _ipAutoSave();', scan)
        failure = scan.index('if (!checkpointSaved)')
        self.assertLess(failure, scan.index('ipAutoPos = previousPosition;', failure))
        self.assertIn('ipAutoCursors\n            ..clear()\n            ..addAll(previousCursors);', scan)

    def test_hot_cache_fetch_uses_operation_local_cancellation(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        pool_start = main.index('Future<void> pool<T>(')
        pool_end = main.index('// FIXTUNNEL:', pool_start)
        pool = main[pool_start:pool_end]
        self.assertIn('{bool Function()? shouldStop}', pool)
        self.assertIn('(shouldStop?.call() ?? poolStop)', pool)

        source = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> _natHotEnsureImpl(')
        end = source.index('bool natHotReady()', start)
        refresh = source[start:end]
        self.assertIn('shouldStop: () => sw.elapsed > natHotFetchDeadline', refresh)

    def test_national_hot_source_reads_and_rebuilds_share_one_serial_queue(self):
        source = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        self.assertIn('Future<void> _hotIoQueue = Future<void>.value();', source)
        self.assertIn('Future<T> _hotSerialize<T>(Future<T> Function() action)', source)
        ensure_start = source.index('Future<void> natHotEnsure({bool force = false})')
        ensure_end = source.index('Future<void> _natHotEnsureImpl(', ensure_start)
        ensure = source[ensure_start:ensure_end]
        self.assertIn('_hotSerialize<void>(() => _natHotEnsureImpl(force: force))', ensure)
        next_start = source.index('Future<List<Server>> natHotNext(')
        impl_start = source.index('Future<List<Server>> _natHotNextImpl(', next_start)
        next_wrapper = source[next_start:impl_start]
        self.assertIn('_hotSerialize<List<Server>>(', next_wrapper)
        impl_end = source.index('const String kNatMemKey', impl_start)
        impl = source[impl_start:impl_end]
        self.assertIn('return await _natHotNextImpl(n, fetch: false, retried: true);', impl)
        self.assertNotIn('return natHotNext(', impl)


    def test_national_hot_source_forced_refresh_is_not_swallowed_by_active_refresh(self):
        source = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        ensure_start = source.index('Future<void> natHotEnsure({bool force = false})')
        ensure_end = source.index('Future<void> _natHotEnsureImpl(', ensure_start)
        ensure = source[ensure_start:ensure_end]
        self.assertIn('bool _hotEnsureRunningForce = false;', source)
        self.assertIn('final activeWasForced = _hotEnsureRunningForce;', ensure)
        self.assertIn('if (force && !activeWasForced)', ensure)
        self.assertIn('await natHotEnsure(force: true);', ensure)
        self.assertIn('_hotEnsureRunningForce = force;', ensure)
        self.assertIn('_hotEnsureRunningForce = false;', ensure)


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
        self.assertIn('await ipAutoLoad(skipIfBusy: true);', body)
        load = body.index('await ipAutoLoad(skipIfBusy: true);')
        lock = body.index('ipAutoBusy = true;')
        run = body.index('await _ipAutoRunOnce(')
        self.assertLess(load, lock)
        self.assertLess(lock, run)
        self.assertIn('final retryWhy = _ipAutoRefusal();', body)
        self.assertIn('nationalMode != runNationalMode', body)

    def test_nat_ip_scan_uses_monotonic_budget_and_integer_concurrency(self):
        source = (ROOT / 'lib' / 'nat_ip_scan.dart').read_text(encoding='utf-8')
        self.assertIn('(cores * 4).clamp(16, 256).toInt()', source)
        self.assertIn('(cores * 2).clamp(8, 64).toInt()', source)
        self.assertIn('port < 1 || port > 65535', source)
        self.assertIn('final elapsed = Stopwatch()..start();', source)
        self.assertIn('if (elapsed.elapsed >= budget) return;', source)
        self.assertNotIn('DateTime.now().add(budget)', source)

    def test_nat_ip_scan_discards_in_flight_results_after_cancellation(self):
        source = (ROOT / 'lib' / 'nat_ip_scan.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> worker() async {')
        end = source.index('\n  }', start)
        worker = source[start:end]
        probe = worker.index('final ms = await natTcpProbe(ip, port, timeout);')
        stale_guard = worker.index('if (aborted() || elapsed.elapsed >= budget)', probe)
        insert = worker.index('if (ms != null && hits.length < want)', stale_guard)
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
        self.assertIn('final remainingBudget = budget - scanClock.elapsed;', body)
        self.assertIn('final portBudget = perPortCap < remainingBudget', body)
        self.assertIn('milliseconds: max(20000, budget.inMilliseconds ~/ max(1, portList.length)).toInt()', body)
        scan = body.index('final hits = await natScanIps(')
        self.assertIn('budget: portBudget,', body[scan:scan + 500])
        expiry = body.index('if (shouldAbort() || scanExpired()) return const <String>[];', scan)
        cursor = body.index('_cfRangeCursors\n    ..clear()')
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

    def test_nat_domain_first_discards_partial_results_after_cancel_or_deadline(self):
        source = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        start = source.index('Future<List<String>> _natDomainFirst(')
        end = source.index('Future<List<String>> natDeviceHosts()', start)
        body = source[start:end]
        self.assertIn('final scanClock = Stopwatch()..start();', body)
        self.assertIn('const scanBudget = Duration(seconds: 45);', body)
        self.assertLess(body.index('final scanClock'), body.index('for (final entry in endpoints.entries)'))
        lookup = body.index('await safeLookup(entry.key)')
        lookup_guard = body.index('if (cancelled()) return const <String>[];', lookup)
        self.assertLess(lookup, lookup_guard)
        self.assertIn('bool expired() => scanClock.elapsed >= scanBudget;', body)
        scan = body.index('final hits = await natScanIps(')
        self.assertIn('cancelled: cancelled,', body)
        discard = body.index('if (cancelled())', scan)
        append = body.index('out.add(', discard)
        self.assertLess(scan, discard)
        self.assertLess(discard, append)
        self.assertIn('return const <String>[];', body[discard:append])
        self.assertGreaterEqual(body.count('if (cancelled())'), 5)
        self.assertIn('if (cancelled()) return const <String>[];', body[body.index('} catch (e, stk)'):])

    def test_nat_ip_scan_never_exceeds_requested_hit_limit_under_concurrency(self):
        source = (ROOT / 'lib' / 'nat_ip_scan.dart').read_text(encoding='utf-8')
        start = source.index('Future<List<NatIpHit>> natScanIps(')
        body = source[start:]
        self.assertIn('if (ips.isEmpty || want <= 0) return <NatIpHit>[];', body)
        self.assertIn('if (ms != null && hits.length < want)', body)

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

    def test_auto_sni_scan_has_a_hard_total_time_budget(self):
        source = (ROOT / 'lib' / 'auto_scanners.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> autoScanRun(')
        end = source.index('Future<void> autoScanSheet(', start)
        body = source[start:end]
        self.assertIn('const scanBudget = Duration(minutes: 3);', body)
        self.assertIn('final scanClock = Stopwatch()..start();', body)
        self.assertIn('bool timedOut() => scanClock.elapsed >= scanBudget;', body)
        self.assertIn('|| timedOut();', body)
        self.assertIn('shouldAbort: () => cancelled(),', body)
        self.assertIn('مهلت سه‌دقیقه‌ای اسکن تمام شد', body)

    def test_auto_sni_scan_aborts_when_network_mode_changes_mid_run(self):
        source = (ROOT / 'lib' / 'auto_scanners.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> autoScanRun(')
        end = source.index('Future<void> autoScanSheet(', start)
        body = source[start:end]
        snapshot = body.index('final scanNationalMode = nationalMode;')
        first_await = body.index('await goldLoad();')
        self.assertLess(snapshot, first_await)
        self.assertIn('bool cancelled() =>', body)
        self.assertIn('_autoScanStop || vpnActive() || vpnWanted() || nationalMode != scanNationalMode || timedOut();', body)
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
        self.assertIn('_autoScanStop || vpnActive() || vpnWanted() || nationalMode != scanNationalMode || timedOut();', body)
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
        start = source.index('Future<_IpAutoAddressBatch?> _ipAutoNextAddrs(')
        end = source.index('extension IpAutoExt', start)
        body = source[start:end]
        mode = body.index('final modeSnapshot = nationalMode;')
        position = body.index('final startPosSnapshot = ipAutoPos;')
        cursors = body.index('final cursorSnapshot = Map<String, int>.of(ipAutoCursors);')
        compute = body.index('await compute(_genAddrsIso, args)')
        guard = body.index('if (nationalMode != modeSnapshot || (shouldAbort?.call() ?? false))')
        generated = body.index("final generatedCursors = Map<String, int>.from(gen['cursors'] as Map);")
        self.assertLess(mode, compute)
        self.assertLess(position, compute)
        self.assertLess(cursors, compute)
        self.assertLess(compute, guard)
        self.assertLess(guard, generated)
        self.assertNotIn('..clear()', body)
        self.assertNotIn('ipAutoPos =', body)
        self.assertIn('return _IpAutoAddressBatch(', body)

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
        prefs = helper.index('final p = await SharedPreferences.getInstance();')
        abort = helper.index('if (shouldAbort?.call() ?? false) return false;', prefs)
        mutation = helper.index('for (final entry in updates.entries)')
        write = helper.index('final write = _goldWrite(p);')
        self.assertLess(prefs, abort)
        self.assertLess(abort, mutation)
        self.assertLess(mutation, write)
        self.assertIn('return await write;', helper)
        self.assertIn('return false;', helper[helper.index('catch (e, stk)'):])

    def test_gold_write_serializes_shared_state_once_and_reuses_preferences(self):
        extras = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        start = extras.index('String _goldEncode()')
        end = extras.index('void _goldTrimIps()', start)
        persistence = extras[start:end]
        self.assertIn('Future<bool> _goldWrite(SharedPreferences p)', persistence)
        self.assertIn("p.setString('gold_v1', _goldEncode())", persistence)
        save = persistence[persistence.index('Future<void> goldSave()'):]
        self.assertIn('final p = await SharedPreferences.getInstance();', save)
        self.assertIn('await _goldWrite(p);', save)
        self.assertNotIn("await p.setString(", save)


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
        after_scan = body.index('if (!cancelled && open)', scan)
        persist = body.index('await goldMergeIps(', after_scan)
        self.assertLess(wait, before_scan)
        self.assertLess(before_scan, scan)
        self.assertLess(scan, after_scan)
        self.assertLess(after_scan, persist)
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
        persist_guard = body.index('if (!cancelled && open)', scan)
        persist = body.index('await goldMergeIps(', persist_guard)
        abort = body.index('shouldAbort: () => cancelled || !open,', persist)
        self.assertLess(close, close_pop)
        self.assertLess(completion, completion_cancel)
        self.assertLess(scan, stop)
        self.assertLess(stop, persist_guard)
        self.assertLess(persist_guard, persist)
        self.assertLess(persist, abort)

    def test_gold_merge_ips_checks_abort_after_preferences_before_cache_mutation(self):
        source = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> goldMergeIps(')
        end = source.index('\nFuture<Map<String, int?>> _goldProbe', start)
        body = source[start:end]
        load = body.index('await goldLoad();')
        prefs = body.index('await SharedPreferences.getInstance();')
        abort = body.index('if (shouldAbort?.call() ?? false) return;', prefs)
        mutation = body.index('_goldIps[c.ip] =')
        write = body.index('await _goldWrite(p);')
        self.assertLess(load, prefs)
        self.assertLess(prefs, abort)
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
        prefs = helper.index('await SharedPreferences.getInstance();')
        last_abort = helper.index('if (shouldAbort?.call() ?? false) return false;', prefs)
        mutation = helper.index('_goldDns[h.ip] = h.avgMs;')
        write = helper.index('return await _goldWrite(p);')
        self.assertLess(prefs, last_abort)
        self.assertLess(last_abort, mutation)
        self.assertLess(mutation, write)
        sheet = dns[dns.index('void dnsxSheet('):]
        scan = sheet.index('r = await dnsxScan(')
        guard = sheet.index('if (stopFlag || !sheetOpen)', scan)
        save = sheet.index('goldAddDns(r, shouldAbort: () => stopFlag || !sheetOpen)', guard)
        self.assertLess(scan, guard)
        self.assertLess(guard, save)


    def test_network_diagnosis_discards_evidence_when_interface_changes_mid_probe(self):
        source = (ROOT / 'lib' / 'national_engine.dart').read_text(encoding='utf-8')
        diagnosis_start = source.index('class NatNetworkDiagnosis')
        pilot_start = source.index('class PilotNetworkProbe')
        diagnosis = source[diagnosis_start:pilot_start]
        identity = diagnosis.index('final id = await _identityHash();')
        probes = diagnosis.index('final domesticF = Future.wait', identity)
        recheck = diagnosis.index('final identityAfterProbe = await _identityHash();', probes)
        classify = diagnosis.index('current = ev.classify();', recheck)
        self.assertLess(identity, probes)
        self.assertLess(probes, recheck)
        self.assertLess(recheck, classify)
        self.assertIn('if (identityAfterProbe != id)', diagnosis)
        self.assertIn('_checkedAt = null;', diagnosis)
        self.assertIn('_identityAtCheck = null;', diagnosis)

        pilot = source[pilot_start:source.index('String natNetworkClassLabel', pilot_start)]
        identity = pilot.index('final identity = await _networkIdentity();')
        domestic = pilot.index('final domestic = await domesticFuture;', identity)
        recheck = pilot.index('final identityAfterProbe = await _networkIdentity();', domestic)
        publish = pilot.index('_last = NetworkEvidence(', recheck)
        self.assertLess(identity, domestic)
        self.assertLess(domestic, recheck)
        self.assertLess(recheck, publish)
        self.assertIn('if (identityAfterProbe != identity)', pilot)
        self.assertIn('_lastAt = null;', pilot)
        self.assertIn('_lastIdentity = null;', pilot)
        self.assertIn('identity.isNotEmpty && lastAt != null', pilot)
        self.assertIn('_lastAt = identity.isNotEmpty ? DateTime.now() : null;', pilot)
        self.assertIn('id.isNotEmpty && at != null', diagnosis)
        self.assertIn('_checkedAt = id.isNotEmpty ? DateTime.now() : null;', diagnosis)
        self.assertIn('_checkedAt = null;', diagnosis[diagnosis.index('} catch (e, st)'):])
        identity_method = diagnosis[diagnosis.index('static Future<String> _identityHash()'):diagnosis.index('static Future<bool> _tcpOk')]
        self.assertIn('if (parts.isEmpty) return \'\';', identity_method)
        self.assertIn('$natOpKey|', identity_method)
        pilot_identity = pilot[pilot.index('static Future<String> _networkIdentity()'):]
        self.assertIn('if (values.isEmpty) return \'\';', pilot_identity)
        self.assertIn('$natOpKey|', pilot_identity)


    def test_stable_tunnel_evidence_is_discarded_after_network_mode_switch(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = source.index('Future<bool> _stableTunnelTrafficOk(Server server)')
        end = source.index('// FIX #107:', start)
        body = source[start:end]
        snapshot = body.index('final modeSnapshot = nationalMode;')
        probes = body.index('final results = await Future.wait(', snapshot)
        mode_guard = body.index('nationalMode == modeSnapshot', probes)
        passed = body.index('passed >= 2', mode_guard)
        self.assertLess(snapshot, probes)
        self.assertLess(probes, mode_guard)
        self.assertLess(mode_guard, passed)


    def test_route_blocking_is_not_misreported_as_dns_poisoning(self):
        source = (ROOT / 'lib' / 'national_engine.dart').read_text(encoding='utf-8')
        start = source.index('class NatNetworkDiagnosis')
        end = source.index('class PilotNetworkProbe', start)
        diagnosis = source[start:end]
        self.assertIn('A public DNS answer combined with failed TCP/443 does NOT prove', diagnosis)
        self.assertNotIn('poison = reach.isNotEmpty', diagnosis)
        self.assertNotIn('dnsPoisonSuspected: poison', diagnosis)
        self.assertNotIn('poison=$poison', diagnosis)
        self.assertIn('globalDnsOk: globalDnsOk', diagnosis)
        self.assertIn('globalTcpOk: globalTcpOk', diagnosis)


    def test_nnie_history_retries_failed_preferences_load_and_serializes_saves(self):
        source = (ROOT / 'lib' / 'national_engine.dart').read_text(encoding='utf-8')
        start = source.index('class NationalNetworkIntelligence')
        end = source.index('/// Multi-source reachability check', start)
        body = source[start:end]
        self.assertIn('var preferencesAvailable = false;', body)
        self.assertIn('_loaded = preferencesAvailable;', body)
        self.assertIn('static Future<void> _saveQueue = Future<void>.value();', body)
        self.assertIn('final next = _saveQueue.then((_) => _saveImpl());', body)
        self.assertIn('static Future<void> _saveImpl() async', body)


    def test_native_vpn_protects_core_sockets_not_the_tun_descriptor(self):
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        self.assertNotIn('protect((int) fd.getFd())', service)
        listener = service[service.index('public boolean onProtect(int socket)'):]
        self.assertIn('return protect(socket);', listener)
        self.assertIn('The TUN descriptor is not a socket', service)


    def test_background_alive_channel_only_disables_on_missing_plugin(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = source.index("await bgChannel.invokeMethod<bool>('alive')")
        end = source.index('if (alive == false', start)
        body = source[start:end]
        self.assertIn('if (e is MissingPluginException)', body)
        self.assertIn('_bgAliveUnsupported = true;', body)
        self.assertIn("_swl('_startWatch#alive', e);", body)


    def test_native_watchdog_stops_after_mode_specific_probe_quorum(self):
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = service.index('private ProbeResult probeResult(boolean modeSnapshot)')
        end = service.index('private ProbeResult probeOne(String url)', start)
        body = service[start:end]
        self.assertIn('int required = modeSnapshot ? 2 : 1;', body)
        self.assertIn('if (nationalMode != modeSnapshot) return ProbeResult.INCONCLUSIVE;', body)
        self.assertIn('if (passed >= required) return ProbeResult.OK;', body)
        self.assertLess(body.index('nationalMode != modeSnapshot'), body.index('probeOne(u)'))


    def test_cancelled_connect_discards_provisional_nat_variant(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = source.index('Future<bool> _connectLoop(List<Server> list')
        end = source.index('// REAL speed test right after connecting', start)
        body = source[start:end]
        self.assertIn('if (abort) { natVarCandidateDiscard(s); return false; }', body)
        self.assertIn('if (abort || !wantVpn) { natVarCandidateDiscard(s); return false; }', body)
        self.assertGreaterEqual(body.count('natVarCandidateDiscard(s);'), 8)


    def test_operator_change_invalidates_provisional_nat_variant_candidates(self):
        source = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        start = source.index('if (k != natOpKey)')
        end = source.index('final Map<String, int> natWins', start)
        body = source[start:end]
        self.assertIn('natOpKey = k;', body)
        self.assertIn('natVarCandidates.clear();', body)


    def test_unsupported_config_discards_provisional_nat_variant(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = source.index('Future<bool> _connectLoop(List<Server> list')
        end = source.index('// REAL speed test right after connecting', start)
        body = source[start:end]
        bad_cfg = body.index('if (badCfg != null)')
        discard = body.index('natVarCandidateDiscard(s);', bad_cfg)
        skip = body.index('continue;', bad_cfg)
        self.assertLess(discard, skip)

    def test_tunnel_health_probes_reject_redirects_and_non_success_pages(self):
        dart = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        native = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        self.assertIn('req.followRedirects = false;', dart)
        self.assertIn('return expects204 ? code == HttpStatus.noContent : code >= 200 && code < 300;', dart)
        self.assertIn('if (expects204 ? code != HttpStatus.noContent : code < 200 || code >= 300)', dart)
        self.assertIn('request.followRedirects = false;', dart)
        nat_open_start = dart.index('Future<bool> _natOpen(String url)')
        nat_open_end = dart.index('Future<void> _natDetect()', nat_open_start)
        nat_open = dart[nat_open_start:nat_open_end]
        self.assertIn('req.followRedirects = false;', nat_open)
        self.assertIn('return expects204 ? code == HttpStatus.noContent : code >= 200 && code < 300;', nat_open)
        self.assertIn('c.setInstanceFollowRedirects(false);', native)
        self.assertIn('url.endsWith("/generate_204")', native)
        self.assertIn('code < 300', native)
        self.assertNotIn('code < 500', native)
        helper_start = dart.index('Future<bool> _tunnelEndpointOpens(String url)')
        helper_end = dart.index('// TUNCHK:', helper_start)
        helper = dart[helper_start:helper_end]
        self.assertIn('if (await _tunInterfaceObserved())', helper)
        self.assertIn('return _siteOpens(url, viaCore: false);', helper)
        self.assertLess(helper.index('if (await _tunInterfaceObserved())'),
                        helper.index('return _siteOpens(url, viaCore: false);'))
        self.assertIn('bool _isTunnelInterfaceName(String name)', dart)
        ping_start = dart.index('Future<int?> pingProxy(')
        ping_end = dart.index('Future<int?> pingAny(', ping_start)
        ping = dart[ping_start:ping_end]
        self.assertIn('if (!await _tunInterfaceObserved())', ping)
        self.assertIn("lastPingErr = 'VPN TUN interface not observed';", ping)
        start_impl = dart.index('Future<bool> _startImpl(Server s,')
        start_end = dart.index('bool _listPartial = false;', start_impl)
        start_code = dart[start_impl:start_end]
        self.assertIn("lastFail = 'اندروید رابط VPN را نساخت یا قابل مشاهده نیست';", start_code)
        self.assertIn('lastStartNoTunnel = true;', start_code)
        self.assertIn('final results = await Future.wait(urls.map((url) =>', dart[dart.index('Future<bool> _tunnelTrafficOk()'):dart.index('Future<bool> _stableTunnelTrafficOk')])

    def test_ip_auto_scan_persists_unverified_core_candidates_before_advancing_cursor(self):
        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        self.assertIn("const String _ipAutoPendingKey = 'ipauto_pending_core_v1';", source)
        self.assertIn("const String _ipAutoStateKey = 'ipauto_state_v1';", source)
        self.assertIn("'version': 1,", source)
        self.assertIn("final committed = await p.setString(stateKey, jsonEncode(checkpoint));", source)
        self.assertIn("if (!committed) return false;", source)
        self.assertIn("if (_ipAutoLoadedNat == null || _ipAutoLoadedNat != saveNationalMode) return false;", source)
        self.assertIn('final List<String> ipAutoPendingCore = [];', source)
        self.assertIn('.where(_ipAutoValidPending)', source)
        self.assertIn('rawPosition.isFinite && rawPosition >= 0', source)
        self.assertIn('value.isFinite && value >= 0', source)
        save_start = source.index('Future<bool> _ipAutoSave()')
        save_end = source.index('/// خودکار فقط IPهای دقیق', save_start)
        save = source[save_start:save_end]
        self.assertLess(save.index('await p.setString(pendingKey, pending.join'), save.index('await p.setString(posKey, position.toString())'))
        run_start = source.index('Future<bool> _ipAutoRunOnce(')
        run_end = source.index('Future<void> ipAutoSheet', run_start)
        run = source[run_start:run_end]
        self.assertIn('...ipAutoPendingCore.where((x) => !seen.contains(x))', run)
        self.assertIn('final remainingCandidates = queued.skip(toTest.length).toList();', run)
        self.assertIn('..addAll(remainingCandidates);', run)
        self.assertIn('final drainingPending = ipAutoPendingCore.isNotEmpty;', run)
        self.assertIn('if (drainingPending) break;', run)
        self.assertIn('if (!drainingPending)', run)
        self.assertIn('if (_ipAutoLoadedNat != runNationalMode)', run)
        background_start = source.index('Future<void> ipAutoBackground()')
        background_end = source.index('/// دلیل رد شدن شروع اسکن', background_start)
        background = source[background_start:background_end]
        self.assertIn('ipAutoHits.isEmpty || ipAutoPendingCore.isNotEmpty', background)
        self.assertIn('final saved = await _ipAutoSave();', background)
        self.assertLess(background.index('final saved = await _ipAutoSave();'), background.index('await p.setString(_ipAutoAtKey, now.toString())'))
        self.assertIn('if (saved && !_ipAutoHalt(modeSnapshot: runNationalMode))', background)


    def test_opening_ip_auto_sheet_does_not_reload_state_during_active_scan(self):
        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        loader_start = source.index('Future<void> ipAutoLoad({bool skipIfBusy = false})')
        loader_end = source.index('Future<bool> _ipAutoSave()', loader_start)
        loader = source[loader_start:loader_end]
        self.assertIn('if (skipIfBusy && ipAutoBusy) return;', loader)
        self.assertIn('if ((skipIfBusy && ipAutoBusy) || nationalMode != loadNationalMode) return;', loader)
        sheet_start = source.index('Future<void> ipAutoSheet(BuildContext ctx0)')
        sheet = source[sheet_start:]
        self.assertIn('await ipAutoLoad(skipIfBusy: true);', sheet)
        start = sheet[sheet.index('Future<void> start() async {'):]
        load = start.index('await ipAutoLoad(skipIfBusy: true);')
        lock = start.index('ipAutoBusy = true;')
        run = start.index('await _ipAutoRunOnce(')
        self.assertLess(load, lock)
        self.assertLess(lock, run)
        self.assertIn('final retryWhy = _ipAutoRefusal();', start)
        self.assertIn('nationalMode != runNationalMode', start)
        self.assertNotIn('await ipAutoLoad();', start)


    def test_background_network_scans_are_scheduled_sequentially_and_stop_for_vpn(self):
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = main.index('Future<void> _runBackgroundNetworkScans()')
        end = main.index('void didChangeAppLifecycleState(AppLifecycleState s)', start)
        scheduler = main[start:end]
        dns = scheduler.index('await dnsxAutoPick(')
        ip = scheduler.index('await ipAutoBackground()')
        self.assertLess(dns, ip)
        self.assertIn('stop: () => !_autoNetworkScanAllowed(modeSnapshot)', scheduler)
        self.assertIn('if (!_autoNetworkScanAllowed(modeSnapshot)', scheduler)
        allowed_start = main.index('bool _autoNetworkScanAllowed(bool modeSnapshot)')
        allowed_end = main.index('Future<void> _runBackgroundNetworkScans()', allowed_start)
        allowed = main[allowed_start:allowed_end]
        self.assertIn('!wantVpn', allowed)
        self.assertIn('!connected', allowed)
        self.assertIn("lastState != 'CONNECTED'", allowed)
        self.assertIn("lastState != 'CONNECTING'", allowed)
        self.assertIn('!searching', allowed)
        self.assertIn('warm == null', allowed)
        self.assertIn('!_resBusy', allowed)
        self.assertIn('!_hotBusy', allowed)
        self.assertIn('!upBusy', allowed)
        self.assertIn('!_natKeepOn', allowed)
        self.assertIn('Timer.periodic(const Duration(minutes: 15)', main)
        self.assertIn('_runBackgroundNetworkScans()', main[main.index('void didChangeAppLifecycleState(AppLifecycleState s)'):])
        self.assertIn('_networkAutoScanPeriodicTimer?.cancel()', main)

        source = (ROOT / 'lib' / 'ip_auto_scan.dart').read_text(encoding='utf-8')
        halt_start = source.index('bool _ipAutoHalt(')
        halt_end = source.index('/// دلیل رد شدن شروع اسکن', halt_start)
        halt = source[halt_start:halt_end]
        self.assertIn('wantVpn', halt)
        self.assertIn('searching', halt)
        self.assertIn('abort', halt)
        self.assertIn('!inForeground', halt)
        self.assertIn('_resBusy', halt)
        self.assertIn('_hotBusy', halt)
        self.assertIn('upBusy', halt)
        self.assertIn('_natKeepOn', halt)
        self.assertIn('if (_dnsxAutoBusy)', source)


    def test_native_service_stale_stop_cannot_tear_down_a_newer_start(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        self.assertIn('private volatile int latestStartId = 0;', source)
        stop_app = source[source.index('public void stopFromApp()'):source.index('private static class Srv')]
        self.assertIn('stopStartId = latestStartId;', stop_app)
        self.assertIn('stopEverything(stopStartId)', stop_app)
        start = source[source.index('public int onStartCommand('):source.index('private void submit(')]
        self.assertIn('latestStartId = startId;', start)
        self.assertIn('stopping = false;', start)
        self.assertIn('startFlow(first, backups, attempt, startId)', start)
        stop_start = source.index('private void stopEverything(int expectedStartId)')
        stop_end = source.index('private void closeTun()', stop_start)
        stop = source[stop_start:stop_end]
        self.assertIn('if (expectedStartId != latestStartId) return;', stop)
        self.assertIn('stopSelfResult(expectedStartId);', stop)
        self.assertNotIn('stopSelf();', stop)
        flow_start = source.index('private void startFlow(')
        flow_end = source.index('private void resumeSaved(', flow_start)
        self.assertIn('stopEverything(startId);', source[flow_start:flow_end])
        resume_start = flow_end
        resume_end = source.index('private void requestStop(int startId)', resume_start)
        resume = source[resume_start:resume_end]
        self.assertIn('startId != latestStartId', resume)
        self.assertIn('stopEverything(startId);', resume)


    def test_native_stale_stop_preserves_newer_start_and_stop_request(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        self.assertIn('private final Object startLifecycleLock = new Object();', source)
        self.assertIn('private volatile int latestStopRequestId = -1;', source)
        start = source[source.index('public int onStartCommand('):source.index('private void submit(')]
        self.assertIn('synchronized (startLifecycleLock)', start)
        self.assertIn('latestStartId = startId;', start)
        stop_start = source.index('private void requestStop(int startId)')
        stop_end = source.index('private boolean connectFrom(', stop_start)
        self.assertIn('latestStopRequestId = startId;', source[stop_start:stop_end])
        stop_app = source[source.index('public void stopFromApp()'):source.index('private static class Srv')]
        self.assertIn('synchronized (startLifecycleLock)', stop_app)
        self.assertIn('requestStop(stopStartId);', stop_app)
        revoke = source[source.index('public void onRevoke()'):source.index('public void onDestroy()')]
        self.assertIn('synchronized (startLifecycleLock)', revoke)
        self.assertIn('requestStop(revokeStartId);', revoke)

        cleanup_start = source.index('private void stopEverything(int expectedStartId)')
        cleanup_end = source.index('private void closeTun()', cleanup_start)
        cleanup = source[cleanup_start:cleanup_end]
        self.assertIn('synchronized (startLifecycleLock)', cleanup)
        self.assertIn('if (expectedStartId == latestStartId)', cleanup)
        self.assertIn('latestStopRequestId == expectedStartId', cleanup)
        self.assertIn('stopSelfResult(expectedStartId);', cleanup)
        self.assertIn('if (expectedStartId != latestStartId', cleanup)
        self.assertIn('&& latestStopRequestId == expectedStartId)', cleanup)
        self.assertIn('stopping = false;', cleanup)


    def test_native_start_reset_is_atomic_with_start_id_publication(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source[source.index('public int onStartCommand('):source.index('private void submit(')]
        self.assertIn('String action = intent == null ? null : intent.getAction();', start)
        lifecycle_start = start.index('synchronized (startLifecycleLock)')
        lifecycle_end = start.index('// Keep this method short:', lifecycle_start)
        lifecycle = start[lifecycle_start:lifecycle_end]
        self.assertIn('latestStartId = startId;', lifecycle)
        self.assertIn('if (intent == null || ACTION_START.equals(action))', lifecycle)
        self.assertIn('stopping = false;', lifecycle)
        self.assertIn('userStopped = false;', lifecycle)
        # No later reset may erase a concurrent stop request after the lock is released.
        remainder = start[lifecycle_end:]
        self.assertNotIn('stopping = false;', remainder)
        self.assertNotIn('userStopped = false;', remainder)


    def test_native_recovery_checkpoint_is_committed_before_process_kill(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        save_start = source.index('private void saveState()')
        save_end = source.index('private boolean loadState()', save_start)
        save = source[save_start:save_end]
        self.assertIn('.commit();', save)
        self.assertNotIn('.apply();', save)

        clear_start = source.index('private void clearState()')
        clear_end = source.index('private int getScore(', clear_start)
        clear = source[clear_start:clear_end]
        self.assertIn('.clear().commit();', clear)
        self.assertNotIn('.clear().apply();', clear)

        recovery_start = source.index('private void recoverWedgedCore(')
        recovery_end = source.index('private boolean stopCoreNow()', recovery_start)
        recovery = source[recovery_start:recovery_end]
        self.assertIn('synchronized (startLifecycleLock)', recovery)
        self.assertLess(recovery.index('clearState()'), recovery.index('Process.killProcess('))
        self.assertLess(recovery.index('saveState()'), recovery.index('Process.killProcess('))

        stop_start = source.index('private void requestStop(int startId)')
        stop_end = source.index('private boolean connectFrom(', stop_start)
        stop = source[stop_start:stop_end]
        self.assertIn('synchronized (startLifecycleLock)', stop)
        self.assertIn('latestStopRequestId = startId;', stop)



    def test_native_start_waits_for_stop_worker_before_state_probe(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private boolean awaitCoreStopped(')
        end = source.index('private boolean bringUp(', start)
        wait = source[start:end]
        self.assertLess(wait.index('while (coreStopping)'),
                        wait.index('readCoreRunningWithWatchdog(core, "start-preflight")'))
        self.assertIn('previous core stop did not finish before startup deadline', wait)

    def test_native_state_probe_does_not_overlap_an_active_stop_core_call(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private Boolean readCoreRunningWithWatchdog(')
        end = source.index('private boolean stopCoreNow()', start)
        probe = source[start:end]
        self.assertIn('if (!coreLock.tryLock()) return null;', probe)
        self.assertIn('if (coreStopping) return null;', probe)
        self.assertLess(probe.index('if (!coreLock.tryLock())'),
                        probe.index('if (coreStopping)'))
        self.assertLess(probe.index('if (coreStopping)'),
                        probe.index('if (!beginNative(operation))'))

    def test_native_stop_thread_construction_is_inside_failure_guard(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private boolean stopCoreNow()')
        end = source.index('private boolean awaitCoreStopped(', start)
        stop = source[start:end]
        thread_decl = stop.index('Thread t;')
        guarded_start = stop.index('try {', thread_decl)
        construction = stop.index('t = new Thread(() -> {', guarded_start)
        launch = stop.index('if (!beginNative("stopCore"))', construction)
        catch = stop.index('} catch (Throwable startError)', launch)
        self.assertLess(guarded_start, construction)
        self.assertLess(construction, launch)
        self.assertLess(launch, catch)
        recovery = stop[catch:stop.index('try {\n            t.join', catch)]
        self.assertIn('coreStopping = false;', recovery)
        self.assertIn('closeTunAfterCoreStop = true;', recovery)


    def test_native_stop_worker_start_failure_releases_core_fence_and_keeps_tun(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private boolean stopCoreNow()')
        end = source.index('private boolean awaitCoreStopped(', start)
        stop = source[start:end]
        launch = stop.index('if (!beginNative("stopCore"))')
        catch = stop.index('} catch (Throwable startError)', launch)
        recovery = stop[catch:stop.index('try {\n            t.join', catch)]
        self.assertIn('endNative();', recovery)
        self.assertIn('coreStopping = false;', recovery)
        self.assertIn('closeTunAfterCoreStop = true;', recovery)
        self.assertIn('return false;', recovery)
        self.assertLess(recovery.index('endNative();'), recovery.index('coreStopping = false;'))


    def test_native_stop_watchdog_covers_post_stop_state_verification(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private boolean stopCoreNow()')
        end = source.index('private boolean awaitCoreStopped(', start)
        body = source[start:end]
        thread_start = body.index('t = new Thread(() -> {')
        thread_end = body.index('}, "KingVpnCoreStop");', thread_start)
        worker = body[thread_start:thread_end]
        self.assertIn('core.stopCore();', worker)
        self.assertIn('stillRunning = core.isV2rayCoreRunning();', worker)
        self.assertIn('finally {\n                // Do not publish coreStopping=false', worker)
        self.assertLess(worker.index('core.stopCore();'), worker.index('stillRunning = core.isV2rayCoreRunning();'))
        self.assertLess(worker.index('stillRunning = core.isV2rayCoreRunning();'), worker.index('endNative();'))
        self.assertLess(worker.index('endNative();'), worker.index('coreStopping = false;'))
        self.assertIn('stopVerified[0] = verified;', worker)


    def test_native_new_start_waits_for_previous_async_core_stop(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        helper_start = source.index('private boolean awaitCoreStopped(')
        helper_end = source.index('private boolean bringUp(', helper_start)
        helper = source[helper_start:helper_end]
        self.assertIn('while (coreStopping)', helper)
        self.assertIn('Thread.sleep(50L)', helper)
        self.assertIn('BRING_UP_TIMEOUT_MS', helper)
        self.assertIn('if (!isCurrent(myAttempt)) return false;', helper)
        self.assertIn('if (!coreStopping && running) stopCoreNow();', helper)
        self.assertIn('readCoreRunningWithWatchdog(core, "start-final-state-check")', helper)

        start = source.index('private boolean bringUp(Srv s, int myAttempt)')
        end = source.index('private void startWatchdog(', start)
        bring_up = source[start:end]
        self.assertIn('if (!awaitCoreStopped(core, myAttempt)) return false;', bring_up)
        self.assertNotIn('if (coreStopping || core.isV2rayCoreRunning())', bring_up)


    def test_sticky_restart_invalid_state_releases_foreground_service(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        resume_start = source.index('private void resumeSaved(int startId)')
        resume_end = source.index('private void requestStop(int startId)', resume_start)
        resume = source[resume_start:resume_end]
        invalid = resume[resume.index('if (!loadState())'):resume.index('startForegroundSafe(')]
        self.assertIn('stopEverything(startId);', invalid)
        self.assertNotIn('stopSelfResult(startId);', invalid)

        cleanup_start = source.index('private void stopEverything(int expectedStartId)')
        cleanup_end = source.index('private void closeTun()', cleanup_start)
        cleanup = source[cleanup_start:cleanup_end]
        self.assertIn('clearState();', cleanup)
        self.assertIn('stopForeground(true);', cleanup)
        self.assertIn('stopSelfResult(expectedStartId);', cleanup)


    def test_native_hang_watchdog_cannot_kill_after_native_call_returns(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        self.assertIn('private final Object nativeLock = new Object();', source)

        begin_start = source.index('private boolean beginNative(')
        begin_end = source.index('private void endNative()', begin_start)
        begin = source[begin_start:begin_end]
        self.assertIn('synchronized (nativeLock)', begin)
        self.assertIn('nativeBusy = true;', begin)
        self.assertIn('recoverWedgedCore(what, token);', begin)

        end_start = source.index('private void endNative()')
        end_end = source.index('private void recoverWedgedCore(', end_start)
        end = source[end_start:end_end]
        self.assertIn('synchronized (nativeLock)', end)
        self.assertIn('nativeBusy = false;', end)
        self.assertIn('nativeToken.incrementAndGet();', end)

        recovery_start = source.index('private void recoverWedgedCore(String what, long expectedToken)')
        recovery_end = source.index('private boolean stopCoreNow()', recovery_start)
        recovery = source[recovery_start:recovery_end]
        self.assertIn('synchronized (nativeLock)', recovery)
        self.assertIn('if (!nativeBusy || nativeToken.get() != expectedToken) return;', recovery)
        self.assertLess(recovery.index('nativeToken.get() != expectedToken'),
                        recovery.index('recovering.compareAndSet(false, true)'))


    def test_sticky_state_loader_filters_empty_or_invalid_server_entries(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private boolean loadState()')
        end = source.index('private void clearState()', start)
        loader = source[start:end]
        self.assertIn('JSONObject o = arr.optJSONObject(i);', loader)
        self.assertIn('if (o == null) continue;', loader)
        self.assertIn('String config = o.optString("config", "").trim();', loader)
        self.assertIn('if (config.isEmpty()) continue;', loader)
        self.assertIn('if (servers.isEmpty()) return false;', loader)
        self.assertIn('Math.min(sp.getInt("idx", 0), servers.size() - 1)', loader)


    def test_native_stop_waiter_uses_worker_verification_without_unwatched_jni(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private boolean stopCoreNow()')
        end = source.index('private boolean awaitCoreStopped(', start)
        stop = source[start:end]
        self.assertIn('final boolean[] stopVerified = {false};', stop)
        self.assertIn('verified = !stillRunning;', stop)
        self.assertIn('stopVerified[0] = verified;', stop)
        self.assertLess(stop.index('endNative();'), stop.index('stopVerified[0] = verified;'))
        join = stop.index('t.join(STOP_CORE_WAIT_MS);')
        waiter = stop[join:]
        self.assertIn('if (!stopVerified[0])', waiter)
        self.assertNotIn('core.isV2rayCoreRunning()', waiter)


    def test_native_vpn_attempt_worker_launch_is_failure_guarded(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private boolean bringUpWithTimeout(Srv s, int expectedStartId)')
        end = source.index('private static void closeQuietly', start)
        body = source[start:end]
        declaration = body.index('Thread attemptThread;')
        guard = body.index('try {', declaration)
        construction = body.index('attemptThread = new Thread(() -> {', guard)
        launch = body.index('attemptThread.start();', construction)
        catch = body.index('} catch (Throwable launchError)', launch)
        self.assertLess(guard, construction)
        self.assertLess(construction, launch)
        self.assertLess(launch, catch)
        recovery = body[catch:body.index('synchronized (waitLock)', catch)]
        self.assertIn('lastError = "could not launch VPN attempt worker:', recovery)
        self.assertIn('return false;', recovery)


    def test_native_final_cleanup_fallback_thread_launch_is_failure_guarded(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private void runFallback(Runnable r)')
        end = source.index('private void startFlow(', start)
        fallback = source[start:end]
        self.assertIn('new Thread(r, "KingVpnService-fallback")', fallback)
        self.assertIn('t.setDaemon(true);', fallback)
        self.assertIn('t.start();', fallback)
        self.assertIn('catch (Throwable launchError)', fallback)
        self.assertIn('could not launch VPN cleanup fallback:', fallback)
        self.assertIn('Log.e(TAG, lastError, launchError);', fallback)


    def test_native_core_calls_are_refused_when_watchdog_cannot_start(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        begin = source[source.index('private boolean beginNative('):source.index('private void endNative()')]
        self.assertIn('catch (Throwable launchError)', begin)
        self.assertIn('nativeBusy = false;', begin)
        self.assertIn('nativeToken.incrementAndGet();', begin)
        self.assertIn('return false;', begin)

        stop_start = source.index('private boolean stopCoreNow()')
        stop_end = source.index('private boolean awaitCoreStopped(', stop_start)
        stop = source[stop_start:stop_end]
        self.assertIn('if (!beginNative("stopCore"))', stop)
        self.assertIn('native watchdog unavailable', stop)

        bring_start = source.index('private boolean bringUp(Srv s, int myAttempt)')
        bring_end = source.index('private void startWatchdog(', bring_start)
        bring = source[bring_start:bring_end]
        self.assertIn('if (!beginNative("startCore"))', bring)
        self.assertIn('refusing unmonitored core start', bring)


    def test_every_native_core_state_query_requires_watchdog(self):
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        helper_start = service.index('private Boolean readCoreRunningWithWatchdog(')
        helper_end = service.index('private boolean stopCoreNow()', helper_start)
        helper = service[helper_start:helper_end]
        self.assertIn('if (!coreLock.tryLock()) return null;', helper)
        self.assertIn('if (!beginNative(operation))', helper)
        self.assertIn('coreLock.unlock();', helper)
        self.assertIn('return core.isV2rayCoreRunning();', helper)
        self.assertIn('finally {\n                endNative();\n            }', helper)

        stop_start = service.index('private boolean stopCoreNow()')
        stop_end = service.index('private boolean awaitCoreStopped(', stop_start)
        stop = service[stop_start:stop_end]
        await_start = service.index('private boolean awaitCoreStopped(')
        await_end = service.index('private boolean bringUp(', await_start)
        await_body = service[await_start:await_end]
        check_start = service.index('private void checkOnce()')
        check_end = service.index('private void rescheduleNormal()', check_start)
        check = service[check_start:check_end]
        self.assertIn('readCoreRunningWithWatchdog(core, "stopCore-preflight")', stop)
        self.assertIn('readCoreRunningWithWatchdog(core, "start-preflight")', await_body)
        self.assertIn('readCoreRunningWithWatchdog(core, "start-final-state-check")', await_body)
        self.assertIn('readCoreRunningWithWatchdog(core, "health-watchdog-state")', check)


    def test_native_health_probe_discards_results_from_superseded_core_attempt(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private void checkOnce()')
        end = source.index('private void rescheduleNormal()', start)
        check = source[start:end]
        snapshot = check.index('final int healthAttempt = attemptSeq.get();')
        native_read = check.index('readCoreRunningWithWatchdog(core, "health-watchdog-state")')
        probe = check.index('ProbeResult pr = coreUp ? probeResult(modeSnapshot) : ProbeResult.HARD_FAIL;')
        guard = check.index('if (attemptSeq.get() != healthAttempt)')
        self.assertLess(snapshot, native_read)
        self.assertLess(native_read, probe)
        self.assertLess(probe, guard)
        stale = check[guard:check.index('if (nationalMode != modeSnapshot)', guard)]
        self.assertIn('rescheduleNormal();', stale)
        self.assertIn('return;', stale)


    def test_tls_diagnostics_do_not_accept_invalid_certificates(self):
        scanners = (ROOT / 'lib' / 'auto_scanners.dart').read_text(encoding='utf-8')
        diagnostics = (ROOT / 'lib' / 'net_diag.dart').read_text(encoding='utf-8')
        sni_start = scanners.index('Future<int?> _autoSniOk(')
        alpn_start = scanners.index('Future<String?> _autoAlpnOk(', sni_start)
        port_start = scanners.index('Future<bool> _autoPortOk(', alpn_start)
        for body in (scanners[sni_start:alpn_start], scanners[alpn_start:port_start]):
            self.assertNotIn('onBadCertificate', body)
        tls_start = diagnostics.index('Future<_DiagItem> _diagTls(')
        tls_end = diagnostics.index('Future<String> netDiagnose()', tls_start)
        self.assertNotIn('onBadCertificate', diagnostics[tls_start:tls_end])



    def test_tls_scanners_and_nat_variants_preserve_certificate_validation(self):
        nip = (ROOT / 'lib' / 'nip_scan.dart').read_text(encoding='utf-8')
        npv = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        ultra = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        self.assertNotIn('onBadCertificate: (_) => true', nip)
        self.assertNotIn('onBadCertificate: (_) => true', npv)
        self.assertNotIn('onBadCertificate: (_) => true', main)
        self.assertIn("tls['allowInsecure'] = false;", ultra)
        self.assertNotIn("tls['allowInsecure'] = true;", ultra)



    def test_native_hang_recovery_does_not_restore_checkpoint_during_teardown(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private void recoverWedgedCore(String what, long expectedToken)')
        end = source.index('private Boolean readCoreRunningWithWatchdog(', start)
        recovery = source[start:end]
        self.assertIn('if (userStopped || stopping) clearState();', recovery)
        self.assertIn('else saveState();', recovery)



    def test_subscription_urls_require_https_and_have_bounded_non_redirecting_reads(self):
        extras = (ROOT / 'lib' / 'iran_ai_extras.dart').read_text(encoding='utf-8')
        groups = (ROOT / 'lib' / 'sub_groups.dart').read_text(encoding='utf-8')
        start = extras.index('Future<List<Server>> fetchSubscription(String url)')
        end = extras.index('// ======================= بخش‌های رابط', start)
        fetch = extras[start:end]
        self.assertIn("uri.scheme != 'https'", fetch)
        self.assertIn('uri.userInfo.isNotEmpty', fetch)
        self.assertIn('followRedirects = false', fetch)
        self.assertIn('streamed.statusCode != 200', fetch)
        self.assertIn('2 * 1024 * 1024', fetch)
        self.assertIn('streamed.stream', fetch)
        self.assertIn('.timeout(const Duration(seconds: 20))', fetch)
        self.assertIn("uri.scheme != 'https'", groups)
        self.assertNotIn("startsWith('http://')", groups)

    def test_operator_asn_lookups_require_https_and_do_not_follow_redirects(self):
        source = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        start = source.index('Future<String?> _natAsnFrom(')
        end = source.index('Future<void> natDetectOperator()', start)
        lookup = source[start:end]
        self.assertIn("uri.scheme != 'https'", lookup)
        self.assertIn('req.followRedirects = false;', lookup)
        self.assertIn('maxAsnResponseBytes = 256 * 1024', lookup)
        self.assertIn('res.timeout(const Duration(seconds: 3))', lookup)
        self.assertIn('responseBytes.length + chunk.length', lookup)
        self.assertNotIn('transform(utf8.decoder).join()', lookup)
        self.assertNotIn('http://ip-api.com', source)



    def test_process_exit_diagnostics_do_not_skip_records_after_display_limit(self):
        source = (ROOT / 'android_src' / 'KingDiag.java').read_text(encoding='utf-8')
        start = source.index('public static String lastExits(Context ctx)')
        end = source.index('private static void nativeHints(', start)
        body = source[start:end]
        self.assertIn('Collections.sort(ordered', body)
        self.assertIn('if (shown >= 5) break;', body)
        self.assertIn('processedThrough = ts;', body)
        self.assertIn('writeSeen(app, processedThrough)', body)
        self.assertNotIn('if (shown >= 5) continue;', body)
        self.assertNotIn('newest > seen', body)


    def test_conversation_memory_retries_after_transient_secure_storage_read_failure(self):
        source = (ROOT / 'lib' / 'king_local_ai.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> _loadConversationMemory() async {')
        end = source.index('Future<void> _saveConversationMemory()', start)
        loader = source[start:end]
        read = loader.index('encoded = await _secure.read(key: _conversationMemoryKey);')
        retry_return = loader.index('return;', read)
        loaded = loader.index('_conversationMemoryLoaded = true;', read)
        self.assertLess(read, retry_return)
        self.assertLess(retry_return, loaded)
        self.assertIn('transient secure-storage failure', loader)
        self.assertIn('if (_conversationMemoryLoaded) return;', loader)


    def test_owner_auth_cancellation_precedes_persistent_auth_state_mutation(self):
        source = (ROOT / 'lib' / 'king_ai_owner_auth.dart').read_text(encoding='utf-8')
        start = source.index('Future<bool> authenticate(String password) async {')
        end = source.index('void lock()', start)
        auth = source[start:end]
        derived = auth.index('final actual = await _derive(password, salt);')
        cancelled = auth.index('if (sessionGeneration != _sessionGeneration) return false;', derived)
        success_cleanup = auth.index("await _storage.delete(key: _failuresKey);", derived)
        failure_counter = auth.index("await _storage.write(key: _failuresKey, value: failures.toString());", derived)
        self.assertLess(derived, cancelled)
        self.assertLess(cancelled, success_cleanup)
        self.assertLess(cancelled, failure_counter)
        failure_read = auth.index("await _storage.read(key: _failuresKey)", cancelled)
        failure_read_guard = auth.index("if (sessionGeneration != _sessionGeneration) return false;", failure_read)
        failure_write = auth.index("await _storage.write(key: _failuresKey", failure_read)
        self.assertLess(failure_read, failure_read_guard)
        self.assertLess(failure_read_guard, failure_write)
        failure_write_guard = auth.index("if (sessionGeneration != _sessionGeneration) return false;", failure_write)
        lock_write = auth.index("await _storage.write(key: _lockUntilKey", failure_write)
        self.assertLess(failure_write, failure_write_guard)
        self.assertLess(failure_write_guard, lock_write)
        success_delete_guard = auth.index("if (sessionGeneration != _sessionGeneration) return false;", success_cleanup)
        lock_delete = auth.index("await _storage.delete(key: _lockUntilKey);", success_cleanup)
        self.assertLess(success_cleanup, success_delete_guard)
        self.assertLess(success_delete_guard, lock_delete)


    def test_service_capability_probe_respects_live_vpn_quiet_window(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = source.index('Future<int> _svcOf(Server s)')
        end = source.index('String _testCfg(String cfg)', start)
        body = source[start:end]
        self.assertIn('await _waitLiveQuiet();', body)
        self.assertLess(body.index('await _waitLiveQuiet();'),
                        body.index('_delayGate.run'))


    def test_live_quiet_wait_tracks_reconnect_deadline_updates(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> _waitLiveQuiet()')
        end = source.index('Future<int?> _delayOnce', start)
        body = source[start:end]
        loop = body.index('while (connected && wantVpn)')
        deadline = body.index('final until = _liveQuietUntil;')
        self.assertGreater(deadline, loop)
        self.assertIn('DateTime.now().isBefore(until)', body)


    def test_native_core_lifecycle_fence_is_process_wide(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        self.assertIn('private static final ReentrantLock coreLock = new ReentrantLock();', source)
        self.assertIn('private static volatile boolean coreStopping = false;', source)
        start = source.index('private Boolean readCoreRunningWithWatchdog')
        end = source.index('private boolean stopCoreNow', start)
        body = source[start:end]
        self.assertIn('if (coreStopping) return null;', body)


    def test_stale_connected_probe_cannot_complete_a_replaced_waiter(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        listener = source[source.index('if (st.state == \'CONNECTED\' &&', source.index('downSig!.complete(true);')):]
        listener = listener[:listener.index('// DROPDEFER')]
        self.assertIn('final verifyGeneration = _connGen;', listener)
        self.assertIn('final verifyCompleter = connSig!;', listener)
        self.assertIn('_verifyPendingConnect(verifyCompleter, verifyGeneration)', listener)
        start = source.index('Future<void> _verifyPendingConnect(')
        end = source.index('// [trust] =', start)
        verify = source[start:end]
        self.assertIn('expectedGeneration != _connGen', verify)
        self.assertIn('!identical(connSig, c)', verify)
        self.assertIn('c.isCompleted', verify)
        self.assertLess(verify.index('expectedGeneration != _connGen'),
                        verify.index('_staleCoreMayBeUp = false;'))
        self.assertIn('c.complete(true);', verify)


    def test_nnie_stability_probe_is_bound_to_connection_generation(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = source.index('final nnieGeneration = _connGen;')
        end = source.index('if (mounted) setState(() {});', start)
        arm = source[start:end]
        self.assertIn('nnieGeneration == _connGen', arm)
        self.assertIn('_stableTunnelTrafficOk(s)', arm)
        self.assertIn('stillValid: () =>', arm)
        engine = (ROOT / 'lib' / 'national_engine.dart').read_text(encoding='utf-8')
        stable_start = engine.index('static Future<void> recordStable(')
        stable_end = engine.index('static Future<void> _save()', stable_start)
        stable = engine[stable_start:stable_end]
        self.assertIn('if (stillValid != null && !stillValid()) return;', stable)
        self.assertLess(stable.index('await load();'),
                        stable.index('if (stillValid != null && !stillValid()) return;'))
        self.assertLess(arm.index('final nnieGeneration = _connGen;'),
                        arm.index('NationalNetworkIntelligence.armStable('))


    def test_vpn_establish_fails_closed_when_ipv6_route_cannot_be_installed(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private ParcelFileDescriptor establish(V2rayConfig cfg)')
        end = source.index('/** جدید: wires libv2ray', start)
        body = source[start:end]
        self.assertIn('b.addAddress("fd00:1:fd00:1:fd00:1:fd00:1", 126);', body)
        self.assertIn('b.addRoute("::", 0);', body)
        self.assertIn('b.addRoute("0.0.0.0", 0);', body)
        self.assertLess(body.index('b.addRoute("::", 0);'),
                        body.index('b.addRoute("0.0.0.0", 0);'))
        self.assertNotIn('ipv6 sinkhole not supported', body)
        self.assertNotIn('catch (Exception e)', body[:body.index('} catch (Exception e)')])

    def test_reliable_config_preserves_selected_global_dns_before_fallbacks(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = source.index('String _reliableVpnCfg(String cfg)')
        end = source.index('// completes when the VPN tunnel reports CONNECTED', start)
        body = source[start:end]
        global_block = body[body.index("} else if (secureDns && !ultraMode"):body.index("    // If the profile has no upstream resolver")]
        self.assertIn('final existingList = existing is List ? existing : const <dynamic>[];', global_block)
        self.assertIn('for (final item in [...existingList, ...globalFallbacks])', global_block)
        self.assertIn("d['servers'] = merged;", global_block)
        self.assertNotIn("d['servers'] = <dynamic>[", global_block)

    def test_plugin_tun_inbound_patch_preserves_king_dns_hijack(self):
        patch = (ROOT / 'patch_plugin.py').read_text(encoding='utf-8')
        self.assertIn("utilities = find_java('Utilities.java')", patch)
        self.assertIn('"king-vpn-dns-hijack".equals(rule.optString("ruleTag"))', patch)
        self.assertIn("P1 DNS: preserve King VPN DNS hijack before plugin fallback", patch)

    def test_reliable_config_hijacks_udp_and_tcp_dns_into_xray_builtin_resolver(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = source.index('String _reliableVpnCfg(String cfg)')
        end = source.index('// completes when the VPN tunnel reports CONNECTED', start)
        body = source[start:end]
        self.assertIn("if (j['outbounds'] is! List || (j['outbounds'] as List).isEmpty)", body)
        self.assertIn("uri?.scheme == 'https' || uri?.scheme == 'http'", body)
        self.assertIn("InternetAddress.tryParse(candidate)", body)
        self.assertIn("'rewriteAddress': dnsRewriteAddress", body)
        self.assertIn("'rewritePort': 53", body)
        self.assertIn("'qType': '1,28'", body)
        self.assertIn("'action': 'direct'", body)
        self.assertIn("'protocol': 'dns'", body)
        self.assertIn("'network': 'tcp,udp'", body)
        self.assertIn("'port': '53'", body)
        self.assertIn("'ruleTag': 'king-vpn-dns-hijack'", body)
        self.assertIn("rules.insert(0,", body)
        self.assertIn("d['queryStrategy'] = 'UseIP';", body)
        self.assertIn("for (final fallback in ['1.1.1.1', '8.8.8.8'])", body)
        self.assertIn("globalServers.add(fallback)", body)
        self.assertIn("d['servers'] = globalServers;", body)

    def test_android_uses_synthetic_dns_only_when_xray_hijack_rule_is_present(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private ParcelFileDescriptor establish(V2rayConfig cfg)')
        end = source.index('/** جدید: wires libv2ray', start)
        body = source[start:end]
        guard = body.index('fullConfig.contains(')
        marker = body.index('king-vpn-dns-hijack', guard)
        ipv4 = body.index('b.addDnsServer("26.26.26.2");')
        ipv6 = body.index('b.addDnsServer("fd00:1:fd00:1:fd00:1:fd00:2");')
        self.assertLess(guard, marker)
        self.assertLess(marker, ipv4)
        self.assertLess(ipv4, ipv6)

    def test_ipv4_ipv6_routes_reach_the_active_native_core_and_dns_queries_both_families(self):
        prepare = (ROOT / 'prepare_android.py').read_text(encoding='utf-8')
        activity = (ROOT / 'android_src' / 'MainActivity.kt').read_text(encoding='utf-8')
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')

        # The generated Android manifest registers the custom VpnService, and
        # the actual Flutter start channel targets that service (not the plugin's
        # independent V2rayVPNService implementation).
        self.assertIn('com.kingvpn.king_vpn.KingVpnService', prepare)
        self.assertIn('Intent(this, KingVpnService::class.java)', activity)
        self.assertIn('KingVpnService.ACTION_START', activity)

        # Both address families are installed on the TUN descriptor that is
        # passed directly into the active libv2ray core.
        establish_start = service.index('private ParcelFileDescriptor establish(V2rayConfig cfg)')
        establish_end = service.index('/** جدید: wires libv2ray', establish_start)
        establish = service[establish_start:establish_end]
        self.assertIn('b.addRoute("0.0.0.0", 0);', establish)
        self.assertIn('b.addRoute("::", 0);', establish)
        self.assertIn('b.addAddress("fd00:1:fd00:1:fd00:1:fd00:1", 126);', establish)
        self.assertIn('ok = core.startCore(cfg, fd.getFd());', service)

        # Xray's UseIP DNS strategy requests both A and AAAA records.
        self.assertIn("d['queryStrategy'] = 'UseIP';", main)

    def test_native_core_initialization_failure_remains_retryable(self):
        service = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        wire_start = service.index('private boolean wireCoreOnce()')
        wire_end = service.index('private void cancelPluginNotification()', wire_start)
        wire = service[wire_start:wire_end]
        self.assertIn('if (coreWired) return true;', wire)
        self.assertIn('V2rayCoreManager.getInstance().setUpListener(this);', wire)
        self.assertLess(wire.index('setUpListener(this);'), wire.index('coreWired = true;'))
        self.assertIn('catch (Throwable initError)', wire)
        self.assertIn('coreWired = false;', wire)
        bring_start = service.index('private boolean bringUp(Srv s, int myAttempt)')
        bring_end = service.index('private void startWatchdog(', bring_start)
        bring = service[bring_start:bring_end]
        self.assertIn('if (!wireCoreOnce()) return false;', bring)
        patcher = (ROOT / 'patch_plugin.py').read_text(encoding='utf-8')
        self.assertIn('VPNRACE_INIT_RETHROW', patcher)
        self.assertIn('throw new IllegalStateException("V2Ray core initialization failed", e);', patcher)




    def test_nat_variant_growth_is_unique_and_bounded(self):
        source = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        start = source.index('int natGrow(int n)')
        end = source.index('List<String>? _natNamesC', start)
        grow = source[start:end]
        self.assertIn('if (n <= 0 || _natSpecs.length >= natMaxVariants) return 0;', grow)
        self.assertIn('final target = min(n, natMaxVariants - _natSpecs.length);', grow)
        self.assertIn('Set<String>? _natGrowSignatures;', source)
        self.assertIn('if (!signatures.add(_natSig(spec))) continue;', grow)
        self.assertNotIn('_natSpecs.length > 500000', grow)

    def test_nat_variant_signature_includes_all_socket_dimensions(self):
        source = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        start = source.index('String _natSig(_NatSpec x)')
        end = source.index('_NatSpec _natMk(', start)
        signature = source[start:end]
        # Every _NatSpec field that can alter the generated link or core config
        # must participate in identity; otherwise distinct variants collapse.
        for field in (
            'other', 'fp', 'alpn', 'frag', 'port', 'portIdx', 'clean',
            'cleanIdx', 'mux', 'muxN', 'sniHost', 'v4', 'tfo', 'ed',
            'edN', 'noise', 'noiseK', 'nodelay', 'doh', 'mode', 'keep',
            'mss', 'sniSwap',
        ):
            self.assertIn('${x.' + field + '}', signature, field)

    def test_nat_sni_variant_labels_match_front_sni_indices(self):
        nat = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        nip = (ROOT / 'lib' / 'nip_scan.dart').read_text(encoding='utf-8')
        start = nat.index('// V13: SNI swap variants')
        end = nat.index('];', start)
        variants = nat[start:end]
        self.assertIn("_NatSpec('SNI>cdnjs', sniSwap: 0)", variants)
        self.assertIn("_NatSpec('SNI>cloudflare', sniSwap: 1)", variants)
        self.assertIn("_NatSpec('SNI>speed', sniSwap: 2)", variants)
        self.assertIn("_NatSpec('SNI>divar.ir', sniSwap: 6)", variants)
        self.assertIn("'www.cloudflare.com',      // 1", nip)
        self.assertIn("'speed.cloudflare.com',    // 2", nip)


    def test_user_relay_hosts_are_normalized_deduplicated_and_bounded(self):
        source = (ROOT / 'lib' / 'nip_scan.dart').read_text(encoding='utf-8')
        start = source.index('List<String> _nipNormalizeRelayHosts(')
        end = source.index('Future<String?> nipResolve(', start)
        helper = source[start:end]
        self.assertIn('InternetAddress.tryParse(raw)', helper)
        self.assertIn('final normalized = parsed.address;', helper)
        self.assertIn('if (!seen.add(normalized)) continue;', helper)
        self.assertIn('if (out.length >= 64) break;', helper)
        self.assertIn('_nipNormalizeRelayHosts(', helper)
        self.assertIn("p.setStringList('nat_relay_hosts', natRelayHosts)", helper)

    def test_nip_cidr_expansion_uses_ceiling_step_and_relay_whitespace_regex(self):
        source = (ROOT / 'lib' / 'nip_scan.dart').read_text(encoding='utf-8')
        self.assertIn('final step = size > limit ? (size + limit - 1) ~/ limit : 1;', source)
        self.assertIn("text.split(RegExp(r'[\\r\\n\\s]+'))", source)

    def test_ripe_cidr_sources_are_validated_deduplicated_and_bounded(self):
        source = (ROOT / 'lib' / 'nip_scan.dart').read_text(encoding='utf-8')
        start = source.index('List<String> _nipNormalizeIpv4Cidrs(')
        end = source.index('/// فهرست بلوک‌های IPv4 ایران', start)
        helper = source[start:end]
        self.assertIn('InternetAddress.tryParse(parts[0].trim())', helper)
        self.assertIn('address.type != InternetAddressType.IPv4', helper)
        self.assertIn('prefix < 8', helper)
        self.assertIn('prefix > 32', helper)
        self.assertIn('if (!seen.add(normalized)) continue;', helper)
        self.assertIn('final limit = min(maxEntries, 4096);', helper)
        country = source[source.index('Future<List<String>> nipIranCidrs()'):
                         source.index('/// همان کانفیگ سرور')]
        self.assertIn('_nipNormalizeIpv4Cidrs(raw)', country)
        asn_start = source.index('Future<List<String>> nipAsnPrefixes(String ip)')
        asn_end = source.index('// FRONTSNI', asn_start)
        asn = source[asn_start:asn_end]
        self.assertIn('_nipNormalizeIpv4Cidrs(cached, maxEntries: 2048)', asn)
        self.assertIn('_nipNormalizeIpv4Cidrs(rawPrefixes, maxEntries: 2048)', asn)
        self.assertIn('if (rawPrefixes.length >= 4096) break;', asn)

    def test_nip_tcp_scan_accepts_ipv4_and_ipv6_literals_and_cleans_sockets(self):
        source = (ROOT / 'lib' / 'nip_scan.dart').read_text(encoding='utf-8')
        probe_start = source.index('Future<int?> nipTcpProbe(')
        scan_start = source.index('Future<List<NipHit>> nipScan(', probe_start)
        scan_end = source.index('/// Normalize and bound untrusted IPv4 CIDR lists', scan_start)
        probe = source[probe_start:scan_start]
        scan = source[scan_start:scan_end]
        self.assertIn('InternetAddress.tryParse(ip.trim())', probe)
        self.assertIn('address.type != InternetAddressType.IPv4', probe)
        self.assertIn('address.type != InternetAddressType.IPv6', probe)
        self.assertIn('Socket.connect(address, port, timeout: timeout)', probe)
        self.assertIn('finally {', probe)
        self.assertIn('socket?.destroy();', probe)
        self.assertIn('address.type == InternetAddressType.IPv4', scan)
        self.assertIn('address.type == InternetAddressType.IPv6', scan)
        self.assertIn('v4Candidates', scan)
        self.assertIn('v6Candidates', scan)
        self.assertIn('Interleave address families', scan)
        self.assertIn('seen.add(address.address)', scan)
        self.assertIn('final clock = Stopwatch()..start();', scan)
        self.assertIn('if (aborted() || clock.elapsed >= budget) return;', scan)
        self.assertIn('List<String> nipExpandIpv6Cidr(', source)
        self.assertIn('address.type != InternetAddressType.IPv6', source)
        self.assertIn('InternetAddress.fromRawAddress(Uint8List.fromList(bytes))', source)
        self.assertIn('Socket.connect(address, port, timeout: const Duration(milliseconds: 2000))', source)

    def test_shared_nip_cidr_expander_dispatches_ipv6_without_breaking_ipv4(self):
        source = (ROOT / 'lib' / 'nip_scan.dart').read_text(encoding='utf-8')
        start = source.index('List<String> nipExpandCidr(')
        end = source.index('/// گسترش محدود CIDR برای IPv6', start)
        helper = source[start:end]
        self.assertIn('InternetAddress.tryParse(parts[0].trim())', helper)
        self.assertIn('parsed?.type == InternetAddressType.IPv6', helper)
        self.assertIn('return nipExpandIpv6Cidr(cidr, maxPerBlock: maxPerBlock);', helper)
        self.assertIn('final limit = min(maxPerBlock, 65536);', helper)
        self.assertIn('prefix < 8 || prefix > 32', helper)

    def test_nip_cidr_expansion_bounds_caller_supplied_limit(self):
        source = (ROOT / 'lib' / 'nip_scan.dart').read_text(encoding='utf-8')
        start = source.index('List<String> nipExpandCidr(')
        end = source.index('/// اتصال TCP', start)
        body = source[start:end]
        self.assertIn('if (maxPerBlock <= 0) return const [];', body)
        self.assertIn('final limit = min(maxPerBlock, 65536);', body)
        self.assertIn('final step = size > limit ? (size + limit - 1) ~/ limit : 1;', body)



    def test_dns_probe_and_manual_scanner_accept_ipv4_and_ipv6_resolvers(self):
        core = (ROOT / 'lib' / 'nnie_core.dart').read_text(encoding='utf-8')
        scanner = (ROOT / 'lib' / 'dns_scanner.dart').read_text(encoding='utf-8')
        extras = (ROOT / 'lib' / 'npv_am_extras.dart').read_text(encoding='utf-8')
        self.assertIn('InternetAddress.anyIPv6', core)
        self.assertIn('InternetAddress.anyIPv4', core)
        self.assertIn('queryType = 1', core)
        self.assertIn('queryType: queryType', core)
        self.assertIn('InternetAddressType.IPv6', scanner)
        self.assertIn('2606:4700:4700::1111', scanner)
        self.assertIn('2001:4860:4860::8888', scanner)
        self.assertIn('parsedIp.type == InternetAddressType.IPv6', extras)

    def test_nat_prescan_tries_bounded_ipv4_and_ipv6_answers(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = source.index('Future<void> _natPrescan()')
        end = source.index('Future<void> _natMemoryReuse()', start)
        body = source[start:end]
        self.assertIn('final ipOf = <String, List<String>>{}', body)
        self.assertIn('.map((a) => a.address)', body)
        self.assertIn('.take(8)', body)
        self.assertIn('for (final ip in ipOf[s.host]!)', body)
        self.assertIn('if (natIpDeadRun.contains', body)
        self.assertIn('if (res[k])', body)

    def test_network_fingerprint_is_stable_across_dns_answer_order(self):
        source = (ROOT / 'lib' / 'ultimate_extras.dart').read_text(encoding='utf-8')
        start = source.index('Future<String> _netFingerprint()')
        end = source.index('extension UltimateExt', start)
        body = source[start:end]
        self.assertIn('.toSet().toList()..sort()', body)
        self.assertIn("ips.join(',')", body)

    def test_server_probe_rejects_non_global_addresses_in_both_families(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = source.index('bool _privateIp(InternetAddress a)')
        end = source.index('int byPing(', start)
        helper = source[start:end]
        self.assertIn('NatDnsWireProbe.publicV4(b, 0)', helper)
        self.assertIn('NatDnsWireProbe.publicV6(b, 0)', helper)

    def test_ripe_asn_discovery_stays_ipv4_only_even_when_dns_prefers_aaaa(self):
        source = (ROOT / 'lib' / 'nip_scan.dart').read_text(encoding='utf-8')
        resolve_start = source.index('Future<String?> nipResolve(')
        resolve_end = source.index('/// بلوک‌های هاست', resolve_start)
        resolver = source[resolve_start:resolve_end]
        self.assertIn('address.type == InternetAddressType.IPv4', resolver)
        self.assertIn('for (final address in results)', resolver)
        asn_start = source.index('Future<List<String>> nipAsnPrefixes(')
        asn_end = source.index('// FRONTSNI:', asn_start)
        asn = source[asn_start:asn_end]
        self.assertIn('InternetAddress.tryParse(ip)', asn)
        self.assertIn('parsedIp.type != InternetAddressType.IPv4', asn)
        self.assertIn('return const [];', asn)

    def test_dns_scanner_checks_both_a_and_aaaa_records(self):
        source = (ROOT / 'lib' / 'dns_scanner.dart').read_text(encoding='utf-8')
        start = source.index('Future<DnsxHit?> dnsxProbe(')
        end = source.index('/// اسکن گروهی', start)
        probe = source[start:end]
        self.assertIn('queryType: 1,', probe)
        self.assertIn('queryType: 28,', probe)
        self.assertIn('final good = familyResults.where((result) => result.ok)', probe)
        self.assertIn('tested += part.length;', probe)
        self.assertIn('if (result != null) times.add(result.elapsedMs!);', probe)


    def test_national_configured_ranges_keep_ipv4_and_ipv6_families(self):
        source = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        normalizer_start = source.index('List<String> _natNormalizeConfiguredRanges(')
        normalizer_end = source.index('/// Next bounded sample', normalizer_start)
        normalizer = source[normalizer_start:normalizer_end]
        expand_start = source.index('BigInt _natIpv6ToBigInt(')
        expand_end = source.index('const List<String> natIranDnsHosts', expand_start)
        expander = source[expand_start:expand_end]
        self.assertIn('ip.type == InternetAddressType.IPv6', normalizer)
        self.assertIn('nipExpandIpv6Cidr', normalizer)
        self.assertIn('first.type == InternetAddressType.IPv6', normalizer)
        self.assertIn('InternetAddress.fromRawAddress(Uint8List.fromList(bytes))', expander)
        self.assertIn('nipExpandIpv6Cidr(item, maxPerBlock: limit)', expander)
        self.assertIn('a.type == InternetAddressType.IPv4', expander)
        self.assertIn('a.type == InternetAddressType.IPv6', expander)
        memory_start = source.index('Future<void> natIpMemLoad()')
        memory_end = source.index('const String _domMemKey', memory_start)
        memory = source[memory_start:memory_end]
        self.assertIn('address.type != InternetAddressType.IPv6', memory)
        domain_start = source.index('Future<List<String>> _natDomainFirst(')
        domain_end = source.index('Future<List<String>> natDeviceHosts()', domain_start)
        domain_scan = source[domain_start:domain_end]
        self.assertIn('address.type != InternetAddressType.IPv6', domain_scan)



    def test_smart_pilot_manual_ip_ranges_accept_bounded_ipv4_and_ipv6(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        start = source.index('List<String> _pilotExpandRanges(String raw)')
        end = source.index('Future<void> _pilotRangesDialog', start)
        block = source[start:end]
        self.assertIn('prefix >= 120 && prefix <= 128', block)
        self.assertIn('nipExpandIpv6Cidr(line', block)
        self.assertIn('address.type == InternetAddressType.IPv6', block)
        self.assertIn('out.length < 256', block)
        self.assertIn('InternetAddressType.IPv6', block)
        scan_start = source.index('Future<void> _pilotScanOnly()')
        scan_end = source.index('Future<void> ', scan_start + 20)
        scan = source[scan_start:scan_end]
        self.assertIn('InternetAddress.tryParse(host)', scan)
        self.assertIn('Socket.connect(address, 443', scan)


    def test_vpn_watchdog_requires_repeated_mode_specific_evidence_before_failover(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        check_start = source.index('private void checkOnce()')
        probe_start = source.index('private ProbeResult probeResult(boolean modeSnapshot)')
        probe_end = source.index('private ProbeResult probeOne(String url)', probe_start)
        check = source[check_start:probe_start]
        probe = source[probe_start:probe_end]
        self.assertIn('if (coreState == null)', check)
        unknown_state = check[check.index('if (coreState == null)'):]
        self.assertIn('rescheduleNormal();', unknown_state)
        self.assertIn('if (attemptSeq.get() != healthAttempt)', check)
        self.assertIn('if (nationalMode != modeSnapshot)', check)
        self.assertIn('if (fails < FAILS_BEFORE_SWITCH)', check)
        self.assertIn('FAILS_BEFORE_SWITCH = 2', source)
        self.assertIn('int required = modeSnapshot ? 2 : 1;', probe)
        self.assertIn('DOMESTIC_PROBE_URLS', probe)
        self.assertIn('INTERNATIONAL_PROBE_URLS', probe)
        self.assertIn('if (passed >= required) return ProbeResult.OK;', probe)

    def test_turbo_ui_does_not_claim_mux_is_enabled(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn('Mux در این نسخه فعال نیست', source)
        self.assertIn('تا آزمون سازگاری و throughput روشن نمی‌شود', source)
        self.assertIn('Mux و Noise تا تأیید سازگاری', source)
        # Keep the safety gate explicit: unsupported variants must not enter
        # the connection matrix merely because the UI calls the mode "turbo".
        ultra = (ROOT / 'lib' / 'nat_ultra.dart').read_text(encoding='utf-8')
        self.assertIn('if (x.mux) return false;', ultra)
        self.assertIn('if (x.noise) return false;', ultra)

    def test_vpn_global_watchdog_probes_independent_provider_families(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private static final String[] INTERNATIONAL_PROBE_URLS')
        end = source.index('};', start)
        urls = source[start:end]
        self.assertIn('www.cloudflare.com/cdn-cgi/trace', urls)
        self.assertIn('github.com/robots.txt', urls)
        self.assertIn('www.google.com/generate_204', urls)
        self.assertIn('www.gstatic.com/generate_204', urls)
        # One independent success is still enough; diversity is fallback coverage,
        # not a requirement that every provider be reachable on a restricted network.
        probe_start = source.index('private ProbeResult probeResult(boolean modeSnapshot)')
        probe_end = source.index('private boolean isLocalHttpInboundAvailable()', probe_start)
        probe = source[probe_start:probe_end]
        self.assertIn('int required = modeSnapshot ? 2 : 1;', probe)
        self.assertIn('if (passed >= required) return ProbeResult.OK;', probe)

    def test_vpn_watchdog_does_not_accept_redirects_or_non_success_status_as_health(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        start = source.index('private ProbeResult probeOne(String url)')
        end = source.index('private ', start + 20)
        probe = source[start:end]
        self.assertIn('setInstanceFollowRedirects(false)', probe)
        self.assertIn('expects204 ? code == HttpURLConnection.HTTP_NO_CONTENT', probe)
        self.assertIn('(code >= 200 && code < 300)', probe)
        self.assertIn('c.disconnect();', probe)


    def test_vpn_watchdog_treats_missing_local_http_inbound_as_inconclusive(self):
        source = (ROOT / 'android_src' / 'KingVpnService.java').read_text(encoding='utf-8')
        self.assertIn('private enum ProbeResult { OK, SOFT_FAIL, INCONCLUSIVE, HARD_FAIL }', source)
        check_start = source.index('private void checkOnce()')
        probe_start = source.index('private ProbeResult probeResult(boolean modeSnapshot)')
        check = source[check_start:probe_start]
        self.assertIn('if (pr == ProbeResult.INCONCLUSIVE)', check)
        inconclusive = check[check.index('if (pr == ProbeResult.INCONCLUSIVE)'):check.index('healthyStreak = 0;', check.index('if (pr == ProbeResult.INCONCLUSIVE)'))]
        self.assertIn('fails = 0;', inconclusive)
        self.assertIn('rescheduleNormal();', inconclusive)
        probe_start = source.index('private ProbeResult probeOne(String url)')
        probe_end = source.index('private ParcelFileDescriptor establish', probe_start)
        probe = source[probe_start:probe_end]
        self.assertIn('return ProbeResult.INCONCLUSIVE;', probe)
        aggregate_start = source.index('private ProbeResult probeResult(boolean modeSnapshot)')
        aggregate_end = source.index('private ProbeResult probeOne(String url)', aggregate_start)
        aggregate = source[aggregate_start:aggregate_end]
        self.assertIn('ProbeResult worst = ProbeResult.INCONCLUSIVE;', aggregate)
        self.assertIn('private boolean isLocalHttpInboundAvailable()', source)
        self.assertIn('socket.connect(new InetSocketAddress("127.0.0.1", LOCAL_HTTP_PORT)', source)
        self.assertIn('if (!isLocalHttpInboundAvailable()) return ProbeResult.INCONCLUSIVE;', probe)
        self.assertIn('return isLocalHttpInboundAvailable()', probe)
        self.assertIn('? ProbeResult.SOFT_FAIL : ProbeResult.INCONCLUSIVE;', probe)
        self.assertIn('catch (SocketException | SocketTimeoutException e)', probe)
        self.assertIn('catch (UnknownHostException | SSLException e)', probe)
        self.assertIn('return ProbeResult.INCONCLUSIVE;', probe)
        self.assertIn('Unexpected probe/runtime failures are not proof of a dead route.', probe)


    def test_plain_fallback_keeps_native_watchdog_http_inbound_without_policy_rewrite(self):
        source = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        helper_start = source.index('String _withVpnHealthHttpInbound(String cfg)')
        helper_end = source.index('// Real-VPN config:', helper_start)
        helper = source[helper_start:helper_end]
        self.assertIn("'listen': '127.0.0.1'", helper)
        self.assertIn("'port': httpProxyPort", helper)
        self.assertIn("'protocol': 'http'", helper)
        self.assertIn('if (portOccupied) return cfg;', helper)
        self.assertIn("if (base != cfg) _withVpnHealthHttpInbound(base)", source)
        # The fallback is still not passed through the DNS/routing policy pipeline.
        cfg_list_start = source.index('final cfgTries = <String>[')
        cfg_list_end = source.index('].map((c) => withErrLog', cfg_list_start)
        cfg_list = source[cfg_list_start:cfg_list_end]
        self.assertIn('_withVpnHealthHttpInbound(base)', cfg_list)
        self.assertNotIn('_reliableVpnCfg(base)', cfg_list)


if __name__ == '__main__':
    unittest.main()
