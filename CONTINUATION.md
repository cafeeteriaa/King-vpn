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
