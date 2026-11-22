# King VPN — mainline continuation checkpoint

## Source of truth
- Repository: `cafeeteriaa/King-vpn`; base `main` HEAD: `c43d325f9803d4f6306415e511f6790deff9d87e`.
- Active branch: `codex/continuation-mainline-20261122`.
- Current code HEAD: `ecd6b8b2533f5d61967b29eac2e9c4db90e33695`.
- PR #42 remains open, Draft, targeting `main`; do not merge without explicit authorization.
- PR #41 / the domestic-ranking feature branch remains separate and unmerged; do not retarget or merge without a full diff audit.

## Network-probe cache correctness
- Original audit found both `NatNetworkDiagnosis` and `PilotNetworkProbe` could reuse stale classification when interface identity lookup returned an empty string; backwards clock movement also needed to invalidate cache.
- A follow-up audit found the first helper version still omitted the critical equality check between current and cached network identities. This meant a change from network A to network B could incorrectly reuse network A's evidence.
- Fixed `shouldReuseNetworkProbeCache` in `lib/network_health.dart`: reuse now requires `!force`, both identities known and non-empty, exact identity equality, non-null timestamp, and age >= 0 and below TTL.
- Applied helper to both cache paths in `lib/national_engine.dart`.
- Added six focused tests in `test/network_health_test.dart`: matching identity hit; empty current identity; missing cached identity; changed network identity; expired/backwards-clock cache; forced refresh.
- Implementation commits: `d284f9d40b7fd7057298625bd83200c75f326afc`, `e5274e6d3ba600bb2d5c18c963b298765169dbe1`, `11841a8df4afaf0135b91db9369216ba73da8c5e`, `ecd6b8b2533f5d61967b29eac2e9c4db90e33695`.
- This only protects network-classification cache correctness. It does not prove tunnel traffic or alter routing policy.

## Audit notes
- Active-branch `android_src/MainActivity.kt` registers `vpn/bg` in `configureFlutterEngine` and includes `alive`, `back`, and `vpnSettings`; source inspection found no missing handler in this branch. Device/runtime reproduction of the historical MissingPluginException is still required.
- `_reliableVpnCfg` applies national DNS preference and sets query strategy, but static source inspection alone cannot prove the selected core applies the DNS policy or prevent every platform/core fallback. Verify using runtime logs and controlled IPv4/IPv6 leak tests.
- Dart stop logic waits for DISCONNECTED with a timeout and marks `_staleCoreMayBeUp` if shutdown cannot be confirmed; late CONNECTED is traffic-verified. Continue race review rather than changing failover blindly.
- DNS replies, TCP opens and TLS handshakes remain diagnostic evidence only, not proof that traffic traverses the VPN tunnel.

## CI / artifact evidence
- Baseline main run 1393 (`44785612381`) succeeded, including source guard, Flutter tests, Dart analysis, Android arm64 release APK build and artifact upload. Debug-key signing only.
- Run 1924 (`44956105111`) succeeded for an earlier checkpoint; artifact ZIP digest and metadata are historical and do not validate current source.
- Run 1925 (`44984275812`) for code commit `d284f9d40b7fd7057298625bd83200c75f326afc` completed successfully. Source guard, Flutter tests, Dart analysis, optimized arm64 APK build, symbols/source ZIP and APK artifact uploads all succeeded. APK artifact: `king-vpn-arm64-release-1925`, ID `14738628280`, ZIP size 49,012,262 bytes, ZIP digest `sha256:836e6c5e97947bcd4beea4a44395cf37bdb5ac61efba887c7c44ddc952d2db30`. This run predates the network-identity mismatch guard and the sixth test. It was debug-key signed, not production-signed.
- Run 1928 (`44984479396`) for docs checkpoint `4e8d08cd38d88e8441d55d38c3cb9a99af05d5f9` was in progress at last poll.
- Run 1929 (`44984637534`) is for code HEAD `ecd6b8b2533f5d61967b29eac2e9c4db90e33695`; pending at last poll. This is the first CI run expected to execute the new identity-mismatch regression test. Do not claim it passed until completed.
- No real device, production signing, APK inner-file verification, or Iranian operator-network test has been performed. No current commit is declared install-ready.

## Engineering guardrails
- Preserve IP Clean sources, ranges, ports and scan capabilities; no arbitrary limits without evidence and tests.
- Preserve IPv4 and IPv6 reachability. Do not infer Iranian IPv6 ASN ownership from country labels.
- Rank domestic endpoints by observed successful national traffic first; ASN/transport/CDN hints remain weaker evidence.
- Do not add Gemini, Grok, paid APIs or API-key-dependent AI services.
- Never call a build install-ready until exact final source commit passes guards, tests, analysis, arm64 build, APK metadata/checksum/signing verification, and device validation.
- Do not merge to `main` or cancel active CI runs without explicit authorization.

## Next actions
1. Poll run 1929 for the exact code HEAD and inspect tests, analysis, APK build and artifacts.
2. Poll run 1928 and inspect the arm64 build/artifact if it completes.
3. Continue end-to-end DNS policy audit, especially whether DNS is resolved through the intended core path and whether IPv4/IPv6 can leak outside the tunnel.
4. Complete connect/stop/failover race audit across Dart and `KingVpnService`; preserve the existing stop-race guards unless a reproducible defect is established.
5. If CI succeeds, inspect APK archive contents, inner APK metadata, ABI and SHA-256; signing remains debug-key unless a production key is configured.
6. Validate national/global traffic on real operator networks separately; CI cannot establish this.
