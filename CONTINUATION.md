# King VPN — mainline continuation checkpoint

## Source of truth
- Repository: `cafeeteriaa/King-vpn`; base `main` HEAD: `c43d325f9803d4f6306415e511f6790deff9d87e`.
- Active branch: `codex/continuation-mainline-20261122`.
- Current branch HEAD: `c23e607d2e2b0e031c1cda24a67c3c3a1a2a081a` (DNS policy test commit).
- PR #42 remains open, Draft, targeting `main`; not merged.
- PR #41 / domestic-ranking branch remains separate; do not retarget or merge without a full diff audit.

## Network-probe cache correctness
- Both `NatNetworkDiagnosis` and `PilotNetworkProbe` previously could reuse stale classification when interface identity was unavailable or changed, or when the clock moved backwards.
- `shouldReuseNetworkProbeCache` in `lib/network_health.dart` now requires no forced refresh, known non-empty current and cached identities, exact identity equality, a timestamp, and age >= 0 and below TTL.
- Both cache paths in `lib/national_engine.dart` use the helper.
- Six focused tests in `test/network_health_test.dart` cover valid same-network reuse, unavailable current identity, changed network, missing cached identity, expired/backwards-clock cache, and forced refresh.
- Run 1932 (`44984895465`) on docs checkpoint `a64465851434784545dbc17bfb0369c14fd99ed4` completed source guards, Flutter tests and Dart analysis, and entered the arm64 release build; it was still running at the latest poll. It does not include the DNS follow-up commits.

## Android IPv6 fail-closed correction
- Audit of `android_src/KingVpnService.java` found the TUN builder added the IPv6 interface address and default route inside a try block, but swallowed any exception and continued to establish the IPv4 route.
- Android's official `VpnService.Builder` reference says adding an address/route enables that address family; with a partially accepted IPv6 setup, continuing after a route failure risks leaving IPv6 outside the tunnel.
- The catch now throws an `IllegalStateException` instead of establishing a partially configured VPN. The outer establish handler reports failure and returns null, preventing a false CONNECTED state with a possible IPv6 bypass.
- Added `test_android_vpn_refuses_partial_ipv6_tunnel_setup` to `test/test_source_guards.py`, asserting that IPv6 setup failure aborts before IPv4 setup and `establish()`.
- This is a fail-closed safety behavior: if IPv6 setup genuinely fails on a device, the VPN connection will fail rather than silently provide an IPv4-only tunnel. Device validation is still required.
- Android reference: https://developer.android.com/reference/android/net/VpnService.Builder (addAddress/addRoute/allowFamily semantics).

## Other audit notes
- Active-branch `android_src/MainActivity.kt` registers `vpn/bg` and handles `alive`, `back`, and `vpnSettings`; the historical MissingPluginException still needs runtime reproduction.
- `_reliableVpnCfg` prefers domestic DNS in national mode and sets `queryStrategy=UseIP`; static inspection does not prove active-core behavior or rule out DNS leakage. Android `VpnService.Builder.addDnsServer` documentation confirms that omitting an explicit DNS server uses the default network's DNS servers; full IPv4/IPv6 TUN routes should capture traffic, but runtime packet/core verification remains necessary.
- Xray accepts DNS servers as either strings or `DnsServerObject` maps. The old national-mode Secure DNS filter only inspected strings beginning with `https://`, so a DoH map (`{"address":"https://..."}`) could survive while Secure DNS was disabled.
- Added `lib/dns_policy.dart` and routed national-mode server merging through `mergeNationalDnsServers`. It preserves domestic-first order and existing per-object metadata, filters DoH map entries by their `address` when Secure DNS is off, retains them when Secure DNS is on, and preserves duplicate handling. Added four tests in `test/dns_policy_test.dart` for string DoH, object DoH, Secure DNS enabled, and domestic-first deduplication.
- DNS policy commits: helper `5d7333a769646ce29496096a581a325a7d82b2c7`, integration `6f06c559c0aa80bb684fc68b2417cda6fe5d7670`, tests `c23e607d2e2b0e031c1cda24a67c3c3a1a2a081a`.
- Dart stop logic waits for DISCONNECTED with a timeout and marks `_staleCoreMayBeUp` if shutdown cannot be confirmed. Keep reviewing races without removing existing guards.
- DNS replies, TCP opens, and TLS handshakes are diagnostic evidence only, not proof that traffic traverses the VPN tunnel.

