# King VPN — continuation checkpoint

## Current active workstream — 2026-11-25
- Repository: `cafeeteriaa/King-vpn`.
- Current engineering branch: `feature/king-fusion-engine-foundation-20261125`.
- Current pull request: #53, open Draft, targeting `feature/king-vpn-audit-hardening-20261125`; do not merge automatically.
- The older PR #48 / DNS scanner checkpoints below are retained as historical project context and are not the active branch for this Fusion workstream.
- Main remains at the previously recorded commit `c43d325f9803d4f6306415e511f6790deff9d87e`; no feature changes are intended for main.
- Keep the existing `lib/main.dart` Flutter V2Ray connection path intact until a separately reviewed, tested adapter integration is ready.


## Source of truth
- Latest checkpoint recorded below supersedes older status summaries; historical checkpoints are retained for traceability.
- Repository: `cafeeteriaa/King-vpn`
- Active VPN feature branch: `fix/dns-auto-full-domain-inventory-20261124`
- Historical checkpoint below: `647eea8feac0b34d3b66f24cfd399ed14f55e11e`. For the latest authoritative state, see the newest dated CI checkpoint at the end of this file.
- PR #48 remains open Draft against `audit/unlimit-known-scanner-candidates-20261123`; no merge to `main`.
- No active GitHub Actions at repair preparation. No workflow was cancelled.

## Changes in this checkpoint
- Restored the complete default TCP-connect inventory test: 65,535 ports (1..65535), with port 0 still available through explicit `firstPort: 0`.
- Restored the matching `natBuildFullPortInventory` documentation.
- Added `android.permission.ACCESS_NETWORK_STATE` to the generated Android manifest permissions. The new `ConnectivityManager.getNetworkCapabilities` ownership check requires this permission.
- Added a source guard ensuring the permission is declared.
- The previous Android native tunnel ownership code remains unchanged: service-owned live TUN descriptor + active VPN transport owner UID on Android 11+; Dart requires both signals and fails closed on Android if native proof is unavailable.
- No IP Clean sources, ranges, ports, UDP inventory, or scan capabilities were removed or narrowed.

## Validation evidence
- Parent native-ownership commit `d6b901bd96b67d69ab164151cfbf0ff42ef6ba64`, CI run 2554: source-guard step failed due two assertions expecting a one-line `if` while the code used a braced block; Flutter tests/analyze/build were skipped: https://github.com/cafeeteriaa/King-vpn/actions/runs/45356296860
- Source-guard-only repair commit `647eea8feac0b34d3b66f24cfd399ed14f55e11e`, CI run 2555: source guards passed; Flutter tests reported 150 passed / 1 failed. The sole failure was the stale default port inventory assertion (expected 65,536 including port 0); analyze/build were skipped: https://github.com/cafeeteriaa/King-vpn/actions/runs/45356528430
- The stale test/doc regression occurred because the prior documentation-only tree was created from an older base tree and unintentionally restored those two files. This checkpoint is based on the actual current HEAD tree and repairs both files; no production port-scan logic is changed.
- The ACCESS_NETWORK_STATE declaration is supported by Android's ConnectivityManager API reference, which documents that `getNetworkCapabilities` requires this permission: https://developer.android.com/reference/android/net/ConnectivityManager
- Exact-head CI for this checkpoint is pending; do not claim the Android ownership change or this repair validated until source guards, Flutter tests, analyze, and ARM64 build pass.

## Open limitations
- Android 11+ owner UID is checked. Android 10 and older use the custom service's live TUN descriptor plus active VPN transport.
- Native evidence proves service/TUN ownership, not end-to-end traffic. HTTP response verification remains a separate gate.
- No physical-device, competing-VPN, Android 10/11+, Iranian carrier, DNS packet-capture, or live IPv4/IPv6 data-plane test has been performed.
- DNS route/leak, native stop/start ordering, failover races, IPv6 data-plane, and CPU/battery profiling remain open.
- Branches `fix/dns-auto-full-domain-inventory-20261124` and `audit/final-master` remain heavily diverged; do not merge wholesale.

## First next action
1. Run exact-head CI for this checkpoint; require source guards, all Flutter tests, `flutter analyze`, and ARM64 release build to pass.
2. If successful, inspect the exact-head artifact and checksum.
3. Then perform physical-device tests for competing VPN takeover, stop/revoke, Android 10 compatibility, Android 11+ owner UID, network handover, and DNS routing through TUN/core.


## Chat-submitted scanner review checkpoint — 2026-11-24

- User supplied a standalone Dart snippet named `KingUltimateScanner` (`part of 'main.dart';`) for review.
- The snippet has **not** been integrated into `lib/main.dart` or committed as executable scanner code. It is an intake/review checkpoint only, so the submitted implementation must not be mistaken for an existing project module.
- Static review recorded the following issues to avoid repeating the same audit:
  - Part-file structure/import placement must be reconciled with the owning Dart library.
  - `X509Certificate.subjectAltNames` is not part of the standard Dart `X509Certificate` API.
  - Start/stop lifecycle can race because `isRunning` is cleared before active work has fully exited.
  - UDP probe does not consume the received datagram and does not reliably close its socket on all paths.
  - DNS response parsing validates only a weak length/count condition and does not validate transaction ID, flags, question, or answer records.
  - IPv6 targets are not consistently supported by the IPv4-bound UDP socket.
  - SNI extraction does not explicitly supply the intended TLS hostname.
  - CDN request construction does not correctly bracket IPv6 literals and does not preserve the parsed endpoint port.
  - HTTP client/socket cleanup is incomplete on exceptional paths.
  - Manual text controllers are not disposed; counters omit some probe categories.
- No scanner algorithm, inventory, range, port list, or user-selected scan behavior has been changed by this checkpoint.
- Next step when explicitly requested: reconcile the snippet with the actual project symbols and Dart/Flutter APIs, fix compile/runtime defects, add focused tests, then commit the reviewed integration to this PR branch. Keep PR #48 open and Draft; do not merge or modify `main`.


## Automatic scanner candidate-inventory checkpoint — 2026-11-24

- Commit `12444d24572ca91c54dc7b25a650b301dc1a30db` adds independent persistent SNI/IP candidate inventories to `lib/auto_scanners.dart`.
- Domain candidates are assembled from `kAutoSniDomains`, `dnsxFullDomains()`, `natFrontSnis` and `natRelayHosts`; saved-server hostnames are optional additional inputs, not the only source.
- IP candidates combine existing global-folder IP observations, dual-stack DNS A/AAAA answers and the current bounded CDN-range inventory batch.
- Candidates are stored separately as `sni_candidates` and `ip_candidates`, shown in both automatic scanner and global-folder UI, and can be copied without being mislabeled as healthy endpoints.
- Active SNI/TLS/TCP checks remain restricted to exact saved KING VPN endpoint scope. Discovery and active validation are deliberately separate.
- Added a source guard for independent candidate persistence and display.
- CI run 2562 passed all source guards, Flutter tests, Dart analysis and ARM64 release build. Exact-head CI for the candidate inventory changes was queued as run 2565 at checkpoint time; do not claim it passed until it completes.
- PR #48 remains open Draft, not merged; `main` is unchanged. No physical-device tunnel verification is claimed.

## 2026-11-24 — Independent IP scanner inventory follow-up

- Extended `lib/ip_auto_scan.dart` so passive IPv4/IPv6 candidate discovery no longer depends on saved or fetched VPN server configurations.
- Candidate sources are the complete project SNI/domain catalogs (dual-stack DNS A/AAAA answers), global-folder IP observations, and the rotating CDN range inventory; candidates merge into the existing persistent `ip_candidates` inventory.
- Reuses resumable domain/CDN cursors; per-run batching is resumable and does not cap the accumulated inventory.
- The IP scanner UI now loads, displays, and copies the full persisted candidate inventory when opened.
- Active TCP and two-pass VPN-core checks remain separate and restricted to exact endpoint IP:port pairs derived from VPN server records. Passive candidates are not promoted to endpoint hits, healthy servers, or verified tunnel routes.
- If no endpoint configuration exists, independent candidate discovery still completes and persists; active validation is skipped rather than blocking discovery.
- Added source guard `test_ip_auto_scanner_discovers_dual_stack_candidates_without_saved_servers`.
- CI run 2566 passed for the preceding source state. CI for this follow-up code/test commit is pending; do not claim it passed until the exact final HEAD completes.
- Device-level VPN/TUN verification remains outstanding.

PR #48 remains open and Draft; do not merge or modify `main`.


## 2026-11-24 — Exact-head validation and next engineering gate

- Current validated branch head at this checkpoint: `e5e0f9fa7df4553dc7990cbb960bb4d2f37693e0`.
- PR #48 is still open and Draft, targeting `audit/unlimit-known-scanner-candidates-20261123`; keep it unmerged and do not modify `main`.
- Exact-head GitHub Actions run 2576 (`45420351690`) completed successfully. The source-repair guard, Flutter dependency resolution, unit tests, Dart analysis, ARM64 Release APK build, source ZIP packaging and artifact uploads all completed successfully. Diagnostic-only steps were skipped as expected.
- ARM64 APK artifact: `king-vpn-arm64-release-2576`, 49,061,061 bytes; SHA-256 `c02cb2c2c876e03ebca3034664be4369900bbc2ed2e457cf352505b5ef40dafb`. Artifact expires 2026-12-08.
- Full source artifact: `king-vpn-full-source-2576`, 1,510,830 bytes; SHA-256 `48861bf52ee6d391a62fdee5db9159cc883d605495bc05578f4ff48defb8d726`.
- Static follow-up reviewed the exact-head Android tunnel evidence path: the optional custom service requires its live TUN descriptor plus an active VPN transport; on Android 11+ an available owner UID must also match this app. The default plugin path requires an active VPN transport owned by this app. Missing native evidence fails closed on Android.
- Static follow-up also confirmed that `_tunnelTrafficOk()` rejects proxy-only mode, requires positive Android tunnel evidence, and then performs an HTTP request through the core proxy to a mode-appropriate destination. Endpoint discovery records remain separate from healthy-route acceptance.
- These checks are code/CI evidence only. They do not establish physical-device connectivity, end-to-end data-plane correctness, DNS leak freedom, IPv6 traffic, failover stability, competing-VPN takeover, or CPU/battery behavior.
- Next actions: obtain device test evidence for Android 10 and Android 11+, competing VPN ownership, stop/revoke and network handover; capture DNS and IPv4/IPv6 traffic through the TUN; test real tunnel responses and failover; profile CPU, memory and battery. Do not mark these as TESTED until evidence is recorded.


## 2026-11-24 — Front-SNI evidence and UDP scope clarification

