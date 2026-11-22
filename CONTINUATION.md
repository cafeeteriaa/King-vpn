# King VPN — mainline continuation checkpoint

## Source of truth
- Repository: `cafeeteriaa/King-vpn`; base `main` HEAD: `c43d325f9803d4f6306415e511f6790deff9d87e`.
- Active branch: `codex/continuation-mainline-20261122`.
- Current branch HEAD: `7b8aa6d85e8201acaf9d123e6474c905f2facecb`.
- PR #42 remains open, Draft, targeting `main`; not merged.
- PR #41 / domestic-ranking branch remains separate; do not retarget or merge without a full diff audit.

## Network-probe cache correctness
- Both `NatNetworkDiagnosis` and `PilotNetworkProbe` previously could reuse stale classification when interface identity was unavailable or changed, or when the clock moved backwards.
- `shouldReuseNetworkProbeCache` in `lib/network_health.dart` now requires no forced refresh, known non-empty current and cached identities, exact identity equality, a timestamp, and age >= 0 and below TTL.
- Both cache paths in `lib/national_engine.dart` use the helper.
- Six focused tests in `test/network_health_test.dart` cover valid same-network reuse, unavailable current identity, changed network, missing cached identity, expired/backwards-clock cache, and forced refresh.
- These tests have not yet completed in a non-cancelled run for the exact current head.

## Android IPv6 fail-closed correction
- Audit of `android_src/KingVpnService.java` found the TUN builder added the IPv6 interface address and default route inside a try block, but swallowed any exception and continued to establish the IPv4 route.
- Android's official `VpnService.Builder` reference says adding an address/route enables that address family; with a partially accepted IPv6 setup, continuing after a route failure risks leaving IPv6 outside the tunnel.
- The catch now throws an `IllegalStateException` instead of establishing a partially configured VPN. The outer establish handler reports failure and returns null, preventing a false CONNECTED state with a possible IPv6 bypass.
- Added `test_android_vpn_refuses_partial_ipv6_tunnel_setup` to `test/test_source_guards.py`, asserting that IPv6 setup failure aborts before IPv4 setup and `establish()`.
- This is a fail-closed safety behavior: if IPv6 setup genuinely fails on a device, the VPN connection will fail rather than silently provide an IPv4-only tunnel. Device validation is still required.
- Android reference: https://developer.android.com/reference/android/net/VpnService.Builder (addAddress/addRoute/allowFamily semantics).

## Other audit notes
- Active-branch `android_src/MainActivity.kt` registers `vpn/bg` and handles `alive`, `back`, and `vpnSettings`; the historical MissingPluginException still needs runtime reproduction.
- `_reliableVpnCfg` prefers domestic DNS in national mode and sets `queryStrategy=UseIP`; static inspection does not prove active-core behavior or rule out DNS leakage. Verify using runtime logs and IPv4/IPv6 leak tests.
- Dart stop logic waits for DISCONNECTED with a timeout and marks `_staleCoreMayBeUp` if shutdown cannot be confirmed. Keep reviewing races without removing existing guards.
- DNS replies, TCP opens, and TLS handshakes are diagnostic evidence only, not proof that traffic traverses the VPN tunnel.

## CI / artifact evidence
- Baseline main run 1393 (`44785612381`) succeeded for source guard, Flutter tests, Dart analysis, arm64 release APK build and artifact upload; debug-key signing only.
- Run 1924 (`44956105111`) succeeded for an earlier checkpoint; artifact is historical.
- Run 1925 (`44984275812`) succeeded for older code `d284f9d40b7fd7057298625bd83200c75f326afc`: source guard, Flutter tests, Dart analysis, arm64 APK build, and artifact uploads passed. APK ZIP digest `sha256:836e6c5e97947bcd4beea4a44395cf37bdb5ac61efba887c7c44ddc952d2db30`; debug-key signed. It predates later cache and IPv6 fixes.
- Run 1928 (`44984479396`) for earlier checkpoint `4e8d08cd38d88e8441d55d38c3cb9a99af05d5f9`: source guard, Flutter tests, and Dart analysis passed; arm64 release APK build was still in progress at last poll.
- Run 1929 (`44984637534`) for cache-fix code head `ecd6b8b2533f5d61967b29eac2e9c4db90e33695` was cancelled before jobs ran.
- Run 1930 (`44984708185`) for docs checkpoint `6d1b8d469b6267bb689fa56bf4eefbaa0b2e4023` remained pending with no jobs at last poll.
- Current head `7b8aa6d85e8201acaf9d123e6474c905f2facecb` has no GitHub check-runs or workflow runs yet. Do not claim the new native guard or cache regression tests passed until a run actually executes.
- No real device, production signing, inner-APK metadata/checksum inspection, or Iranian operator-network validation has been performed. Current branch is not declared install-ready.

## Engineering guardrails
- Preserve IP Clean sources, ranges, ports and scan capabilities; no arbitrary limits without evidence and tests.
- Preserve IPv4 and IPv6 capability; do not infer Iranian IPv6 ASN ownership from country labels.
- Rank domestic endpoints by observed successful national traffic first; ASN/transport/CDN hints are weaker evidence.
- Do not add Gemini, Grok, paid APIs, or API-key-dependent AI services.
- Never call a build install-ready until the exact final source commit passes guards, Flutter tests, Dart analysis, arm64 build, APK metadata/checksum/signing verification, and device validation.
- Do not merge to `main` or cancel active CI runs without explicit authorization.

## Next actions
1. Get a non-cancelled CI run for current head `7b8aa6d85e8201acaf9d123e6474c905f2facecb`; verify the new Python source guard, all Flutter tests, Dart analysis, and arm64 build.
2. Poll run 1928 for build completion and artifact metadata; treat it as older source only.
3. Continue DNS path audit, including whether resolver traffic traverses the intended core and whether IPv4/IPv6 can bypass the TUN.
4. Complete connect/stop/failover race review across Dart and `KingVpnService`.
5. If an exact-head APK is built, inspect the inner APK, ABI, package metadata, APK SHA-256 and signing status.
6. Validate national/global traffic on real operator networks separately; CI cannot establish this.