## CI / artifact evidence
- Baseline main run 1393 (`44785612381`) succeeded for source guard, Flutter tests, Dart analysis, arm64 release APK build and artifact upload; debug-key signing only.
- Run 1924 (`44956105111`) succeeded for an earlier checkpoint; artifact is historical.
- Run 1925 (`44984275812`) succeeded for older code `d284f9d40b7fd7057298625bd83200c75f326afc`: source guard, Flutter tests, Dart analysis, arm64 APK build, and artifact uploads passed. APK ZIP digest `sha256:836e6c5e97947bcd4beea4a44395cf37bdb5ac61efba887c7c44ddc952d2db30`; debug-key signed. It predates later cache and IPv6 fixes.
- Run 1928 (`44984479396`) for earlier checkpoint `4e8d08cd38d88e8441d55d38c3cb9a99af05d5f9` completed successfully: source guard, Flutter tests, Dart analysis, optimized arm64 release APK build, and APK/source/symbol artifact uploads all passed. Artifacts are older-source evidence only; APK archive digest `sha256:a4653731a2d2684aba4f19b436f0153fa01b06c4bc608ece05a3a01601b48451`.
- Run 1929 (`44984637534`) for cache-fix code head `ecd6b8b2533f5d61967b29eac2e9c4db90e33695` was cancelled before jobs ran.
- Run 1930 (`44984708185`) for docs checkpoint `6d1b8d469b6267bb689fa56bf4eefbaa0b2e4023` remained pending with no jobs at last poll.
- Run 1932 (`44984895465`) is for `a64465851434784545dbc17bfb0369c14fd99ed4`, not the current DNS policy head; its source guard, Flutter tests and Dart analysis passed, and the arm64 build was in progress at last poll. No exact-head check-run was visible for current `c23e607d2e2b0e031c1cda24a67c3c3a1a2a081a` at the last poll. Do not claim the DNS policy tests passed until a run actually executes.
- No real device, production signing, inner-APK metadata/checksum inspection, or Iranian operator-network validation has been performed. Current branch is not declared install-ready.

## Engineering guardrails
- Preserve IP Clean sources, ranges, ports and scan capabilities; no arbitrary limits without evidence and tests.
- Preserve IPv4 and IPv6 capability; do not infer Iranian IPv6 ASN ownership from country labels.
- Rank domestic endpoints by observed successful national traffic first; ASN/transport/CDN hints are weaker evidence.
- Do not add Gemini, Grok, paid APIs, or API-key-dependent AI services.
- Never call a build install-ready until the exact final source commit passes guards, Flutter tests, Dart analysis, arm64 build, APK metadata/checksum/signing verification, and device validation.
- Do not merge to `main` or cancel active CI runs without explicit authorization.

## Next actions
1. Get a non-cancelled CI run for current head `c23e607d2e2b0e031c1cda24a67c3c3a1a2a081a`; verify source guards, DNS policy tests, all Flutter tests, Dart analysis, and arm64 build.
2. Poll run 1932 for build completion and artifact metadata; treat it as pre-DNS-fix source only.
3. Continue DNS path audit, including whether resolver traffic traverses the intended core and whether IPv4/IPv6 can bypass the TUN.
4. Complete connect/stop/failover race review across Dart and `KingVpnService`.
5. If an exact-head APK is built, inspect the inner APK, ABI, package metadata, APK SHA-256 and signing status.
6. Validate national/global traffic on real operator networks separately; CI cannot establish this.