- Front-SNI probe in `lib/nip_scan.dart` now accepts every syntactically valid HTTP status (100..599) as evidence that the TLS/SNI request reached an HTTP peer. HTTP 4xx/5xx responses are not treated as proof of a usable VPN route; central core/TUN traffic acceptance remains authoritative.
- Added source guard `test_front_sni_probe_accepts_all_valid_http_statuses`.
- Follow-up review found that `natBuildFullUdpPortInventory` generates the complete UDP port-number inventory only. It does not send datagrams, consume UDP responses, or validate UDP reachability; no caller of this helper was found in the reviewed `lib/nat_ultra.dart` path. UDP protocol probing is therefore NOT_IMPLEMENTED / NOT_TESTED and must not be represented as UDP-tested.
- Clarified the UDP inventory contract in `lib/nat_ip_scan.dart`, renamed the broad inventory test to avoid implying reachability, and added a source guard that protects the distinction.
- Commits: front-SNI source fix `553ce7e6650fb70228243fa6cedfd6fb7966ea12`; front-SNI guard `f874ce6fb34b14dac0356af035f8912bf54a65ac`; UDP inventory clarification `931795d76f3f9def8773179c6720ead4a77994ca`; UDP scope guard `c883fe52a1f55e1c4678f1ccf9c251013a10585a`.
- CI run 2577 (`45435575873`) for the earlier documentation checkpoint `65b2306b16200b51c9b8b12b017f8b7fa7ac28c8` completed successfully: source guard, Flutter unit tests, Dart analysis, ARM64 release APK, source package and artifact uploads passed. This result does not validate later code commits.
- CI run 2578 (`45436621353`) was triggered for the front-SNI fix commit and reached ARM64 release APK build after source guards, Flutter unit tests and Dart analysis passed. At this checkpoint it remained in progress; its final result and artifacts are not yet confirmed. It does not include the subsequent UDP documentation/guard commits.
- Current branch head at checkpoint: `c883fe52a1f55e1c4678f1ccf9c251013a10585a`. Exact-head CI has not yet appeared for this commit.
- PR #48 remains open Draft, base `audit/unlimit-known-scanner-candidates-20261123`; do not merge or modify `main`.
- Physical-device tests, end-to-end UDP, DNS leak, IPv4/IPv6 data-plane, competing VPN, failover and CPU/battery profiling remain outstanding.


## 2026-11-24 — Exact HEAD CI 2580 and engineering continuation

### Repository and release gate
- Repository: `cafeeteriaa/King-vpn`.
- Active branch: `fix/dns-auto-full-domain-inventory-20261124`.
- PR #48 remains open and Draft, base `audit/unlimit-known-scanner-candidates-20261123`; current PR HEAD at this checkpoint was `b6266f6008bd7edcffc9ef75ed6df51c0fce345e`. Do not merge, close, or modify `main`.
- Exact-HEAD CI run 2580 (`45437235722`) completed with conclusion SUCCESS on `b6266f6008bd7edcffc9ef75ed6df51c0fce345e`.
- All source-repair guard, Flutter unit tests, Dart analysis, ARM64 Release APK build, source packaging, APK/source/symbol uploads, and all Post-Job steps passed. Diagnostic-only steps were skipped as expected.
- ARM64 artifact: `king-vpn-arm64-release-2580`, 49,061,198 bytes; archive SHA-256 `1911ec3523da7891ee85717536a4809df6e25b1ed4289286bf2b8a864e3b952e`.
- Full source artifact: `king-vpn-full-source-2580`, 1,513,083 bytes; archive SHA-256 `1f9587e29ff2c593e4acbeca9475f5aeacabb4d0be1b56c05e1636cc456a07f5`.
- Symbols artifact: `king-vpn-symbols-2580`, 1,331,925 bytes; archive SHA-256 `8dcc36152cc59bfbdc81492e440c4418c2b3a59da14b91285182245277554df4`.
- CI run 2578 (`45436621353`) also completed SUCCESS, but it validates only its own earlier SNI commit `f874ce6fb34b14dac0356af035f8912bf54a65ac`; run 2580 is the exact-HEAD evidence.
- Artifact links and workflow logs: https://github.com/cafeeteriaa/King-vpn/actions/runs/45437235722
- CI evidence validates source/test/analyze/build only. It does not prove physical-device connectivity or live tunnel data-plane correctness.

### Static lifecycle and scanner audit carried out on exact HEAD
- `natScanIps`: bounded worker count, monotonic Stopwatch budget, per-socket timeout, finally-based socket destruction, cancellation checks before dispatch and after in-flight connect, and hit-count enforcement at insertion. In-flight TCP connects cannot be forcibly cancelled by Dart's Socket.connect; they are bounded by the configured timeout.
- `dnsxProbe` / `NatDnsWireProbe.probe`: A and AAAA probes use UDP DNS requests; source address/port 53, transaction ID, QR/opcode, truncation, RCODE, question name/type/class, answer owner/CNAME chain, RDATA length and public-address validation are checked. Cancellation watcher, subscription cancellation, and RawDatagramSocket.close() are present.
- `dnsxScan`: bounded batches and cancellation propagation are present; manual UI does not persist partial results after cancellation.
- `_natRangeScanStepBody`: serial busy lock, mode snapshot, staged per-port/range cursors, and persistence-before-cursor-advance are present. Full TCP port inventory is used for explicitly configured IP Clean ranges; outside those ranges, configured endpoints are tested only on their declared ports.
- `autoScanRun`: scanner lock and stop flag, mode/VPN cancellation, batched domain and CDN cursors, exact configured endpoint targets, and commit-after-complete-batch behavior are present. Candidate inventories remain distinct from active endpoint observations and verified tunnel routes.
- `_ipAutoRunOnce`: passive IP candidate inventory is independent of saved servers and persists independently; active TCP and core tests are limited to exact IP:port pairs derived from current VPN server records. Generated active-scan cursors are committed only after the full endpoint TCP batch completes; core-verification backlog is stored separately.
- Android `KingVpnService`: serialized worker submission, attempt sequence fencing, coreLock/tunLock separation, bounded stop waits, deferred TUN close while native stop is unverified, foreground promotion on normal start/recovery, and stop/revoke cleanup paths are present in source. Static inspection is not a substitute for Android runtime tests.
- Generic UDP port reachability probing remains NOT_IMPLEMENTED / NOT_TESTED. The complete UDP port-number inventory helper only creates port numbers; the DNS resolver's UDP A/AAAA request is a separate, implemented protocol-specific UDP exchange.

### Open findings / constraints
- `CONTINUATION.md` had stale top-level checkpoint metadata. This section supersedes the older historical checkpoint statements for current status.
- Automatic SNI/TLS/port checks in `auto_scanners.dart` are currently restricted to saved VPN endpoint IP:port targets; automatic IP scanner active checks are likewise restricted to exact configured endpoint pairs. Passive candidate discovery still aggregates the project domain catalogs, dual-stack DNS answers, global-folder observations, and rotating CDN inventory. Explicit IP Clean ranges retain their own full TCP-port path. Do not silently expand or narrow these scopes; preserve user-defined scan behavior and obtain explicit target scope when active probing would reach unrelated third-party networks.
- No physical Android device test is recorded. Still outstanding: Android 10 and Android 11+ runtime ownership, VPN consent/revoke, competing VPN, TUN lifecycle under start/stop races, real end-to-end traffic, DNS leak capture, IPv4/IPv6 data-plane, failover, network handover, UDP protocol tests, and CPU/memory/battery profiling.
- No claims of DEPLOYED, device-tested, UDP-reachable, leak-free, or stable real-world connection are justified by CI alone.

### Next actions
1. Recheck PR HEAD and ensure any documentation update is committed only to the active feature branch; do not alter `main` or merge PR #48.
2. Run exact-HEAD CI after any new commit and retain artifact hashes.
3. Perform three independent reviews of scanner scope/cursor semantics, native TUN lifecycle/ownership, and tunnel traffic acceptance.
4. Execute physical-device test matrix and record each outcome separately as IMPLEMENTED / CI-TESTED / DEVICE-TESTED / DEPLOYED.
5. Design generic UDP probing only with explicit, user-authorized target scopes and protocol-aware response semantics; never label port inventory as reachability.


## 2026-11-24 — Exact HEAD CI 2581 and three-pass static review

### Exact-head CI evidence
- Exact HEAD: `df33e0a0ce8d96cfe3d4111dc6e82c4182ba8cbf` on `fix/dns-auto-full-domain-inventory-20261124`.
- GitHub Actions run 2581 (`45438946875`) completed with conclusion SUCCESS on this exact commit.
- Source-repair guard, Flutter dependency resolution, unit tests, Dart analysis, optimized ARM64 Release APK build, APK size reporting, source packaging, all three artifact uploads, and Post-Job cleanup completed successfully. Diagnostic-only steps were skipped as expected.
- ARM64 APK artifact: `king-vpn-arm64-release-2581`, 49,061,202 bytes; GitHub artifact archive digest `sha256:7c3363c67187837aaa5f390ec990b10ec620d4195c041fd706487d6bafc463bd`.
- Full source artifact: `king-vpn-full-source-2581`, 1,515,238 bytes; GitHub artifact archive digest `sha256:47533df239bc0d20d07b20efc7ad28111bde59c69759755650ab9084e82fffe8`.
- Symbols artifact: `king-vpn-symbols-2581`, 1,331,925 bytes; GitHub artifact archive digest `sha256:86b5ab33dbda5342776661e781b5f63b93db5d4358f481eba2881d2306c87060`.
- Artifacts expire 2026-12-08 (APK/source) and 2026-12-24 (symbols). Workflow: https://github.com/cafeeteriaa/King-vpn/actions/runs/45438946875
- CI validates this source tree, automated tests, analysis and packaging. It is not evidence of device-level connectivity, DNS leak freedom, IPv6 data-plane correctness or deployed status.

### Three focused static review passes on exact HEAD
These are three distinct technical review passes by the same assistant, not three independent external reviewers:
1. **Scanner scope and cursor semantics:** reviewed `autoScanRun`, `_ipAutoRunOnce`, `natScanIps`, and the TCP/UDP inventory helpers. Confirmed bounded TCP workers/timeouts, socket cleanup, cancellation checks, independent passive candidate persistence, full 1..65535 TCP port-number inventory, and active endpoint tests restricted to exact configured VPN endpoint pairs (with explicit IP Clean ranges handled separately). Candidate inventory remains distinct from endpoint reachability and verified tunnel status. No static blocker found in the inspected paths.
2. **Android native TUN lifecycle and ownership:** reviewed `KingVpnService` start/stop/revoke/destroy paths, attempt sequence fencing, `coreLock` / `tunLock`, native-stop verification, deferred TUN close, plus MainActivity's VPN transport and owner-UID probes. No static blocker found in the inspected paths; native timing, API-level behavior and races still require physical-device tests.
3. **Central tunnel traffic acceptance:** reviewed `tunUp()`, `androidVpnTunnelEvidence`, `_tunnelTrafficOk()`, `_siteOpens()`, and all `_onConnected` acceptance call sites/source guards. Proxy-only mode is rejected; Android tunnel evidence is required before HTTP acceptance; proxy requests are forced to fail rather than silently falling back to DIRECT when the core inbound is unavailable; HTTP success is separately required before a route is marked verified. No static blocker found in the inspected paths.

