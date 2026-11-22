# King VPN — mainline continuation checkpoint

## Current source of truth
- Repository: `cafeeteriaa/King-vpn`
- Default/base branch: `main`, HEAD `c43d325f9803d4f6306415e511f6790deff9d87e`.
- Active continuation branch: `codex/continuation-mainline-20261122`.
- Current branch HEAD before this checkpoint refresh: `e5274e6d3ba600bb2d5c18c963b298765169dbe1`.
- PR #42: open Draft, targets `main`; do not merge without explicit authorization.
- The old domestic-ranking branch remains separate. It is 103 commits ahead of main (last comparison), and PR #41 is still a separate draft targeting a feature branch. Do not merge or retarget it without auditing its full diff.

## Current engineering change
- Audit found both `NatNetworkDiagnosis` and `PilotNetworkProbe` could reuse a cached classification when the local network identity lookup returned an empty string. In that failure case, two unavailable identity reads compared equal and could keep stale network evidence for the full cache TTL. A backwards system-clock adjustment could also make a cache appear younger than it is.
- Added pure helper `shouldReuseNetworkProbeCache` in `lib/network_health.dart`. It allows reuse only when current and cached identities are both non-empty and equal, timestamp exists, cache age is non-negative and below TTL, and force is false.
- Updated both cache paths in `lib/national_engine.dart` to use the helper.
- Added five focused policy tests in `test/network_health_test.dart`: valid same-network hit, empty current identity, missing prior identity, expired/backwards-clock cache, and forced refresh.
- This is a conservative cache correctness fix. It does not claim to prove tunnel traffic or alter VPN routing policy.

## CI and build evidence
- Baseline main commit `c43d325f9803d4f6306415e511f6790deff9d87e`: run 1393 (`44785612381`) completed successfully; source guards, Flutter tests, Dart analysis, Android arm64 release APK build, and artifact upload passed.
- Baseline APK was signed with a generated Flutter debug key, not a production signing key. No real device/operator network test is claimed.
- PR checkpoint commit `c415a79a9a823468900cd4a24697177a66030bb0`: run 1924 (`44956105111`) completed successfully, including tests, analysis, arm64 APK build and artifact upload. Artifact: `king-vpn-arm64-release-1924`, ID `14728245424`, archive size 49,012,354 bytes. The artifact digest `sha256:0ce47451f06f757f84e0e49b0313334c2cbf021dcd192203ae3ef751e1a8a1f0` is for the artifact ZIP, not the inner APK. Debug-key signing remains.
- Current code commit `e5274e6d3ba600bb2d5c18c963b298765169dbe1`: CI run 1926 (`44984280781`) was pending at last inspection. No test/build success is claimed for this code change until this run finishes.
- Feature branch PR #41 run 1919 (`44955779075`) later completed successfully for its implementation commit `7b9da526df4f81a8faf2d7d6ae2e213506c88550`; it does not validate mainline code or the current continuation branch.
- No operator-level Iranian network connectivity or real-device validation has been performed.

## Engineering guardrails
- Preserve IP Clean sources, ranges, ports and scan capabilities; avoid arbitrary limits unless justified and tested.
- Preserve IPv4 and IPv6 routing/reachability. Do not infer Iranian IPv6 ASN ownership from country labels.
- Rank domestic endpoints using observed successful national traffic first; ASN/transport/CDN hints remain weaker evidence.
- DNS replies, TCP opens, and TLS handshakes are diagnostic evidence only; none alone proves VPN tunnel traffic.
- Do not add Gemini, Grok, paid APIs, or API-key-dependent AI services.
- Never call a build install-ready until the exact final source commit passes source guards, Flutter tests, Dart analysis, arm64 release build, and APK artifact/package/checksum/signing verification. A debug-key build is not a production-signed release.
- Do not merge to main or cancel active CI runs without explicit authorization.

## Next work
1. Confirm run 1926 for the cache correctness fix; inspect test, analysis, APK build and artifacts.
2. Continue the end-to-end audit of `lib/main.dart`, `lib/national_engine.dart`, `lib/network_health.dart`, DNS resolver policy, and Android VPN plugin/service lifecycle.
3. Verify DNS policy is actually applied to the active core and that IPv4/IPv6 resolution does not silently fall back to an unintended direct path.
4. Trace tunnel drop through failover/reconnect; verify stale timers and overlapping connect/disconnect requests cannot race.
5. Review native `vpn/bg` channel registration and plugin initialization against the previously observed MissingPluginException class of failure.
6. Verify APK inner file, ABI, package metadata, APK SHA-256 and signing status before any installation claim.
7. Validate domestic/global traffic on real operator networks separately; CI cannot prove this.