## Latest continuation — 2026-11-22
- Current branch HEAD: `3d0e838d456a879daeaa772bd110bce1ddcaf29b`; PR #42 remains open, Draft, targets `main`, not merged.
- Commit `d14eeb15384dcc492e597ba8c1ad556a6d489b85`: final native `CONNECTED` publication in `KingVpnService.startFlow` is guarded by `lifecycleLock` and rechecks `stopping || userStopped` before saving state, starting watchdog, and emitting success. Added a source guard.
- Commit `3d0e838d456a879daeaa772bd110bce1ddcaf29b`: in the default FlutterV2ray path, asynchronous stale-core tunnel verification now captures the current `_connGen` and verifies the same `connSig` is still active, incomplete, and `wantVpn` remains true after the network probe returns. An old probe cannot clear `_staleCoreMayBeUp` or complete a superseded waiter. Added a source guard.
- Important distinction: Flutter plugin status events do not carry attempt IDs. The Dart side uses serialized core starts, generation checks on the waiter, stale-core traffic verification, and post-await generation validation; do not claim plugin event callbacks themselves are natively generation-tagged.
- `kOwnVpnService=false`; the plugin-managed path is the active default. Custom native service work must not be mistaken for default-path runtime validation.
- CI run `44986379535` belongs to `d14eeb1`, not current HEAD. It was pending with no jobs visible at last poll. A new exact-head run for `3d0e838` is expected; verify it before making any build/test claims.
- Next: audit plugin-managed stop/start and late CONNECTED/DISCONNECTED callback ordering; verify `_verifyPendingConnect` cannot leave a waiter hanging after a superseded probe; inspect tunnel probe routing (must be through core, not direct network); check run status and update this checkpoint.
- No device, Iranian operator-network, production-signing, or exact-head APK validation is claimed.

- Follow-up clarification commit: `8691127c3e331affa1ea541805d0d51ab4d3e66d` updates the stale function comments to accurately describe both data paths; no behavior changed in that comment-only commit.


## Latest continuation — 2026-11-22 (proxy-path verification)
- Current engineering code commit: `824479a3e10f4eabb6a167a18136894b688cc1af`; branch now includes this commit. PR #42 remains open and Draft; do not merge without explicit authorization.
- Fixed a false-positive in `_tunnelTrafficOk()`: proxy mode previously returned true without making a network request. It now executes the same real-traffic probe in both modes. In proxy mode, `_useCoreProxy(true)` selects `127.0.0.1:$httpProxyPort`; in VPN mode, the existing core-proxy/tunnel path remains in force. A CONNECTED event alone is not treated as proof of usable internet.
- Added source guard `test_stale_connect_verification_checks_proxy_mode_data_path` to prevent restoring the proxy-mode unconditional-success shortcut and to assert the probe uses the local core HTTP proxy.
- Reviewed `_siteOpens()`: it uses `_useCoreProxy(viaCore)` and explicit HTTP proxy routing; success requires HTTP 2xx/3xx, not merely a response. The current stale verification calls it with `viaCore: true`.
- CI run `44986813019` is the exact-head run for code commit `824479a`; it was pending and had no jobs exposed at the last poll. Do not claim CI success until this run (or a newer exact-head run) completes successfully.
- The plugin's status callbacks still have no attempt identifiers; do not claim native event-level generation tagging. Existing Dart waiter generation guards remain.
- No real device, operator-network, production-signing, or install-ready APK validation is claimed.
- Next: poll exact-head CI; audit DISCONNECTED callback/downSig ordering and superseded stop waiters; inspect `_verifyPendingConnect` timeout/cancellation behavior; continue IPv4/IPv6 DNS and route-bypass audit.