### Review and release status
- PR #48 remains open, Draft, and unmerged; base remains `audit/unlimit-known-scanner-candidates-20261123`. `main` remains untouched.
- GitHub currently reports no submitted PR reviews or inline review threads. Do not describe the three passes above as independent reviewer approvals.
- No code was changed during these review passes; this checkpoint records evidence only.
- Device tests remain NOT TESTED: Android 10 and 11+, VPN consent/revoke, competing VPN, TUN start/stop races, real end-to-end traffic, DNS capture/leaks, IPv4/IPv6 data-plane, failover, network handover, generic UDP protocol probes, and CPU/memory/battery profiling.
- Generic UDP port reachability remains NOT_IMPLEMENTED / NOT_TESTED. UDP port inventory is not UDP probing.

### Next gate
1. Keep PR #48 Draft and do not merge or modify `main`.
2. Run exact-HEAD CI after this documentation-only checkpoint commit and retain the resulting artifacts/digests.
3. Obtain real Android device and network-matrix evidence before marking any device-level behavior TESTED or DEPLOYED.
4. Preserve existing scanner behavior and user-selected ranges; any active probe beyond exact configured endpoints or explicit user-authorized ranges requires an explicit target scope.


## 2026-11-24 — Exact HEAD CI 2582 completion

### CI result
- Exact source commit: `ac6435c286e17bfc6c4df7156be68e9435a0ed3b` on `fix/dns-auto-full-domain-inventory-20261124`.
- GitHub Actions run 2582 (`45440202559`) completed with conclusion SUCCESS at 2026-11-24 16:47:29 UTC. Workflow: https://github.com/cafeeteriaa/King-vpn/actions/runs/45440202559
- Source-repair guard, dependency resolution, Flutter unit tests, Dart analysis, optimized ARM64 release APK build, APK size reporting, symbols packaging/upload, complete source packaging/upload, APK upload, and post-job cleanup all succeeded. Repair diagnostics were skipped because the build succeeded.
- Build log reports the APK as 123.0 MB. Artifact archive `king-vpn-arm64-release-2582`: 49,061,209 bytes; GitHub archive digest `sha256:eb068b57723052eeb1c7c1a9232bdc57066bb9af43f73dcc9c018f5c743e6ac8`.
- Full source artifact `king-vpn-full-source-2582`: 1,516,389 bytes; archive digest `sha256:7b271ecf66804b331f1eccf84bcd0054b0b43f5575ff99f5eb978d93a9bc1900`.
- Symbols artifact `king-vpn-symbols-2582`: 1,331,925 bytes; archive digest `sha256:6eec144e0f4f0a17fea04dec4f4831da8f071741271191fb85d9ae24dba31f70`.
- APK and source artifacts expire 2026-12-08; symbols expire 2026-12-24. All artifacts were present and unexpired at verification.
- Workflow explicitly reports signing with generated Flutter debug key; this is not production-signed. CI success does not establish device-level connectivity, leak freedom, or deployment.

### Build-log observations (not build blockers)
- Flutter analysis emitted informational deprecation notices for `package:flutter/material.dart` migration and `withOpacity`; analyze still passed under configured no-fatal-infos policy.
- Java compiler warned that source/target 8 are obsolete; several plugins reported deprecated APIs; workflow actions setup-java@v4 / upload-artifact@v4 / checkout@v4 / setup-gradle@v4 emitted Node.js 20 deprecation notices.
- Build log noted generated ELF libraries contain unobfuscated DWARF debugging information. This requires a deliberate symbols/packaging review before production release; do not silently strip or alter build flags in this continuation.
- APK reported size is 123.0 MB while the uploaded ZIP artifact is 49,061,209 bytes; these are different measurements (uncompressed APK vs compressed artifact archive), not contradictory sizes.

### Repository and release gate
- PR #48 remains open, Draft, and unmerged; base `audit/unlimit-known-scanner-candidates-20261123`.
- Feature branch HEAD remains `ac6435c286e17bfc6c4df7156be68e9435a0ed3b`; main remains `c43d325f9803d4f6306415e511f6790deff9d87e` and was not modified.
- No code changes were made in this continuation; this entry records the exact-head CI evidence only.
- Device runtime verification remains NOT TESTED: Android 10/11+, VPN consent/revoke, competing VPN, TUN lifecycle races, end-to-end traffic, DNS leak capture, IPv4/IPv6 data plane, failover, network handover, generic UDP reachability, and CPU/memory/battery profiling.
- Production signing and production deployment remain NOT DONE.

### Next actions
1. Continue with device/runtime test matrix when a physical Android device and controlled test networks are available.
2. Review 123 MB APK size, ELF DWARF/debug-symbol handling, Java 8 compatibility and deprecated workflow actions as separate evidence-led maintenance tasks; avoid changing release semantics without validation.
3. Keep PR #48 Draft and do not merge to main until required review, device validation, and release signing gates are complete.


### 2582 APK archive integrity spot-check
- Downloaded the exact GitHub artifact ZIP `king-vpn-arm64-release-2582` (artifact ID `14943536256`) and independently recomputed its SHA-256: `eb068b57723052eeb1c7c1a9232bdc57066bb9af43f73dcc9c018f5c743e6ac8`, matching GitHub's artifact digest.
- Inspected the ZIP: it contains exactly `app-arm64-v8a-release.apk`, uncompressed size 122,951,294 bytes. Independently computed APK SHA-256: `d49b6380c973850eec803e971e52017cc1157606e6897c952fef94d9da4ca9cb`.
- This verifies archive integrity and the expected APK payload, not Android installation, signature trust, or runtime VPN behavior. The workflow log states the APK was signed with the generated Flutter debug key, not a production key.


## 2026-11-24 — Exact HEAD CI 2583 and APK artifact verification

### Exact-head CI
- Source commit tested: `6b1859b8144285e158d661d6d74b70c781bd9430` on `fix/dns-auto-full-domain-inventory-20261124`.
- GitHub Actions run 2583 (`45441336928`) completed SUCCESS at 2026-11-24 16:53:01 UTC: https://github.com/cafeeteriaa/King-vpn/actions/runs/45441336928
- Source Guard, Flutter dependency resolution, unit tests, Dart analysis, optimized ARM64 release build, APK size report, symbols/source/APK artifact uploads, and all post-job cleanup passed. Diagnostic-only repair steps were skipped as expected.
- ARM64 artifact `king-vpn-arm64-release-2583` (artifact ID `14943194110`): 49,061,200 bytes; GitHub archive digest `sha256:35b3bfca454c24f86342f303d156cd1c776e0d83a665a511be18cfe489a5e87e`.
- Full source artifact `king-vpn-full-source-2583` (artifact ID `14943707072`): 1,517,566 bytes; archive digest `sha256:7d436c6d87c2185f6277470991885dca1116777c45e16d1a5ce72cb959c50b14`.
- Symbols artifact `king-vpn-symbols-2583` (artifact ID `14943841865`): 1,331,925 bytes; archive digest `sha256:9a03d6f4dc171b08977328d5bcfb3837d2ac29649c40608221e5b82f0ff39dc2`.
- Downloaded the ARM64 ZIP and independently verified its SHA-256 against GitHub's digest. The ZIP contains exactly `app-arm64-v8a-release.apk` (122,951,294 bytes); independently computed APK SHA-256: `69f4b809d1b63c94959bb6447417e812dd243f981dce1adecb312969530fdf51`.
- Workflow log reports APK size 123.0 MB. The compressed artifact archive size and uncompressed APK size are different measures.

### Build observations
- Non-blocking notices remain: Flutter Material API and `withOpacity` deprecations, Java source/target 8 obsolescence, deprecated plugin APIs, Node.js 20 action deprecation notices, and generated ELF DWARF debug information. No build flags or runtime dependencies were changed in response.
- The APK is generated with the workflow's Flutter debug key; it is not production-signed. Archive integrity and CI success do not prove installation, live tunnel operation, or leak freedom.

### Repository state and exact-head follow-up
- At the time of this checkpoint, PR #48 is open, Draft, and unmerged; base remains `audit/unlimit-known-scanner-candidates-20261123`.
- Feature branch HEAD after the prior documentation checkpoint was `079db875fb51c7cd900f39fef7b0c28df09aa580`; `main` remains `c43d325f9803d4f6306415e511f6790deff9d87e` and was not modified.
- Run 2583 validates its exact source commit `6b1859b...`, not the later documentation-only HEAD. Run 2584 (`45441562865`) was triggered for `079db875...` and was in progress at checkpoint time. After this documentation edit, require a new exact-HEAD CI run for the new HEAD as well.
- No executable code or scanner scope changed in this checkpoint. Keep PR #48 Draft and do not merge to `main`.
- Physical-device runtime checks, production signing, and production deployment remain NOT TESTED / NOT DONE.


## 2026-11-24 — Android 7–10 VPN ownership fallback

- Static audit found that the default plugin path could never satisfy the ownership gate on API 24–29: `NetworkCapabilities.ownerUid` is only available from API 30, while `minSdk` is 24.
- Repaired `kingVpnTransportOwnedByApp` on API 24–29 by requiring both an active `TRANSPORT_VPN` network and `VpnService.prepare(this) == null`. Android grants VPN preparation to one application at a time and revokes the previous grant when another VPN app is selected. Android 11+ continues to use `ownerUid` directly.
- The result remains fail-closed: no active VPN transport means false; a missing VPN grant means false. The existing Dart acceptance policy still requires both transport and ownership evidence, and the separate core-proxy traffic check remains in place.
- Added an isolated source-guard test for API 24–29 fallback, API 30+ owner UID, minimum SDK preservation and the existing competing-VPN rejection tests.
- Validation is source-only until exact-head CI and physical Android tests complete. VPN revoke/takeover, API 24–29 device tests, end-to-end traffic and DNS leak checks remain NOT TESTED.


## 2026-11-24 — Live TCP probe cancellation and monotonic pre-scan budget

- Replaced `Socket.connect` in the shared NAT TCP probe with `Socket.startConnect` and `ConnectionTask.cancel()`. In-flight probes now stop within the cancellation watcher interval instead of waiting for the full socket timeout.
- The main NAT scanner passes a combined cancellation predicate for user stop, elapsed budget and already-reached hit target, so sibling workers do not continue unnecessary connects. The existing post-probe stale-result guard remains.
- The national pre-scan now resolves hostnames in bounded concurrent batches (all candidates in the current 400-item round are attempted unless aborted), then preserves the original independent monotonic 90-second TCP budget. Unresolved candidates remain queued for later rounds.
- Added deterministic `IOOverrides` tests for cancellation during socket connection, cancellation while `startConnect` is still resolving, and timeout cancellation; source guards cover both scanner call paths.
- This is source/CI validation only; physical Android network handover and real-world socket cancellation behavior remain untested on devices.


## 2026-11-24 — Lossless NAT candidate queue overflow

- Added a pure, deduplicating queue-split helper: active queue limits now move overflow into `natRestPending` instead of deleting the tail. Applied to the national source merge (1,200 active entries) and range-generated candidates (3,000 active entries).
- Duplicate detection now includes both active and overflow queues.
- Range scanning and source merging pause when the combined queue reaches its backpressure threshold; the range cursor is not advanced while paused. The existing range/domain/IP/IPv4/IPv6/port search scope is unchanged.
- Range scans also defer before advancing the cursor when no configuration template is available.
- Added unit and source-guard tests proving that bounded active queues preserve all unique overflow entries.


