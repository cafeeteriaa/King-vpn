# King VPN — mainline continuation checkpoint

## Current source of truth
- Repository: `cafeeteriaa/King-vpn`; base `main` HEAD: `c43d325f9803d4f6306415e511f6790deff9d87e`.
- Active branch: `codex/continuation-mainline-20261122`.
- PR #42 is open, Draft, targets `main`; do not merge without explicit authorization.
- Latest code commit: `e5274e6d3ba600bb2d5c18c963b298765169dbe1` (tests for probe-cache policy).
- Latest branch HEAD before this documentation refresh: `c07c4ac492c41825906c7506ae47e95455f92be8`.
- The previous domestic-ranking branch remains separate; last comparison showed 103 commits ahead of main. PR #41 remains a separate draft targeting another feature branch. Do not merge or retarget it without full diff review.

## Current engineering change
- Audit found both `NatNetworkDiagnosis` and `PilotNetworkProbe` could reuse cached network classification when local interface identity lookup returned an empty string. Two unavailable identity reads compared equal, allowing stale evidence to be reused for the TTL. A backwards system-clock adjustment could also make an old cache appear fresh.
- Added pure helper `shouldReuseNetworkProbeCache` in `lib/network_health.dart`. Cache reuse requires: not forced, current and cached identities both non-empty and equal, a timestamp, and age >= 0 and below TTL.
- Updated both cache paths in `lib/national_engine.dart`.
- Added five focused tests in `test/network_health_test.dart`: valid matching identity, empty current identity, missing prior identity, expired/backwards-clock timestamp, and force refresh.
- This change prevents reuse of untrustworthy classification evidence; it does not itself prove VPN tunnel reachability or change core routing.

## CI / build evidence (live state at checkpoint)
- Baseline main commit `c43d325f9803d4f6306415e511f6790deff9d87e`: run 1393 (`44785612381`) succeeded, including source guards, Flutter tests, Dart analysis, Android arm64 release APK build and artifact upload. Artifact was signed with generated Flutter debug key, not production signing.
- Initial PR documentation checkpoint `c415a79a9a823468900cd4a24697177a66030bb0`: run 1924 (`44956105111`) succeeded, including tests, analysis, arm64 APK build and artifact upload. Artifact `king-vpn-arm64-release-1924`, ID `14728245424`, ZIP size 49,012,354 bytes. ZIP digest: `sha256:0ce47451f06f757f84e0e49b0313334c2cbf021dcd192203ae3ef751e1a8a1f0` (not the inner APK digest). Debug-key signing only.
- Code commit `d284f9d40b7fd7057298625bd83200c75f326afc`: run 1925 (`44984275812`) is still in progress at this checkpoint. Source guard, Flutter unit tests, and Dart analysis completed successfully; arm64 release APK build remains in progress, no artifact yet. This run predates the additional five cache-policy tests.
- Test commit `e5274e6d3ba600bb2d5c18c963b298765169dbe1`: run 1926 (`44984280781`) was cancelled with no jobs, so the five new tests are not yet independently CI-verified.
- Current PR head before this documentation refresh `c07c4ac492c41825906c7506ae47e95455f92be8`: run 1927 (`44984312895`) is pending with no jobs at last inspection. Do not claim tests/build passed for the latest head until a completed run verifies it.
- No real device, production signing, or Iranian operator-network connectivity test has been performed.

## Engineering guardrails
- Preserve IP Clean sources, ranges, ports and scan capabilities; do not add arbitrary limits without device-safety evidence and tests.
- Preserve IPv4 and IPv6 reachability/routing. Do not infer Iranian IPv6 ASN ownership from country labels.
- Rank domestic endpoints by observed successful national traffic first; ASN/transport/CDN hints remain weaker evidence.
- DNS replies, TCP opens, and TLS handshakes are diagnostic evidence only; none alone proves traffic is traversing the VPN tunnel.
- Do not add Gemini, Grok, paid APIs, or API-key-dependent AI services.
- Never call a build install-ready until the exact final source commit passes source guards, Flutter tests, Dart analysis, arm64 release build, and APK package/checksum/signing verification. A debug-key APK is not a production-signed release.
- Do not merge to `main` or cancel active CI runs without explicit authorization.

## Next work
1. Poll run 1925 and 1927; verify whether the APK build and exact-head tests finish, and inspect artifacts/logs.
2. Ensure the five new cache-policy tests execute on a non-cancelled run.
3. Continue end-to-end audit of `lib/main.dart`, `lib/national_engine.dart`, `lib/network_health.dart`, DNS resolver policy, and Android VPN plugin/service lifecycle.
4. Verify DNS policy is applied to the active core and IPv4/IPv6 DNS cannot silently fall back to an unintended direct path.
5. Trace tunnel drop through failover/reconnect; verify stale timers and overlapping connect/disconnect requests cannot race.
6. Review native `vpn/bg` channel registration and plugin initialization against the previously observed MissingPluginException.
7. Verify APK inner file, ABI, package metadata, APK SHA-256 and signing status before any installation claim.
8. Validate domestic/global traffic on real operator networks separately; CI cannot prove this.