## Latest continuation — 2026-11-22 (stop-event attribution safety)
- Verified current pre-change HEAD `5bae3ddd34148b2317532faeb7bab424664166c3` with CI run `44986967528`: Source-repair guard, Flutter unit tests, Dart analysis, optimized arm64 release-mode APK build, and APK/source/symbol artifact uploads all completed successfully. Artifact is debug-key signed and is not a production-signed or device-validated release.
- CI artifacts: arm64 APK artifact `14740387981` (archive digest `sha256:0ccfd7216c5071aa2bc7b226a023ec349499fdad6bb39e17da083404a28fc3f5`); full source `14739899130`; symbols `14740596932`.
- Audit found `downSig` was completed by any plugin `DISCONNECTED` callback while a stop waiter existed. Since FlutterV2ray status events have no attempt IDs, an old callback could be misattributed to a later stop and prematurely shorten teardown.
- Removed the unattributed `downSig` completion path. `_stopCoreInner` now awaits the plugin stop request, applies a conservative fixed 2.2-second teardown grace, and always leaves `_staleCoreMayBeUp` enabled. A subsequent CONNECTED event must pass the existing real traffic probe through the core proxy before it can satisfy the active connect waiter.
- Added source guard `test_plugin_stop_does_not_trust_unattributed_disconnected_event`. This is a source-level race mitigation; plugin events still cannot be correlated to native attempts, and real-device lifecycle testing remains necessary.
- New commit is not yet CI-validated; do not carry forward the previous HEAD's CI result to this commit.
- No device/operator validation or production signing is claimed. PR #42 remains open Draft; do not merge.


## Latest continuation — CONNECTED verification deduplication (2026-11-22)
- Follow-up audit of the default FlutterV2ray path found repeated CONNECTED callbacks could launch overlapping traffic probes for the same pending waiter. A platform/proxy-selection exception thrown before _siteOpens enters its own catch could also escape the async callback.
- Added per-waiter in-flight deduplication for _verifyPendingConnect; a newer waiter remains independent. Probe exceptions are logged and treated as unverified traffic; they cannot clear _staleCoreMayBeUp or complete the waiter. The existing bounded connect timeout remains responsible for ending an unverified attempt.
- Added source guard test_stale_connect_verification_coalesces_callbacks_and_contains_probe_errors.
- This change does not add attempt IDs to FlutterV2ray events and does not claim to solve all late DISCONNECTED state attribution. Requires exact-HEAD CI and real-device lifecycle validation.


### CI source-guard correction
- CI run `44987802709` checked out merge commit `bf45f363ee746090c5d53613437df49238c81115` for PR head `57c17535330b6362c391ba4eac6afc62f8bc79da`.
- Source guards found one stale test assertion: the implementation assigns the awaited probe result to a previously declared `bool ok`, while the test expected an inline `final ok` declaration. This is a test expectation mismatch, not a Dart compile/test failure; Flutter tests, Dart analysis and APK build were skipped because the source guard is a required first step.
- Corrected the source guard to assert the actual assignment. Exact new HEAD must pass a fresh CI run before validation claims.


## Latest follow-up — verify unattributed DISCONNECTED before failover (2026-11-22)
- Audit found the default FlutterV2ray callback still immediately treated an untagged DISCONNECTED event as authoritative after a 2-second debounce. A late event from an older core could therefore trigger unnecessary failover while the current connection was still healthy.
- Added _confirmDisconnectBeforeFailover: it coalesces probes per connection generation, checks the current Android TUN via tunUp(), then requires real core-path traffic via _tunnelTrafficOk(). It rechecks generation, intent, busy/switching, and network state after awaits before deciding. A healthy current TUN/data path restores CONNECTED state; otherwise failover proceeds.
- Both the normal 2-second disconnect debounce and deferred-disconnect recovery now use this confirmation path. Added source guard test_unattributed_disconnect_requires_current_tun_and_traffic_before_failover.
- This reduces false failovers but does not add native attempt IDs or prove which plugin event was emitted by which core. Device lifecycle and operator-network testing remain required.
- New commit must pass its own source guards, Flutter tests, Dart analysis and arm64 release build; no current-head APK/device validation is claimed.