## 2026-11-24 — National-mode source isolation repair

- Added a dedicated Iranian-service domain seed list for automatic discovery while national mode is active.
- National-mode candidate discovery no longer mixes in the global domain catalog, global front-SNI/relay seeds, Cloudflare/CDN CIDR ranges, hard-coded global fallback IPs, or the mixed global-folder IP cache.
- Global mode retains its prior global catalog/CDN/cache sources. National mode still includes exact saved VPN endpoint hosts/configurations for endpoint validation; no active scan scope was broadened.
- This is a candidate-source relevance fix only. It does not prove that any discovered address is reachable from an Iranian carrier during an international outage.
- Exact-head CI and Iranian-network/device tests have not yet been observed for this repair. Do not mark it TESTED until those runs/evidence exist.


## 2026-11-25 — Fusion lifecycle hardening and persistent-memory integrity

- Active branch: `feature/king-fusion-engine-foundation-20261125`; PR #53 remains open and Draft against `feature/king-vpn-audit-hardening-20261125`. Do not merge automatically.
- Fusion now treats a disconnect arriving during an in-flight native start as a cancellation request. It waits for the start call to settle, then rolls back the just-started adapter instead of silently ignoring the disconnect.
- Native stop failures are no longer discarded: failed adapter handles remain tracked, are exposed through `cleanupPendingEngineIds`, and can be retried by a later disconnect. `KingFusionResult.cleanupFailedEngineIds` reports rollback failures after a failed start.
- Fusion tests now cover busy-start rejection, disconnect-during-start cancellation, reverse-order rollback, stop failure retention, and successful retry.
- Clarified that Fusion's `connected` result means every adapter accepted its start call; it is not proof of end-to-end traffic or a verified VPN tunnel.
- NNIE endpoint-history writes are serialized so concurrent record/stability updates cannot finish out of order and overwrite newer snapshots.
- NNIE history loading now marks the store loaded only after a successful read/parse. A storage or parse failure is rethrown and does not silently initialize an empty inventory that could overwrite persisted history.
- Fresh resource writes remain serialized and use temporary-file replacement; merge reads fail closed instead of treating a read error as an empty cache.
- KING AI research-memory writes remain serialized and atomically replaced; the fixed 500-note truncation remains removed.
- The Fusion engine remains an adapter foundation only. The existing `flutter_v2ray_client` lifecycle in `lib/main.dart` has not been replaced, and no new native engine is claimed to be bundled or operational.
- Exact-head CI for the latest source changes must pass source guards, Flutter tests, Dart analysis and ARM64 release build before validation is claimed. The preceding CI failure at run 2938 was a stale source-guard expectation for the NNIE serialization refactor; the guard was corrected in the following commit. Physical-device tunnel, DNS-leak, IPv4/IPv6 data-plane, network-handover and battery tests remain NOT TESTED.
- Main is expected to remain at `c43d325f9803d4f6306415e511f6790deff9d87e`; verify this ref before future work. Do not modify or merge to main.


## 2026-11-25 — Final Fusion handoff race review

- Added the missing `dart:async` import required by Fusion's operation completers after exact CI exposed the compile error; the source guard now checks this import.
- Closed the reconnect handoff window: while a disconnect waiter is waiting for an in-flight connect to unwind, new connect requests receive `E-FUSION-DISCONNECT-PENDING`. The cancellation latch is cleared only after disconnect acquires the operation slot.
- Three-pass static review checked adapter lifecycle, persistence ordering, regression guards and branch/PR state. All 13 reviewed invariants passed at the latest source snapshot.
- CI run 2941 exposed the missing async import; it was corrected. On the subsequent run 2942 (pre-handoff-race snapshot), source guards, Flutter unit tests and Dart analysis passed; the ARM64 release build was still running at the last observation. Run 2944 is queued for the handoff-race follow-up; require a completed exact-head run before calling this branch fully validated.
- The active Flutter V2Ray connection path in `lib/main.dart` remains unchanged. Fusion is not yet wired into the production connection path; no additional native engine is claimed as integrated.
- The default branch must remain at `c43d325f9803d4f6306415e511f6790deff9d87e`. PR #53 remains open Draft; no merge has been performed.


## 2026-11-25 — IP Auto exact endpoint/template integrity

- Removed the two-template truncation from the national IP Auto template inventory. All templates returned by the national source are retained; the per-run address batch remains a resumable execution slice, not an inventory deletion.
- Replaced port-only template selection with an exact resolved `IP:port -> all matching source configurations` index. A shared port no longer causes a candidate IP to be tested with an unrelated server configuration.
- Core verification now tries every original configuration that actually resolves to the exact IP:port pair, preserving each configuration's transport, TLS, SNI, host and credentials. A pair remains in the retry queue if none of its matching configurations passes the two-pass check.
- Added a reusable immutable endpoint-template index helper in `lib/nat_ip_scan.dart`. It validates IPv4/IPv6 literals and ports, normalizes equivalent IPv6 spellings, optionally constrains indexing to the current generated address slice, deduplicates repeated source identities, and preserves all distinct templates.
- Added unit coverage for multiple configurations sharing one IP:port, separate ports, IPv4/IPv6, canonical IPv6 normalization, scope exclusion, invalid values and immutable results. Added source guards against restoring `take(2)` truncation or port-only `firstWhere` fallback.
- This change does not widen active probing to unrelated public/CDN ranges. Active checks remain limited to exact addresses resolved from configured VPN endpoint records; passive inventory and active endpoint verification remain separate.
- Latest exact-head CI is pending after the scanner/test/source-guard changes. Previous exact-head run 2942 completed successfully for the prior Fusion-only snapshot (unit tests, Dart analysis and ARM64 build); do not transfer that success to the new scanner commits.
- PR #53 remains open Draft and unmerged. Main remains at `c43d325f9803d4f6306415e511f6790deff9d87e`.


## 2026-11-25 — DNS hostname inventory normalization

- Extracted shared hostname normalization into `lib/king_domain_inventory.dart` so scanner input parsing is independently unit-testable.
- DNS inventory normalization now accepts project `domain:` and `full:` rules, case-folds names, removes a terminal DNS root dot, deduplicates, and validates total name length and each label.
- IPv4 and IPv6 literals are no longer misclassified as hostnames. This matters because user-configured relay IPs share source collections with hostname catalogs; they remain valid endpoint data but do not enter DNS/SNI hostname queues.
- Added standalone tests for project rule prefixes, mixed case, root dots, duplicate names, IPv4/IPv6 exclusion, malformed labels, overlong labels/names, single-character labels and punycode names.
- Added a source guard that ensures the shared normalizer remains wired into DNS scanner inventory construction.
- This is normalization only: no domain source is removed by a fixed list, no inventory count ceiling is introduced, and DNS/endpoint resources remain separate.
- Exact-head CI is pending for the domain-normalization additions as well as the preceding exact endpoint/template changes. Physical device and network-path tests remain outstanding.


## 2026-11-25 — Three-pass scanner review

- Pass 1 (semantics): verified complete national template retention, removal of two-item template truncation, exact IP:port association, and trying all source configurations for a pair. No port-only fallback remains.
- Pass 2 (scope/safety): verified that active IP checks remain constrained to the generated address slice resolved from the existing endpoint inventory; endpoint ports and IPv4/IPv6 values are validated; DNS host normalization excludes IP literals and malformed labels.
- Pass 3 (regression): verified main.dart imports the standalone normalizer, dns_scanner.dart uses it, unit tests cover endpoint indexing and hostname normalization, and source guards match the final implementation.
- Static review result: 15/15 assertions passed across the three passes. This is a source-level review, not a substitute for exact-head CI or Android device tests.
- Corrected a source-guard wording mismatch before final CI; no product behavior was changed by that guard-only correction.
- Latest exact-head CI is queued; run 2945 is still processing a prior commit's ARM64 build. Wait for the latest head's source guard, Flutter tests, Dart analysis and ARM64 build before marking this stage validated.


## 2026-11-25 — Unified auto-scan checkpoint

- Replaced three separately-written SharedPreferences cursor keys (CDN, hostname and TCP-port progress) with one versioned `auto_scan_checkpoint_v2` JSON value.
- Added a pure decoder that validates checkpoint version and cursor value types, detaches decoded maps, and migrates legacy cursor keys when no valid v2 checkpoint exists.
- A valid v2 checkpoint preserves intentional empty/null cursor values instead of resurrecting stale legacy progress. Malformed v2 data falls back to independently readable legacy values; malformed legacy CDN JSON does not discard valid domain/port cursors.
- The scanner now stages all three inventory cursors, saves scan observations first, then commits the combined checkpoint in one preference write. If that write reports failure, it leaves the previous checkpoint authoritative and reports that the next run will safely rediscover already-saved observations.
- Added Dart tests for round-trip, legacy migration, intentionally empty state, corrupt-state fallback and invalid ports; added source guards against reintroducing separate cursor writes.
- This reduces partial-progress inconsistencies; it is not a claim of filesystem-level fsync or transactional guarantees beyond the single preference operation exposed by the platform API.


## 2026-11-25 — Shared fair batching for domain and TCP-port inventories

- Added `kingNextInventoryBatch<T>` as a common cursor-based round-robin slicer for complete inventories.
- Replaced duplicated domain and port wraparound calculations with the shared helper.
- The helper returns an immutable slice, leaves the source inventory unchanged, handles stale cursors by safely restarting at the beginning, and returns an empty result for empty inventories or non-positive batch sizes without modulo-by-zero risk.
- The per-run batch size controls only work performed in one pass. The complete hostname and 1–65535 TCP port inventories remain available across subsequent cursor-backed runs.
- Added Dart tests for wraparound, stale cursors, larger-than-inventory batches, empty inventories, non-positive batch sizes and immutable results.


## 2026-11-25 — CI-driven generic batching and canonical IPv6 correction

- The first Dart CI pass caught that generic type variables cannot be used in const collection expressions. Both empty-result paths in `kingNextInventoryBatch<T>` now return runtime-typed empty lists.
- The endpoint-template test exposed that equivalent IPv6 spellings were not guaranteed to compare equal through the platform's textual `InternetAddress.address` representation alone.
- Added byte-based IPv6 canonicalization: parse the 16 address bytes, split into eight 16-bit groups, compress the longest zero run (leftmost on ties), and use lowercase hexadecimal. IPv4 formatting remains unchanged.
- Both the active endpoint and address-scope paths now use the same canonical representation before exact pair matching.
- Added regression tests for expanded/compressed IPv6 equivalence, all-zero and trailing-zero runs, and unchanged IPv4 formatting.
- The latest source-guard run before this correction exposed one stale source assertion; it was updated to check the canonicalizer. The newest exact-head CI run is pending.


## 2026-11-25 — IP Auto atomic recovery checkpoint