## Latest continuation — Smart Pilot evidence consistency (2026-11-22)
- Current branch head: `ae43210a6eed10158868f552d91aeb5a253fa185`; PR #42 remains open Draft, not merged.
- Commit `c8443a1049f434982b7ba8c0cbe404e202ed46a9`: `choosePilotNetworkStrategy` now requires explicit TLS reachability verification and at least 2 successful handshakes for a healthy group; an unreachable group must have zero successes as well as sufficient samples. This prevents contradictory manually constructed/stale evidence from changing the route.
- Commit `ae43210a6eed10158868f552d91aeb5a253fa185`: confidence calculation clamps successful counts to the number of available samples; tests cover inconsistent healthy labels without TLS quorum and impossible success counts.
- Scanner behavior is unchanged: three domestic and three global TLS handshakes; quorum >=2/3. TLS reachability still does not prove VPN tunnel traffic.
- Exact-head CI run `44996637457` was triggered for `ae43210a`; source-repair guard passed, Java setup passed, Gradle setup was still running at last poll. Do not claim Flutter tests, Dart analysis, APK build or artifact upload passed until this run completes.
- Static audit of plugin-managed disconnect handling: `DISCONNECTED` events are treated as unattributed; current TUN daemon-liveness signal and core data-path probe are rechecked before failover. Plugin events still carry no attempt ID. No device/operator-network validation.
- Next: poll run `44996637457`; if it passes, download and inspect exact-head APK/source artifacts. Continue review of DNS resolver traffic and native/plugin stop-start races. Keep PR #42 Draft and unmerged.


## CI correction — Smart Pilot fixture migration (2026-11-22)
- CI run 44996637457 for code commit ae43210a failed the test step: 131 passed, 3 failed. All three failures were stale fixtures in `pilot_command_bar_test.dart` (2) and `smart_pilot_architecture_test.dart` (1), which declared healthy reachability without the newly required successful-handshake count and TLS verification.
- Updated those fixtures in commits `68d860bd26fa61f5f5e1fa21352f98318ce4976b` and `a10b5301ecf3761c597347501440bca73f79a209`; production policy was not weakened.
- The 131 other tests, including the new evidence-consistency tests, passed in the failing run. The suite must be rerun on the current branch head before claiming green.
- CI run 44996679873 was queued on the earlier documentation checkpoint but its run metadata captured code SHA ae43210a while PR head subsequently advanced; do not treat it as validation of the fixture updates. Await a run whose tested SHA matches current branch HEAD.


## Exact-HEAD CI and APK checkpoint — 2026-11-22
- Branch HEAD tested: `4ec8d2bb42fbbebf8449e8498bae5fb35b5be31f`; workflow run `44998437589` (run number 2001) completed successfully for this exact commit.
- All 134 Flutter tests passed; source-repair guard, Dart analysis, V2Ray plugin patching, optimized Android arm64 release-mode APK build, 16 KiB ELF PT_LOAD validation (19 native libraries), and Android `zipalign -c -P 16 -v 4` validation all passed.
- APK artifact: `king-vpn-arm64-release-2001`, artifact ID `14745136575`, ZIP digest `sha256:13574844019a99b09dd8a4215459cd2d64b911619544741e8ff693526188d106`. Extracted APK SHA-256: `8a251f04ac8c60a9da9340c757052258b839b2504202792c0470a0c3323d16c1`; APK size 122,885,758 bytes.
- Signing is the generated Flutter debug key, not a production signing key. The artifact is a CI validation build, not a Play Store/production release. No Android device, real VPN traffic, IPv6 runtime, or Iranian operator-network validation is claimed.
- TUN evidence now has two independent signals on Android: plugin daemon-process liveness and `ConnectivityManager` active-network `TRANSPORT_VPN`; either alone is insufficient. If both are not positively confirmed, interface enumeration remains the compatibility fallback, and a known inactive daemon vetoes that fallback. Source guards cover both sides. Device testing is still needed to confirm Android exposes the expected active VPN transport on supported OEM builds.
- PR #42 remains open, Draft, and unmerged.


## TUN false-positive prevention follow-up — 2026-11-22
- Audit found the interface-name compatibility fallback could accept a generic `tun*`/VPN-like interface even when Android's `ConnectivityManager` definitively reported that the active network was not a VPN transport. In a multi-VPN or stale-daemon scenario, that could misattribute another provider's interface to King VPN.
- `tunUp()` now returns false immediately when the King VPN daemon signal is available but `kingVpnTransportActive` definitively returns false. The interface-name fallback remains available only when the native transport result is unavailable/indeterminate; positive native proof still requires both daemon liveness and VPN transport.
- Added a source guard asserting the definitive-negative check occurs before interface fallback.
- Commits: implementation `14481302424c2268b8931eea5b88c859d329c452`; test `34acb1cdf6756a1c82e062e3de9918bd8a42fd50`. Exact-HEAD CI run `45000052401` (run 2003) is pending; do not claim this follow-up is validated until it completes.
- This remains source-level evidence hardening. Real Android device/OEM, VPN coexistence, tunnel traffic, IPv6 and operator-network tests are still required. PR #42 remains Draft and unmerged.


## Underlying-network detection hardening — 2026-11-22
- The network watchdog previously treated any non-loopback interface with any address as proof that the phone's underlying network was up, excluding only `tun*` and `dummy*`. VPN-like interfaces named `vpn*`, `ppp*`, `utun*`, `wg*`, `tailscale*`, or containing `wireguard`, `xray`, or `v2ray` could therefore mask a real physical-network outage.
- `_netWatch()` now excludes those virtual tunnel interface families and counts an interface as up only after finding an IPv4 or IPv6 address. It also serializes periodic scans with `_netWatchBusy` so overlapping asynchronous snapshots cannot overwrite newer network state.
- Added source guards for virtual-interface exclusions, address-family evidence, and scan serialization.
- Commits: implementation `90edc493677af3daa7d20ea666ae0e8e62f75a41`; tests `939321e141f566513601dce2f235a7ff2d9c79dc`. CI run 2006 (`45000309340`) targets the exact test commit and is pending.
- This is source-level hardening only. Physical Wi-Fi/mobile transitions, OEM interface naming, captive portals, airplane mode, and IPv4/IPv6 runtime behavior still require device/network testing. PR #42 remains Draft and unmerged.


## Network-change failover grace — 2026-11-22
- The watchdog previously raised `fails` to `watchFailLimit - 1` immediately on any interface/IP signature change. A single failed tunnel probe during Wi-Fi/mobile handover or IPv6 privacy-address rotation could therefore trigger premature server failover.
- A connected link change now clears stale failure count and updates `netUpAt`; the existing 15-second settling guard suppresses failover while Android rebuilds routes/DNS. Repeated failures after the grace period still follow the normal watchdog threshold.
- Added a source guard asserting the grace path is used and the immediate-failover shortcut is absent.
- Commits: implementation `e61656e223acee52f81b6cccb1f8420a62c21e5c`; tests `37f27f127bc21de114a3a75dede5f8d01df4c7b7`.
- The prior CI run 2007 was cancelled when a newer commit superseded it; the new exact-commit CI result must be checked before treating this change as validated. No live carrier or device test is claimed.