- Added versioned per-mode `ipauto_snapshot_v2_nat` / `ipauto_snapshot_v2_glob` snapshots. Each serialized value contains IP:port observations, the pending core-verification backlog, all range cursors, and the current position.
- `ipAutoLoad` treats a valid v2 snapshot as authoritative and migrates from existing independent preference keys only when v2 is absent or malformed. Legacy keys remain intact for compatibility.
- `ipAutoSave` commits the full state through one `SharedPreferences.setString` operation instead of four independently awaited writes. This is a single-key application checkpoint, not a filesystem-fsync guarantee.
- The IP Auto run persists the completed TCP cursor with the complete pending core-verification queue before lengthy native-core checks. Successful queue removals/promotions are checkpointed, allowing process-death recovery during verification.
- Added tests for round-trip, legacy migration, valid-empty authority, corrupt fallback and invalid positions, plus a source guard enforcing the single-write save path.
- Three-pass review: (1) state model and nat/global separation; (2) crash windows and queue durability; (3) legacy migration and single-write regression guard.
- Exact-head CI run 2984 is in progress for commit `46be052d79bf8c5ec06da441ee966b2b96cd541f`. Do not claim this stage validated until source guards, Flutter tests, Dart analysis and ARM64 release build all complete successfully.
- Device-level tunnel, DNS-leak, IPv4/IPv6 data-plane, network-handover and battery tests remain NOT TESTED.


## 2026-11-25 — Fusion data-plane acceptance gate (latest)
- Extended `lib/king_fusion_engine.dart` with an explicit `KingFusionTrafficVerifier` contract and per-plan `requireTrafficVerification` opt-in.
- When a plan requires end-to-end evidence, a missing verifier is rejected during preflight, before any adapter starts. Native adapter start success alone cannot satisfy the requested verified-connectivity contract.
- After all hops start, the verifier must return positive evidence within the configurable positive timeout (default 12 seconds). A negative result rolls back all started hops in reverse order and returns `E-FUSION-TRAFFIC-UNVERIFIED`; verifier exceptions/timeouts use the normal failure cleanup path.
- Added cancellation fencing after the asynchronous verification await. A disconnect requested while traffic verification is pending now wins over a late positive probe and triggers rollback with `E-FUSION-CANCELLED`.
- Added regression tests for missing-verifier preflight, negative data-plane evidence and rollback, positive verification, disconnect during verification, and verification-timeout cleanup.
- Commits on this feature branch: `12e5ed7efc74109501f83d903fb72350be3d153d`, `e9dcf25e996fc3fcc665f82e333e9fb3d8701ea0`, `7d8a0062251ec7aa879720a1afc030f2862ce4e4`, `fc5045a12ac25adf9d40b031290fd870e3417673`, `67a887b33a9597495d8c1f562578c3610a7710c9`.
- Three review passes: (1) architecture — verifier is injected and opt-in, preserving existing app connection paths; (2) lifecycle/security — no config or native handle logging, bounded verification wait, reverse rollback and cancellation fencing; (3) regression — added focused unit tests for each new branch.
- Validation status: latest exact-head workflow lookup returned no PR-triggered workflow run for `fc5045a12ac25adf9d40b031290fd870e3417673`. Do not claim tests, analyzer, or APK build passed until exact-head CI is observed. No device-level data-plane verification is claimed.
- Next: inspect workflow trigger behavior / PR head, run exact-head CI, fix any failures, then wire a real verifier only to an existing app-owned tunnel probe after confirming it traverses the intended route. Do not replace the current `flutter_v2ray_client` connection lifecycle or claim Xray/Sing-box/WireGuard adapters are integrated without native implementations and device tests.


## 2026-11-25 — Fusion verified-connectivity result semantics (continued)
- Added `KingFusionResult.trafficVerified`. It is true only when the plan explicitly required traffic verification and the injected verifier returned positive evidence. Ordinary adapter-start success leaves it false, so callers cannot confuse native startup with data-plane proof.
- Added a dedicated `E-FUSION-VERIFY-TIMEOUT` result for the verifier's bounded wait. Timeout classification is isolated to the verifier await; a `TimeoutException` raised by a native adapter start is not mislabeled as a traffic-probe timeout.
- Added regression assertions for verified and unverified success, verifier timeout cleanup, and native-start timeout classification.
- New commits: `795d59b442c1eb2716171e3bdb332521853a52a4`, `f071cd258773f76e74722a5d4f14c00e17332b0a`, `93399d04b3aa21ad0fb9d9f217f1353c278cf26d`, `36225f0aaeb365ca07a4809f82f92ac5dd1cdcc2`, `0c4d9fff5fffbd279c5313801442decda31bf025`.
- Review passes: (1) API semantics — `connected` remains adapter-start state while `trafficVerified` is separate; (2) timeout correctness — only verifier timeout receives the dedicated code; (3) regression coverage — explicit tests distinguish native start timeout from verifier timeout.
- Validation: the repository workflow `.github/workflows/build.yml` is configured for all pull requests, but the GitHub workflow-run lookup returned no run for the earlier exact PR head. Latest commits have not been run through Flutter tests, Dart analysis, or Android build in this session. Do not claim CI success.
- Latest work remains on `feature/king-fusion-engine-foundation-20261125`, PR #53 Draft and unmerged. Main connection path remains unchanged. Device-level traffic proof remains untested.
- Next: obtain an exact-head CI run, then inspect and implement a real application-owned traffic verifier only after proving the probe uses the active VPN route; separately audit native adapter startup and stop semantics before integrating any additional VPN engine.


## 2026-11-25 — Exact-branch CI trigger repair
- Updated `.github/workflows/build.yml` so pushes to `feature/king-fusion-engine-foundation-20261125` also run the full Android validation workflow. Previously the push branch filter omitted this active feature branch; PR-triggered runs were not visible through the exact-commit workflow lookup, leaving the latest code without observed validation.
- This change does not weaken or skip any checks: source guards, Flutter tests, Dart analysis, and optimized Android arm64 release build remain in the existing workflow.
- CI trigger change commit: `afc8fff165af5f812c4f6ea44308a87b2ffe485e`.
- Awaiting the workflow result for this exact commit; do not report success until the run and all required jobs complete.


## 2026-11-25 — Fusion adapter failure-code boundary hardening

- Added a strict public failure-code normalizer for native adapter start failures. Only stable uppercase machine codes matching `^[A-Z][A-Z0-9_-]{0,63}$` are allowed through; null retains the existing generic `E-FUSION-START` behavior and malformed/free-form adapter text becomes `E-FUSION-ADAPTER-START`.
- This prevents arbitrary adapter error strings from crossing the Fusion result boundary. Such strings can accidentally contain fragments of VPN configuration, tokens, endpoint credentials, or other sensitive details.
- Added a regression test that supplies an adapter failure string containing a private configuration marker and verifies the returned result contains only the safe generic code.
- Three-pass review: (1) API compatibility — existing safe adapter codes such as `E-TEST-START` remain unchanged and null remains generic; (2) security — free-form detail is not propagated and no configuration is added to logs/results; (3) regression — a focused test covers malformed detail while the existing rollback and lifecycle tests remain in place.
- During post-write source inspection, a duplicated trailing source fragment was detected in the engine file and removed in a separate repair commit. The current fetched file has one `KingFusionEngine` declaration, one normalizer definition, one call site, and a clean class/file ending.
- Commits: `3346ad0540f6d6f4011df6ddf09a361b82766f89` (normalizer), `8fb679970f635904722f2ce20da650d701a25a3b` (regression test), `6694f78dce6c91c207a163b082a18b067252c2a6` (duplicate-tail repair).
- Exact prior-head CI run 3003 passed on `f54294e23ad4aad7e14dabac6065b0956c3d8ce6`, including source guard, Flutter unit tests, Dart analysis, ARM64 release APK build, source packaging and provenance steps. This does not validate the new failure-code changes.
- Exact-head CI run 3008 is pending for `6694f78dce6c91c207a163b082a18b067252c2a6`; do not mark this change CI-validated until the run completes successfully.
- PR #53 remains open Draft and unmerged. Existing `lib/main.dart` V2Ray connection path remains untouched. Device-level tunnel/data-plane validation remains outstanding.


## 2026-11-25 — CI syntax failure diagnosis and corrective follow-up

- Exact run 3006 for test commit `8fb679970f635904722f2ce20da650d701a25a3b` failed during Flutter unit-test compilation (281 tests passed, 1 test file failed to load). The failure was in the newly added normalizer's raw-regex literal, which had been truncated in the committed source; analyzer and APK build were skipped.
- Run 3008 was triggered for the intermediate duplicate-tail repair commit. It is not accepted as validation evidence for the corrected source.
- Replaced the regex with a straightforward ASCII code-unit validator to avoid quoting/escaping ambiguity. It accepts only uppercase A–Z, digits, underscore and hyphen, with a maximum length of 64 and an uppercase initial character. It also restores the dedicated verifier-timeout exception declaration that was within the malformed duplicated tail.
- Current engine file was re-fetched after the correction: one `KingFusionEngine` declaration, one normalizer definition, one normalizer call site, and the verifier-timeout exception declaration are present. The regression test remains present.
- Corrective commit: `bf8bba4bc4f115309cce09876bb28aa044d188e5`.
- Exact-head CI run 3012 is pending for that corrective commit. Do not call the change validated until source guard, all Flutter tests, Dart analysis and ARM64 release build pass on the final head.


## 2026-11-25 — Fusion cancellation and bounded native cleanup

- Added optional `KingFusionCancellableTrafficVerifier`. The coordinator now races verification against a disconnect signal, so disconnect no longer waits for a verifier future that never completes. Cancellation is requested on both user disconnect and verifier timeout; late verifier completion is not allowed to turn a cancelled operation into success.
- The base `KingFusionTrafficVerifier` contract remains source-compatible. Existing verifiers need not implement cancellation, but implementations that own sockets/probes should implement the optional cancellation interface and make `cancel()` idempotent.
- Added configurable `nativeStopTimeout` (default 8 seconds, must be positive). Each native stop attempt is bounded; a timed-out/failed stop remains in the cleanup-pending list so a later disconnect can retry. Adapter `stop()` implementations must tolerate retries.
- Added regression coverage for a verifier that never completes, cancellation requests on disconnect and timeout, and a native stop that never completes while retaining its cleanup handle.
- Three-pass review: (1) lifecycle/API — cancellation is optional and the base verifier API is unchanged; (2) safety — disconnect signal wins over late verifier results, cleanup is bounded and failed handles are retained; (3) regression — new tests cover hung verifier and hung stop paths alongside prior start/rollback/verification cases.
- Current source/test files re-fetched from the branch: `lib/king_fusion_engine.dart` contains one coordinator declaration and one failure-code normalizer/call site; `test/king_fusion_engine_test.dart` contains 19 Fusion tests including the new cancellation/timeout cases.
- Commits: `49574a82010826f6d634e8cbafc0e501f2ac542c` (coordinator cancellation/stop timeout), `456650ffb06afc930faae5c0ba5605e37a6c0784` (new tests), `d6c138234d33bb5e6446c2a76b870f5a620a5c2b` (cancel verifier work on timeout), `ccd66b8bcae75e9c2a9a91174735f9590bb1371b` (assert cancellation behavior).
- CI run 3012 passed on the prior syntax-repair commit `bf8bba4bc4f115309cce09876bb28aa044d188e5`. CI run 3021 is pending for the current test commit `ccd66b8bcae75e9c2a9a91174735f9590bb1371b`; current cancellation changes are not yet CI-validated.
- Existing application V2Ray route remains unchanged. No device-level VPN tunnel verification or native engine integration is claimed.