## DoH cache network-generation and mode fencing — 2026-11-22
- Audit found that `natDohUsable()` captured the network generation to prevent stale cache writes, but still returned the old probe result to its caller when the generation changed during the asynchronous request. The server-variant ladder could therefore consume a stale positive/negative result even though it was not cached.
- DoH cache entries are now also scoped to national/global mode because the probe target differs (`nic.ir` vs `google.com`).
- An in-flight probe whose network generation changes is discarded and retried once against the current generation; a second concurrent network change fails closed. A mode change during the probe also fails closed. Only a result validated against the same generation and mode can be cached or returned.
- Added source guards for generation fencing, bounded retry, and mode-aware cache validation.
- Commits: implementation `4f53a27e69e1350637c01fbc7e1270bc1dcfab3b`; tests `988ddab83eaec17ab7c8cd5c28faf91cd6798a3d`.
- CI result for the final documentation head must be checked before calling the change validated. No live DNS or carrier test is claimed.

## OODA outage/recovery guard for self-heal and disconnected retry — 2026-11-22
- OODA audit found that the watchdog's NETHOLD protected connected tunnel probes, but the self-heal engine ran before that guard and could interpret an orphaned connection as a reason to reconnect/search during a known underlying-network outage. The disconnected watchdog retry path also called failover before reaching NETHOLD.
- Self-heal now still observes/diagnoses, but defers disruptive automatic actions while `netDown` is true or during the 15-second `netUpAt` route/DNS recovery grace. Explicit `reason: 'force'` remains the manual override.
- The disconnected watchdog branch now applies the same outage/recovery gate before retry/failover.
- Added source guards for both paths. No live device/carrier validation is claimed.
- Commits: heal `7b85d8f2d54106c7b1691c4c81997c67823e7f00`; watchdog `c97680ceea1ad53031c11c4d08c39b3e9ae7b87e`; tests `d05b2728cc67896fb97ea23cf6a6fb9f1d793257`.
- A new exact-head CI run is required; prior run 2012 tested the earlier head and cannot validate these commits.


## OODA DNS evidence invalidation across outage/recovery — 2026-11-22
- Audit found that _netWatch() invalidated the DoH precheck cache when the interface/IP signature changed, but a physical outage/recovery can occur while Android reports the same interface signature. In that case, DNS reachability evidence from before the outage could remain reusable.
- _netWatch() now calls natDohCacheClear() exactly when the underlying network transitions into confirmed netDown, and again when it transitions back to available. The existing DoH generation fence discards in-flight probes from the prior network state; the next variant decision must observe the new state.
- Commits: implementation c7ed6eff05ca474ec394f72aeca5ae84c68ba17d; source guard d7e5eccdf996bbee154a339c8bcc380f3716e290.
- This invalidates DNS evidence only; it does not itself prove DNS resolution, tunnel traffic, or domestic/global reachability. CI for the exact final head and real-device/carrier validation are still required.
- PR #42 must remain open Draft and unmerged.


## OODA: isolate NNIE learning by domestic/global route — 2026-11-22
- Audit found NNIE endpoint history was keyed by endpoint + transport/TLS only. The same success/failure history could influence standby ranking and source ordering in both national and global modes, even though reachability and tunnel behavior differ by route.
- NNIE keys now include an explicit domestic/global scope; all connect successes, verified stable-traffic updates, tunnel failures, national candidate ordering, Smart Pilot standby scoring, and diagnostic history reads use the current route scope.
- Persistence key advanced from nnie_profiles_v2 to nnie_profiles_v3. The old mixed-scope history is intentionally not reused, avoiding contamination; no server/config is rejected for lacking new history.
- Commits: engine 7984e147898fc201a82f71882612404a85ca3552; main integration 87d5aef9a9880630f2e115314bf7f94d2ac5c215; pilot/diagnostics b70b0aa72980cc0c0ce0500494a6d7efbf1916ea; source guard 11e448da2b9ec31ba62e592c988be1b2bd820a04.
- CI and real-device/carrier validation are pending. PR #42 remains open Draft and unmerged.