## 2026-11-25 — Cancellable native startup

- Added optional `KingFusionCancellableEngineAdapter` for native engines whose start operation can block. A disconnect now requests cancellation from the in-flight adapter; the interface contract requires the cancellation hook to be idempotent and make the pending `start()` future settle.
- A successful late start returned while disconnect is pending is tracked and immediately rolled back; a failed/cancelled start is reported as `E-FUSION-CANCELLED` rather than leaking adapter-specific cancellation details.
- Added a deterministic fake adapter and regression test proving disconnect requests startup cancellation and stops a late-created native handle.
- Three-pass review: (1) compatibility — existing adapters need not implement the optional interface; (2) lifecycle — late successful handles enter the normal reverse-order rollback path; (3) regression — dedicated startup cancellation test added, and all previous verifier cancellation/timeout and cleanup retry cases remain present.
- Commits: `f6d2b1f71fca8d5d6192bc6407e9840a9a1f74b5` (optional native start cancellation), `168a76e19f136c0ca0a23b6c0417e31ad7d056b6` (startup cancellation test).
- Current fetched source/test checks: one `KingFusionEngine` declaration; cancellation-aware verifier and startup interfaces present; bounded stop timeout present; 20 Fusion tests in the test file.
- CI run 3021 for an earlier intermediate test commit was cancelled when a newer branch push superseded it. CI run 3026 is pending for current test commit `168a76e19f136c0ca0a23b6c0417e31ad7d056b6`. Do not claim current-stage CI success until this exact-head run completes successfully.


## 2026-11-25 — Fusion CI correction and native-stop concurrency hardening

- Exact-head CI for commit `3c050481c981dfeba7965f09031599c52af6fda9` completed with failure in the Flutter test-loading stage. The compiler identified one misplaced `verifier.cancelCalls` assertion in the native-start cancellation test; the variable was not in scope there. Removed the invalid assertion while retaining the verifier cancellation assertions in the dedicated verifier tests.
- A lifecycle audit found a second-order cleanup race: Dart's `Future.timeout` does not cancel the underlying native `stop()` operation. A subsequent disconnect could therefore issue a second stop while the first native stop was still running.
- Added per-adapter in-flight stop tracking. Timed-out stop futures remain registered until they actually settle; repeated disconnects wait on the same operation instead of overlapping native stop calls. Once the prior operation settles, a later disconnect may safely retry cleanup.
- Added a deterministic regression test that times out twice against one still-running stop, verifies only one native stop was issued, releases the original operation, and verifies a later disconnect performs the retry and reaches idle.
- Three-pass review: (1) compatibility — no changes to the base adapter interface and no new requirements for existing adapters; (2) lifecycle/safety — stop calls are serialized per adapter and handles remain retained until successful cleanup; (3) regression — misplaced compile-time assertion removed and timeout/overlap/retry behavior covered by a focused test.
- Commits: `cf6ccda3cbff4ee5a614b482f57463b21f3aaf96` (serialized stop operations), `58d2f6ced0b733ace590e07fc85f3b5bb41c8a35` (test correction and stop-concurrency regression).
- The exact latest branch head is `58d2f6ced0b733ace590e07fc85f3b5bb41c8a35`. The new exact-head CI run must complete before claiming tests, analyzer or Android release build are validated. Physical device/data-plane tests remain outstanding.


## 2026-11-25 — Fusion preflight containment and dependency-safe rollback

- Hardened preflight against adapter-owned compatibility code throwing unexpectedly. A thrown `canChainTo()` now becomes the stable `E-FUSION-VALIDATION-EXCEPTION` result before any native adapter starts; adapter compatibility checks are documented as side-effect-free.
- Added a regression test proving a compatibility-check exception does not start either hop and does not escape as an uncaught exception.
- Continued the cleanup-order audit and corrected a dependency hazard: if stopping a downstream hop fails or times out, rollback now stops at that point and retains that hop plus every upstream hop. It no longer tears down an upstream dependency while the downstream engine may still be running.
- A later disconnect retries in reverse dependency order: downstream first, then upstream only after downstream cleanup succeeds.
- The in-flight stop map now uses identity semantics, avoiding accidental collisions if adapter classes implement value-based equality.
- Added a two-hop regression test that forces the downstream stop to fail, verifies the upstream stop is not attempted, then verifies a later retry stops downstream and upstream in the correct order.
- Three-pass review: (1) compatibility — base adapter methods unchanged; preflight errors are now represented as result codes; (2) lifecycle — strict reverse dependency cleanup and identity-keyed serialization preserve native handle ownership; (3) regression — preflight exception and two-hop cleanup retry tests added.
- Commits: `d5859428a6d0e95e4e63979fcf4ba835c7b7005f` (preflight exception containment), `52aff9ca4d0d02c40e698e2d277f1cd24d4e0e04` (preflight regression), `8cd647d5bb0ee88e8995f13786d71f9ec3351cbe` (dependency-safe cleanup), `c39ae3f521757db274d8192eee4ac5afb64fb174` (reverse-order regression).
- Exact latest-head CI is required before validation claims. Earlier workflow attempts are still processing/cancelled for intermediate heads; no current-head test/analyze/Android build result is claimed.


## 2026-11-25 — Native-start exception cancellation race

- Corrected the generic native-start exception path so an exception raised after the user has requested disconnect is classified as `E-FUSION-CANCELLED`, not `E-FUSION-EXCEPTION`.
- Previously, adapters returning a failed result after disconnect were already classified as cancellation, but adapters throwing during the same cancellation race could leak a generic exception result. Both outcomes now honor the same cancellation state while rolling back earlier successful hops.
- Added a two-hop regression test: the first hop starts, the second start is held, disconnect is requested, and the second adapter then throws. The result is cancellation, the first hop is stopped, and the engine returns to idle.
- Three-pass review: (1) API consistency — thrown and returned start failures follow the same cancellation semantics; (2) lifecycle — already-started handles still enter reverse-order rollback; (3) regression — explicit test covers the exception/disconnect interleaving.
- Commits: `77066d5c032ddbb7704b6896edff66ed4090e255` (cancellation result mapping), `287a7019bdee76a7c376219f7db13f05664ed9c3` (race regression test).


## 2026-11-25 — Reconnect guard while native cleanup is pending

- Split the previous active-connection guard into two precise states: a healthy connected route returns `E-FUSION-ALREADY-ACTIVE`, while retained native handles from failed/timed-out cleanup return `E-FUSION-CLEANUP-PENDING`.
- This prevents a new route from starting while an earlier native engine may still be alive. Reconnect becomes available only after a later disconnect successfully clears the retained handles.
- Extended the failed-stop retry test to attempt a new connection before cleanup retry; it verifies the explicit cleanup-pending result and confirms no second native start occurs.
- Three-pass review: (1) state semantics — connected and cleanup-pending are distinct; (2) lifecycle safety — no new engine can overlap a still-owned native handle; (3) regression — reconnect is blocked until reverse-order cleanup succeeds.
- Commits: `2aa5b14650cea4a485484882948de61eaee28f10` (cleanup-pending guard), `3cfc20a107c48fa483f6ac7823a4efe6f9077298` (reconnect regression test).


## 2026-11-25 — Read-only lifecycle state and safe Fusion telemetry

- Added an additive, immutable `KingFusionSnapshot` exposing coordinator state, busy/disconnect flags, active engine IDs, pending cleanup IDs and the lifecycle event sequence. Native handles and configuration payloads are deliberately excluded.
- Made the coordinator's state internally owned and externally read-only (`state` getter). Callers can no longer mutate the state machine independently of native resource ownership.
- Added opt-in lifecycle telemetry with monotonically increasing sequence numbers, timestamps, safe event types, engine IDs, sanitized failure codes and active-hop counts. Events cover state transitions, preflight rejection, hop start/failure, traffic verification, rollback, cleanup and disconnect.
- Observer exceptions are isolated; a faulty telemetry consumer cannot break connection startup or cleanup. No raw adapter exception strings, user configuration, credentials or native handles are included in event fields.
- Added regression coverage for immutable snapshots, monotonic event sequencing, secret-free event content and listener exception isolation. Fusion test count is now 26.
- Three-pass review: (1) API compatibility — event listener is optional and all additions are additive; existing adapter interfaces and call sites remain unchanged; (2) security/lifecycle — state is read-only externally and telemetry excludes secrets/handles; (3) regression — tests cover event ordering, snapshot contents and observer failures.
- Commits: `dcaf38d76b24232d7c7959b9f5a29555d1558918` (snapshot/event API), `affca07a66d94ba066ef51fa4aac090715b9c773` (telemetry tests), `e64f46f565075e986ec8b19f7eaef566c838b012` (state-storage and validation telemetry correction).
- The newest exact-head CI run is pending. The earlier `c41cb6c` run has passed Flutter tests and Dart analysis but its Android arm64 APK step is still in progress; it does not validate this newer telemetry revision.


## 2026-11-25 — Precise verification telemetry

- Corrected the state storage introduced with snapshots: the coordinator now has a real private `_state` field and exposes only its getter. The earlier mechanical rename was caught in immediate source review before claiming CI validation.
- Added a dedicated `operationCancelled` lifecycle event and moved disconnect-request telemetry so idle and active disconnect calls are both observable.
- Traffic-verifier exceptions now have their own `E-FUSION-VERIFY-EXCEPTION` result and `verificationFailed` event, rather than being misreported as a native engine-hop failure. Verification timeouts also emit a typed failure event; cleanup-pending disconnect completion reports its pending status.
- Added a regression test that makes the verifier throw, confirms the specific failure code/event, ensures no native-hop failure event is emitted, and verifies rollback of the started adapter.
- Test count: 27 in `test/king_fusion_engine_test.dart`.
- Three-pass review: (1) correctness — internal state declaration and all state writes checked; (2) observability/security — typed failure events carry sanitized codes only; (3) regression — verifier-exception behavior and rollback covered.
- Commits: `e64f46f565075e986ec8b19f7eaef566c838b012` (private state storage correction), `f06a3d5031d2000000a21504b07cb0ee66c6a1e2` (verification failure classification), `5aa622774ace91396542ad55f0f08216d64f7ef3` (verifier regression test).
- The exact latest-head CI run must complete before claiming the snapshot/telemetry work passes tests, analysis or Android build.


## 2026-11-25 — Registry, timeout and snapshot invariants

- Expanded the lifecycle test suite to 30 tests.
- Added constructor-time duplicate adapter-ID rejection (including whitespace-normalized duplicates), positive-timeout validation for both native stop and traffic verification, and validation-rejection telemetry assertions.
- Added an explicit immutability assertion proving snapshot engine-ID lists cannot be modified by callers.
- The tests verify rejected plans never start native adapters and that rejected-plan telemetry contains only a stable sanitized code and engine ID, never the supplied configuration text.
- Three-pass review: (1) compatibility — constructor validation only rejects ambiguous/invalid registry or timeout configuration; (2) security — snapshot collections are unmodifiable and telemetry remains configuration-free; (3) regression — duplicate IDs, invalid durations, rejected plans and snapshot mutation are covered.
- Commits: `2b64091a9c80709f4833b722b9312733763bba23` (invariant tests), `9ccb12c95703f31cc2be119a32b2002ff72ac495` (portable matcher correction).


## 2026-11-25 — Engine identifier boundary hardening

- Added a strict, bounded identifier grammar for adapter registry IDs (ASCII letters, digits, dot, underscore and hyphen; maximum 64 characters). Invalid IDs are rejected during registry construction before they can enter public engine listings or lifecycle telemetry.
- Lifecycle event engine IDs are normalized through the same safe identifier check; malformed identifiers are omitted rather than copied into diagnostics.
- Added a regression test proving identifiers containing unsupported characters are rejected before any adapter is started.
- Three-pass review: (1) compatibility — all current built-in test identifiers use the supported stable-ID grammar; (2) security — identifiers cannot smuggle arbitrary text into telemetry; (3) regression — constructor rejects unsafe IDs and retains duplicate-ID handling.
- Commits: `61250956fd099d21e121ebe9cf038208dc8d7d3c` (identifier validation), `32f0f2ffb2c4876bbbc9f1c0099be12d44561cd4` (unsafe-ID regression test).
- Test count: 31. Latest-head CI is still required.


## 2026-11-25 — Declarative transport-capability preflight

- Extended `KingFusionHop` with an optional `requiredTransport` declaration. This is explicitly separate from the opaque native configuration string; the coordinator never parses or rewrites user configuration to guess transport.
- Preflight normalizes the requested transport and checks it against the adapter descriptor's advertised `supportedTransports`. Unsupported requirements fail before any native adapter starts with `E-FUSION-TRANSPORT-UNSUPPORTED`; malformed values fail with `E-FUSION-TRANSPORT-INVALID`.
- Existing callers remain compatible because the transport requirement is optional. Existing descriptors with empty transport capability sets retain their previous behavior unless a caller explicitly requests a transport.
- Added regression tests for case/whitespace-normalized supported transport, unsupported transport, and malformed transport values; no opaque configuration contents enter diagnostics.
- Three-pass review: (1) compatibility — additive optional plan field; (2) correctness/security — transport is declarative, validated and never inferred from config; (3) regression — accepted/rejected/malformed cases covered before native execution.
- Commits: `9e7b5e0f12c13a8a747bc7d4ee9e863d69314773` (transport preflight), `edc91d4fe35437cfbf5c19c5bee1a96ffd67aedf` (transport tests).
- Test count: 33. Exact latest-head CI remains required.


## 2026-11-25 — Frozen adapter registry metadata

- The coordinator now snapshots adapter descriptors at construction, including a defensive immutable copy of the advertised transport capability set. Later mutation of an adapter-owned Set cannot silently change what the registry advertises or what preflight accepts.
- Added an identity-keyed adapter-to-ID map so active handles, cleanup diagnostics, snapshots and lifecycle events use the stable registry identifier rather than repeatedly querying a potentially dynamic adapter descriptor.
- `availableEngines` now returns the frozen descriptor snapshots, not mutable adapter-owned metadata.
- Added a regression test that mutates the original transport Set after coordinator construction, confirms the advertised snapshot remains unchanged and immutable, and verifies that preflight still uses the original captured capability.
- Three-pass review: (1) compatibility — public descriptor fields are preserved; (2) lifecycle/security — registry identity and capabilities cannot drift after registration; (3) regression — post-registration mutation and snapshot immutability are covered.
- Commits: `abb124448ec405050b80e8f0e31e0f44f7497b7d` (descriptor snapshots), `fb9d48a14b9f3fa907e73b350226c19dbb822489` (frozen identity in chain validation), `37fce6c2eab1aafb93bf4d704ba89926c03a9ac4` (snapshot ID correction), `d6c9042b05adf2b7b889228319c0b91f76de19fc` (capability immutability test).
- Test count: 34. Latest-head CI required.


## 2026-11-25 — CI-discovered active-vs-cleanup snapshot correction

- The CI run for `3bb1ee5778513c0bcd046fa88ed1617d2abd22ed` exposed a semantic bug in the new snapshot: `cleanupPendingEngineIds` was reporting every live active hop as pending cleanup, even while the route was healthy.
- Corrected the getter to expose retained IDs only after the coordinator has entered the failed state with cleanup still outstanding. Healthy active routes and ordinary in-progress disconnects no longer appear as cleanup failures.
- The failed CI run had 313 passing tests and one failing snapshot assertion; the failure was isolated to this reporting semantic, not compilation. The assertion now matches the corrected lifecycle distinction.
- Three-pass review: (1) state semantics — active and cleanup-pending are distinct; (2) lifecycle — retained handles remain visible after failed rollback; (3) regression — the existing snapshot test covers healthy-active state while cleanup-retry tests cover failed state.
- Fix commit: `f1bb315f5885d3421e25b63073d5d73f422d1dac`. Latest-head CI must verify this correction and the later registry/transport changes.


## 2026-11-25 — Concurrent disconnect coalescing

- Added a shared in-flight disconnect future. All callers that request disconnect during the same native cleanup operation now join the exact same future; a second caller can no longer return while the first caller is still waiting for a blocked native `stop()`.
- The cancellation signal is raised only when disconnect is joining an active connect/verification operation. Additional callers joining an already-running teardown do not set a stale cancellation latch.
- Retained the previous cancellation behavior: disconnect during native startup or traffic verification still signals the active operation, requests optional adapter/verifier cancellation, waits for connect rollback, and then performs any remaining cleanup.
- Cleanup-failure IDs now use the frozen adapter registry identity instead of re-reading a mutable adapter descriptor after registration.
- Added a deterministic concurrency regression test: hold native stop, invoke disconnect twice, verify the second future remains pending, release stop, await both callers, and assert exactly one native stop call and final idle state.
- Three-pass review: (1) API/concurrency — all concurrent callers share one future; (2) lifecycle — joining teardown does not create overlapping native cleanup or stale cancellation state; (3) regression — blocked-stop test asserts both callers observe completion.
- Commits: `65f8c66b137b3d3d5e7c9c129988229581a92c95` (concurrent disconnect test), `9621086cbf5795811c4e92797bddee00d08b2b04` (coalesced disconnect and stable cleanup identity).
- CI for `9621086cbf5795811c4e92797bddee00d08b2b04` is pending. The immediately preceding exact-head commit `4a1274f599eeb4a92d40e40c373313b96e5fd7a3` passed both push and pull-request workflows, including Flutter tests, Dart analysis and Android arm64 release APK build; this does not pre-validate the new concurrency change.


## 2026-11-25 — Bounded secret-free Fusion lifecycle history

- Added configurable in-memory lifecycle event retention to `KingFusionEngine`. The default history window is 256 events and callers may choose any positive capacity; non-positive capacities are rejected at construction.
- Event history is populated even when no observer callback is registered, so diagnostic snapshots remain useful in production integrations that do not attach a listener.
- Added immutable `recentEvents` access on both the engine and `KingFusionSnapshot`. The retained window is trimmed from the oldest end and never grows beyond the configured capacity.
- The history stores only the existing sanitized `KingFusionEvent` fields: sequence, timestamp, lifecycle type/state, validated engine ID, sanitized failure code and active-hop count. Opaque configurations and native handles are not introduced into telemetry.
- Added tests for retention without a listener, bounded eviction, immutable history/snapshot collections, sequence continuity, configuration secrecy, and invalid capacity.
- Three-pass review: (1) compatibility — additive constructor option with a default; existing listeners and event sequencing remain intact; (2) security/lifecycle — no config/native handle fields are retained and memory use is bounded/configurable; (3) regression — 2 new tests cover history behavior and validation.
- Commits: `1704b51268988059226d89c2ce6fe9000cf00d6e` (engine history), `11460856dbcaaff71f8183c076000531a9e37f9e` (history tests).
- Dedicated Fusion test count: 40. CI for the exact latest head is pending; do not treat older CI results as validation of this change.


## 2026-11-25 — Reentrant disconnect observer safety

- A lifecycle observer could synchronously call `disconnect()` while handling `disconnectRequested`. The old order emitted the event before publishing `_disconnectOperation`, allowing recursive event dispatch before the first call had installed its coalescing future.
- Corrected the ordering: the first caller publishes the shared disconnect future before notifying observers. Reentrant and concurrent callers now join that same operation. Joiners do not re-emit `disconnectRequested`, preventing observer recursion while preserving one event for the teardown transition.
- Added a deterministic regression test whose observer calls `disconnect()` directly from `disconnectRequested`; it asserts one event, one native stop, no recursion, and final idle/not-busy state.
- Three-pass review: (1) concurrency/API — the shared future is visible before callbacks run; (2) lifecycle — reentrant callers cannot start duplicate teardown or recursively dispatch the same event; (3) regression — the callback-driven test asserts exactly-once event and stop behavior.
- Commits: `467802307f8364959445e615bfbc8a9a5b61b1ca` (reentrancy fix), `73dfadc35cad05b37367e940ebfdd413732ff66c` (regression test).
- Dedicated Fusion test count: 41. Exact latest-head CI is required.


## 2026-11-25 — Block reentrant connection during disconnect notification

- Found a lifecycle race in the synchronous `disconnectRequested` observer window: `disconnect()` had published its shared future, but `_performDisconnect()` had not yet started and `_busy` was still false. An observer could call `connect()` in that window and begin a new native start immediately before teardown.
- `connect()` now rejects when either `_disconnectOperation` is already published or `_disconnectRequested` is active, returning `E-FUSION-DISCONNECT-PENDING` before validation or adapter invocation.
- Added a regression test that attempts a new connection directly from the `disconnectRequested` observer. It verifies the attempted connection is rejected, only the original start and one stop occur, and the coordinator returns to idle.
- Three-pass review: (1) API/concurrency — the guard checks the published disconnect future, not only `_busy`; (2) lifecycle/security — no new configuration is passed to a native adapter once teardown is committed; (3) regression — observer reentrancy test asserts failure code, exactly one start/stop, and final idle state.
- Commits: `2e0e2ff55167e23d18d3a3e7e0b786265196ead4` (guard), `6d040bad06fa6a1e4866d2e5815abd1f7b18efff` (test).
- Dedicated Fusion test count: 42. Exact latest-head CI is required.

- Follow-up test-quality refinement: the reentrant-connect regression now captures and awaits the returned `Future<KingFusionResult>` directly, rather than observing completion through a detached callback. This makes the assertion deterministic and ensures the rejection result is observed by the test. Commit: `34146d04c8f935bc0f0f376a8da167bddba73cc1`.


## 2026-11-25 — Snapshot visibility for pending disconnect operations