## OODA: require fresh standby endpoint evidence before Smart Pilot switches — 2026-11-22
- Audit found `_pilotBestStandby()` could include candidates whose ranking was lifted by route-scoped NNIE history or profile rate even when their endpoint check was missing/stale. That could authorize an unnecessary switch to an unverified standby.
- Standby candidates now require a successful positive endpoint ping measured within the last four minutes. Stale/cached NNIE and profile data remain advisory for ranking only after this live eligibility gate; the existing 12-point hysteresis remains.
- The guard is deliberately described as endpoint reachability, not proof that user traffic passes through the VPN tunnel. Verified tunnel outcome history remains separate evidence and is still route-scoped.
- Added a source guard for the freshness gate and the distinction between endpoint checks and tunnel data-plane proof.
- Commits: implementation 6bf961f6343929dbc9a2d7d39adb97af46308ee7; source guard 4cca04249db1414f324572b470445b2cdd97d736.
- CI and real-device/carrier validation are pending. PR #42 remains open Draft and unmerged.


## OODA: exact-head validation checkpoint — 2026-11-22
- Current branch/PR head at this checkpoint: `bde2bb133a579bea89f1ae7e2b0e1fb020725181`; base `main` is `c43d325f9803d4f6306415e511f6790deff9d87e`.
- Exact-head Android CI run `45002336463` completed successfully. Its job passed source-repair guards, Flutter unit tests, plugin patching, Dart analysis, optimized arm64 release-mode APK build, 16 KiB ELF PT_LOAD alignment validation, 16 KiB APK ZIP alignment validation, and artifact uploads.
- The PR is mergeable with GitHub merge state `clean`; this confirms GitHub reports no merge conflict, not runtime correctness.
- This exact-head CI result supersedes the earlier historical notes above that described CI as pending for earlier checkpoints. No physical-device, IPv4/IPv6 traffic-leak, VPN carrier, Iranian operator-network, production-signing, or Play-install validation is claimed. CI's APK uses the configured CI signing key and is not a production release.
- Smart Pilot standby candidates now require positive endpoint ping evidence no older than four minutes; NNIE history is separated by domestic/global route. Endpoint ping and TLS reachability are not equivalent to proof of application traffic through the Android VPN TUN.
- Next integration decision: only integrate this exact tested head after reconfirming the PR head and successful checks; preserve this distinction between automated CI evidence and real-device acceptance.


## Latest continuation — 2026-11-27 (unified resource-source prioritization)

- Implementation is confined to the active development branch; main is unchanged.
- Added lib/king_resource_intelligence.dart as a shared source-classification and stable-priority layer.
- Integrated it into fetchServers() (global/shared source path) and natHotUrls() / _natHotEnsureImpl() (Net Melli hot-source cache).
- Net Melli prioritizes known domestic public hosts, then user-provided sources, then community/public sources. Global mode prioritizes user-provided sources, then community/public sources, then domestic hints.
- Every source supplied to the ordering function is retained; no new source-count cap or automatic subscription purchase was added. Existing fetch deadlines, cancellation, parsing, deduplication, and cache safeguards remain in place.
- User-provided URLs are classified as requiring user-supplied access; this does not assert that every such URL is paid. A paid source is only fetched with the user's existing access; no account creation or purchase occurs.
- Host classification is a scheduling hint only. It does not prove that a host is domestic, reachable, safe, or capable of providing a working tunnel.
- Added 8 focused Dart unit tests and a Python source guard for the national hot-source integration.
- Validation status: NOT RUN in this environment. No Dart/Flutter SDK is available here, and no CI workflow run or commit status was returned for the implementation commit at the last check. Do not mark the new tests, analyzer, APK build, or device behavior as passed.
- Scope boundary: this change implements unified source classification and ordering. It does not by itself implement arbitrary gateway creation, bypass the absence of an upstream route, or claim component-level repair / real-tunnel success. Existing server parsing and connection verification remain responsible for deciding whether a fetched configuration is usable.
- Next acceptance: obtain exact-head CI for source guards, Flutter tests, Dart analysis, and arm64 build; then continue the full scanner audit and perform real tunnel traffic validation on separate domestic and global networks.