- Found that the snapshot's `disconnectRequested` flag remained false during the synchronous `disconnectRequested` event callback: the shared disconnect future was already published, but `_disconnectRequested` is reserved for cancelling an in-flight connect and had not yet been set.
- Snapshot projection now reports `disconnectRequested` when either the in-flight cancellation flag is set or the shared disconnect operation exists. This keeps the observable snapshot consistent with the lifecycle event and the connection guard without changing the cancellation signal's internal semantics.
- Extended the reentrant disconnect observer regression to capture the snapshot during `disconnectRequested` and assert it is true then, and false again after disconnect completes.
- Three-pass review: (1) compatibility — additive correction to the existing snapshot boolean; (2) lifecycle — public snapshot now reflects the committed disconnect transition during observer callbacks; (3) regression — assertions cover both pending and completed states.
- Commits: `008d4d3de4cf84dfbf80b5200bccd9a5a3bdc67b` (snapshot projection), `232e169e73fe90445ba8bf830898653e16c93ba9` (regression assertion). Dedicated Fusion test count remains 42.


## 2026-11-25 — Final-state observer disconnect race

- Found a completion-window race during the final transition to `connected`: a synchronous lifecycle observer could call `disconnect()` from the `stateChanged(connected)` event. The disconnect operation was committed and waiting for the current connect operation, but `connect()` could still return a successful result before unwinding.
- Added a final cancellation check after final lifecycle notifications and before constructing the success result. If an observer committed teardown in that window, the connect operation now rolls back its started handles and returns `E-FUSION-CANCELLED`; the waiting disconnect then completes the serialized cleanup.
- Added a regression test that requests disconnect synchronously from the connected-state observer and asserts a cancellation result, exactly one native start, exactly one native stop, idle state and cleared busy state.
- Three-pass review: (1) API semantics — success is no longer returned after a disconnect transition has been committed; (2) lifecycle — the active handle is rolled back before the waiting disconnect completes; (3) regression — deterministic observer reentrancy coverage checks result, call counts and final state.
- Dedicated Fusion test count: 43 by source test declaration count. Exact-head CI is required; no local Flutter execution is claimed.
- Commits: `1865d2980ad774c5caca22f14fc1951f27c56b08` (completion-window guard), `445937186afd52ea4ad05d719c0c3966617af1a8` (regression test).

- Additional regression: a `verificationPassed` observer can also request teardown synchronously. The test verifies the result is cancellation (not traffic-verified success), with exactly one native start/stop and an idle final state. Dedicated Fusion test count: 44 by source test declaration count.
- Additional test commit: `41ab80eb8b91e13c2431701eb683bd58ba36d8b7`.

## 2026-11-25 — Cancellation at the hopStarting observer boundary

- Found a pre-native-start reentrancy gap: `hopStarting` is synchronously delivered, so an observer could call `disconnect()` after the loop's cancellation check but immediately before `adapter.start()`. The coordinator previously still invoked native start and only rolled it back after the future settled.
- Added a second cancellation check immediately after `hopStarting` delivery and before crossing the adapter boundary. A committed disconnect now returns `E-FUSION-CANCELLED` without starting a native hop.
- Added a regression test asserting zero native start calls, zero stop calls, zero started hops, and an idle/non-busy final state after the waiting disconnect completes.
- Three-pass review: (1) API/event semantics — synchronous observer cancellation is honored at the event boundary; (2) resource lifecycle — no handle is acquired, so no unnecessary native cleanup is scheduled; (3) regression — explicit call-count and final-state assertions.
- Dedicated Fusion test count: 45 by source test declaration count. Exact-head CI remains required; no local Flutter execution is claimed.
- Commits: `230392f94ad51484d8f0522eaeae3caf13e381da` (pre-start cancellation guard), `08cdaa27504cb5ed79468901ccc915560c9cfb62` (regression test).

## 2026-11-25 — Preflight operation-slot reservation

- Found another synchronous reentrancy window: validation rejection telemetry is delivered before the previous implementation reserved the engine's busy/operation slot. A listener could call `connect()` from `validationRejected` and start a valid second plan while the first request was still unwinding.
- The coordinator now reserves its operation slot and completion signal before preflight validation. Validation failure/exception paths release that slot through a dedicated completion helper, allowing a concurrent disconnect to wait for the validation operation rather than racing it.
- Added a regression test where a `validationRejected` observer immediately submits a valid plan. The nested call must return `E-FUSION-BUSY`; no native start is allowed.
- Three-pass review: (1) API semantics — the first request owns the operation slot throughout synchronous preflight; (2) lifecycle — completion is signaled on both validation failure branches and disconnect can serialize behind it; (3) regression — nested valid connect is explicitly rejected and engine returns to non-busy state.
- Dedicated Fusion test count: 46 by source test declaration count. Exact-head CI required; no local Flutter execution is claimed.
- Commits: `84d64ecfd761e9b30b5d4cd24db5d7ca14f580dc` (operation reservation), `4957239d9b35b6b404aadbcc1782a3fa65261d97` (regression test).

## 2026-11-25 — Verifier startup cancellation boundary

- Found a resource-start race at the verification event boundary. `verificationStarted` is synchronously delivered; an observer could call `disconnect()`, completing the cancellation signal, but the current code still evaluated `verifier.verify(plan)` while constructing the `Future.any` inputs. This could allocate probe sockets or other verifier resources after teardown was committed.
- Added a cancellation check immediately after `verificationStarted` and before reading/invoking the verifier. The active native hops are rolled back and the connect result is `E-FUSION-CANCELLED`; no verifier work is started.
- Added a regression test asserting verifier invocation count is zero, native start/stop each occur once, and the engine ends idle and not busy.
- Three-pass review: (1) API semantics — a committed disconnect wins over verification; (2) resource lifecycle — no probe resources are created after cancellation; (3) regression — explicit verifier call-count and native lifecycle assertions.
- Dedicated Fusion test count: 47 by source test declaration count. Exact-head CI is required; no local Flutter execution is claimed.
- Commits: `acceb1369ac66012d2166c9d94860ebe1f8fe06b` (guard), `faccf110ed4762dac55b32361769b64f28d0b1da` (test).

## 2026-11-25 — Disconnect serialization across rejected preflight

- Extended the preflight reentrancy audit to both synchronous observer boundaries that can terminate validation: `validationRejected` and `stateChanged(failed)`.
- Added a regression where the validation-rejection observer requests disconnect. It verifies the original validation result remains stable, no native start/stop is attempted for a plan rejected before acquisition, the disconnect event is emitted once, and the final snapshot returns to idle with no pending disconnect.
- Added a second regression where the failed-state observer requests disconnect. It verifies teardown waits for preflight's reserved operation slot to be released and the final snapshot is idle, not busy, and has no active handles.
- Three-pass review: (1) API compatibility — preflight still reports the original validation failure rather than rewriting it as a cancellation; (2) lifecycle — disconnect waits on the reserved operation completion and does not manufacture native cleanup work; (3) regression — both observer boundaries have explicit final-state assertions.
- Dedicated Fusion test count: 49 by source test declaration count. Exact-head CI is required; no local Flutter execution is claimed.
- Commits: `9127cd7ceb1f6d0804d8508091000b0bb38caf8c` (validation-rejection observer), `766598447dfbd80388d44f1838593caf6b675b07` (failed-state observer), `6918c768b998ae8ecf032b7f1c3aca7e1a89839b` (assertion correction).

## 2026-11-25 — Defensive engine descriptor snapshots

- Extended the public-metadata boundary audit. Adapter descriptors are supplied by external implementations; their `supportedTransports` Set can be mutable even though the descriptor fields themselves are final.
- Added a focused adapter fixture that exposes mutable transport metadata, constructs the Fusion engine, then mutates the source Set. The public descriptor snapshot must preserve the normalized original transport inventory.
- The regression also asserts that both the descriptor transport Set and the returned `availableEngines` collection reject mutation.
- Three-pass review: (1) API contract — callers receive a stable metadata snapshot rather than a live adapter-owned collection; (2) isolation — adapter-side mutations cannot silently rewrite Fusion's public capability view; (3) regression — mutation attempts and source mutation are explicitly covered.
- Dedicated Fusion test count: 50 by source test declaration count. Exact-head CI required; no local Flutter execution is claimed.
- Commit: `42e58180022ccaa03d5b2b9c45f3ab8f56b83297`.

## 2026-11-25 — Capability snapshot behavior under adapter mutation

- Strengthened the descriptor-isolation regression beyond checking immutable presentation: after the adapter mutates its original transport Set from TCP to UDP, the engine still accepts TCP from the captured capability snapshot and rejects UDP as unsupported.
- This verifies that the snapshot is authoritative for preflight validation, not merely a read-only copy returned by `availableEngines`.
- Three-pass review: (1) compatibility — transport matching continues to use the normalized constructor-time contract; (2) isolation — adapter-owned mutable collections cannot rewrite validation behavior; (3) regression — both acceptance of the original capability and rejection of the mutated capability are asserted, with cleanup between attempts.
- Dedicated Fusion test count: 50 declarations remain; the existing regression was expanded rather than adding a new test declaration. Exact-head CI is pending; no local Flutter execution is claimed.
- Commit: `d1581f0a1b852d82d488e85c498d19d30cce9cff`.

## 2026-11-25 — Reentrant cleanup-failure observer regression

- Added an integration-style lifecycle test where the synchronous `cleanupFailed` observer calls `disconnect()` while the original disconnect is still rolling back.
- The nested call must join the already-published disconnect future: it must not recursively emit another teardown, invoke native stop twice, or erase the retained failed handle.
- The test then issues a later independent disconnect and verifies the retained cleanup can be retried successfully, returning the engine to idle and not busy.
- Three-pass review: (1) lifecycle ordering — the original disconnect owns cleanup through observer delivery; (2) resource safety — no duplicate stop is launched from a reentrant observer; (3) recovery regression — a subsequent independent call retries the retained handle.
- Dedicated Fusion test count: 51 declarations by source inspection. Exact-head CI remains pending; no local Flutter execution is claimed.
- Commit: `f280d9aa964724580cf8af80089041024d3d8828`.

## 2026-11-25 — Immutable cleanup-failure result boundary

- Corrected a subtle API immutability gap: `toList(growable: false)` prevents resizing but still permits callers to overwrite existing elements. Fusion now publishes rollback failure identifiers through `List.unmodifiable`.
- Added a regression that attempts to overwrite a returned cleanup-failure engine ID and requires `UnsupportedError`, while retaining the existing cleanup retry assertions.
- Three-pass review: (1) API semantics — the result's cleanup report is immutable rather than merely fixed-length; (2) integrity — consumers cannot rewrite which engine Fusion reports as requiring cleanup; (3) regression — mutation rejection is tested on a real partial rollback result.
- Dedicated Fusion test count: 51 declarations; one existing test expanded. Exact-head CI pending; no local Flutter execution is claimed.
- Commits: `e9828768c2fc3a2a464c5ea97e93112a6b3d5444`, `a6d7867a5da168b9b0139aa4fc0268687bd78806`.
