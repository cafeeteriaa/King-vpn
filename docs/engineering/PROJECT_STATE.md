# King VPN — Engineering Project State

Updated: 2026-11-23
Repository: `cafeeteriaa/King-vpn`
Active audit/continuation branch: `audit/final-master`
Primary VPN implementation branch under separate review: `codex/continuation-mainline-20261122`
Base branch: `main`

## Live source of truth — refresh on every resume

- Current audit branch HEAD at this checkpoint: `16590fb5bd2f074c79569ee51ccac56a09a42d92` (documentation-only refresh after `36f4af0`).
- PR #44 is OPEN, DRAFT, mergeable, and NOT merged; its current head is the audit branch above. Keep it Draft; do not merge without explicit owner authorization.
- Current `main` SHA: `c43d325f9803d4f6306415e511f6790deff9d87e`; no changes were made to `main`.
- PR #42 remains OPEN and DRAFT at `05fcad8c5c046e647ae62584ba0ac0ed6baf57dd`; PR #43 and #41 remain separate Draft workstreams. Re-read live PR metadata before relying on any of these values.
- Exact-head CI for audit HEAD `16590fb5bd2f074c79569ee51ccac56a09a42d92`: Run `45094539188` (run 2145), currently `in_progress`; source guard, Flutter unit tests, and Dart analysis passed, while the ARM64 release APK build is still running. Alignment and artifact-upload steps have not yet run.
- Run `45094163106` for prior docs checkpoint `9a4b0cddeff3f9ee132b5996e496b7db54029ac0`: completed SUCCESS, including ARM64 build, 16 KiB ELF/ZIP alignment, and artifact uploads. It is not exact-head evidence for `16590fb`.
- Run `45094289369` for `36f4af0172aa78b6fc1777e735bbdb0465af7021`: CANCELLED; do not treat it as a validation failure or success.
- Last completed exact-code CI Run `45075391129` for `da2733be49b96497edf166311401271e8d2ef2fb`: SUCCESS, including unit tests, Dart analysis, ARM64 release build, 16 KiB ELF/ZIP alignment and artifact upload. This result does not certify later source commits or device runtime.
- Latest code-changing commit in PR #44 at this checkpoint: `da2733be49b96497edf166311401271e8d2ef2fb` (test fixture aligned with the three-probe contract); later commits `9a4b0cd` and `36f4af0` are documentation-only.
- PR #44 currently contains 14 changed files (README, MainActivity, engineering/AI/roadmap docs, Smart Pilot/network-health implementation and tests, patch gate and repair orchestrator). Its base is the live PR #42 branch head `05fcad8c5c046e647ae62584ba0ac0ed6baf57dd`; it remains Draft and unmerged.
- Repository write permission was confirmed. No changes were made to `main`.

## Latest implementation under review

### Native lifecycle stop-marker race

Implementation commit: `896dda05d16b2ec8f4aea1d5490ed61ff35a34f4`.

- Added `requestStopAndPersist(context)`, holding `lifecycleLock` across stop-generation invalidation and the synchronous durable `user_stopped=true` write.
- Routed app Stop, notification Stop, unknown service action, and VPN revocation through the atomic helper.
- Added `persistStopStateIfCurrent(context)` so delayed failure cleanup writes only while its exact stop generation still owns the service.
- `invalidateRecoveryAfterStartFailure` now checks `stopping`, `userStopped`, and `attemptSeq == requestedStopGeneration` while holding `lifecycleLock`; stale failures cannot erase a newer Start's saved recovery state.
- All-server failure and foreground-notification failure use generation-scoped stop persistence.
- The implementation relies on Java monitor reentrancy when `requestStopAndPersist` calls `requestStop()`; this is valid for the same monitor.
- Lock-order inspection: nested service state paths use `lock -> lifecycleLock`; the new stop helper uses `lifecycleLock` without acquiring `lock`. No reverse nested acquisition was found in the inspected paths.
- Residual limitation: SharedPreferences `commit()` remains synchronous on the service command path. It was already synchronous before this change; holding the lifecycle monitor through the commit lengthens the critical section. Measure main-thread latency on device before changing durability semantics.

Latest test-only code commit: `0ad29bfe7eb30b13eff2f3949b0b6086bedc6545`.

- Updated source guards to assert the new helper call sites and lifecycle-lock ordering.
- No production behavior changed in this final code commit.

## Three independent reviews

### REVIEW-1 — Technical correctness: PASS WITH LIMITATIONS

- Stop invalidation and durable stop-marker persistence are now serialized against Start's recovery-latch release under the same lifecycle monitor.
- Delayed Start failures and stale all-server/foreground failure paths are fenced by stop-generation ownership.
- The Start path persists the new server list before releasing the recovery latch; the latch release is generation-checked under `lifecycleLock`.
- The stop cleanup checks its captured stop generation before clearing saved state or stopping the service.
- Java synchronized monitor reentrancy makes the nested `requestStop()` call safe.
- Limitation: source inspection and source guards do not prove every possible Android scheduling interleaving; deterministic concurrency tests and device lifecycle tests remain desirable.

### REVIEW-2 — Security, stability, and side effects: PASS WITH LIMITATIONS

- Stop/revocation remains fail-closed: the durable stop marker is committed before asynchronous core/TUN cleanup; clearing saved recovery state remains the fallback if the marker write fails.
- No credentials, keys, user configuration schema, IP Clean ranges, or VPN protocol behavior were changed by this lifecycle patch.
- Stale cleanup is prevented from erasing a newer Start's persisted server list.
- Inspected lock nesting did not reveal a reverse lock-order cycle in the touched paths.
- Residual risks: synchronous SharedPreferences commits can add main-thread latency; Android process death, permission revocation, OEM foreground-service behavior, and real native-core stop/start races still require device validation. If both durable marker and state-clear operations fail, the code logs the failure but cannot guarantee persisted stop intent.

### REVIEW-3 — Independent diff and validation: PASS WITH LIMITATIONS

- Re-read the implementation diff and final source-guard diff at exact tested code HEAD.
- Exact-head GitHub Actions run 2130 (`45047539595`) for `0ad29bfe7eb30b13eff2f3949b0b6086bedc6545` completed SUCCESS.
- Successful CI steps: source-repair guard, Java/Gradle/Flutter setup, generated Flutter host preparation, dependency resolution, V2Ray plugin patch, unit tests, Dart analysis, optimized arm64 release APK build, 16 KiB ELF load-segment alignment, 16 KiB APK ZIP alignment, and APK/source/symbol artifact uploads.
- Exact-head APK artifact: `king-vpn-arm64-release-2130`, artifact ID `14763823062`, archive size `49,011,435` bytes, GitHub archive digest `sha256:664050952e07aa316530bca4e7c8cc99698b2ba4e7f5b723db42b24de534a816`.
- Downloaded archive SHA-256 independently matched GitHub's digest.
- Extracted APK size: `122,885,758` bytes; inner APK SHA-256: `67828ad04e885675161fcadd66aec5c27106ece2e24abd269abdf45f9c9e4618`.
- APK archive contains one arm64 release APK. Inspected entries include arm64 native libraries for Flutter, V2Ray, tun2socks, and local inference libraries.
- Limitation: this environment did not have `apksigner`, `aapt`, or `apkanalyzer`; APK package metadata and signing certificate were not independently verified. CI did not report a production-signing or device-install validation step.

## Acceptance status

- IMPLEMENTED: native lifecycle stop-marker serialization and stale failure fencing.
- REVIEWED-1: PASS WITH LIMITATIONS.
- REVIEWED-2: PASS WITH LIMITATIONS.
- REVIEWED-3: PASS WITH LIMITATIONS.
- TESTED: exact-head CI unit-test and source-guard steps passed.
- BUILT: exact-head arm64 release APK built by CI.
- ALIGNMENT: 16 KiB ELF and APK ZIP alignment steps passed.
- ARTIFACT: archive digest independently matched GitHub's reported digest; inner APK SHA-256 recorded above.
- SIGNING: NOT VERIFIED in this environment.
- DEVICE / VPN RUNTIME: NOT TESTED.
- DNS leak / IPv4 / IPv6 traffic-path acceptance: NOT TESTED.
- Iranian operator-network / national-internet acceptance: NOT TESTED.
- Production release / install-ready: NOT VERIFIED.

Final status: VERIFIED WITH LIMITATIONS. This CI artifact is not declared production-ready or device-accepted.

## Resume checkpoint — 2026-11-23

### Work completed in the current audit stream

- Smart Pilot evidence hardening: invalid/unknown latency is not accepted as a route-switch signal; the dedicated probe uses a 2-of-3 TLS quorum, validates sample counters, and only caches evidence against a known transient Android network identity.
- Network handover protection: before/after physical-network identity must match; mixed snapshots are discarded and retried once. Forced refreshes are serialized behind an active ordinary refresh.
- AI repair security: automatic patches are limited to `lib/` and `test/`; executable, native, workflow, dependency and tooling paths require owner review. The repair orchestrator no longer executes untrusted patch code on the developer host; CI on the exact PR commit is the validation boundary.
- Native lifecycle ownership review was added to `FINAL_MASTER_AUDIT.md`: `kOwnVpnService=false` remains the active default; custom service stop acknowledgement is asynchronous and is not proof that the core/TUN is down. Potential interaction with plugin stop remains a device-validation item, not a proven production bug.
- Existing code and features were preserved; no engine activation, main-branch change, PR merge, or release was performed.

### Current validation boundary

- Latest fully completed CI evidence before the current exact-head run: Run `45094163106` / commit `9a4b0cd` — SUCCESS. This commit is documentation-only after code commit `da2733be`; it confirms the same code tree but is not the current exact HEAD.
- Run `45094539188` for current audit HEAD `16590fb` is in progress; Source Guard, Flutter Unit Tests, and Dart Analysis are successful; ARM64 APK build is in progress.
- Device-level Start/Stop, process death, VPN revocation, DNS leak, IPv4/IPv6 packet flow, and Iranian operator-network validation remain NOT TESTED.
- Do not describe any CI artifact as production-signed, install-ready, leak-free, or carrier-validated without separate evidence.

### Immediate continuation order

1. Poll Run `45094539188` to completion; inspect build/alignment/artifact steps and verify artifacts before claiming exact-head Build success.
2. Continue Android plugin/custom-service ownership audit without changing `kOwnVpnService=false` until device acceptance. Existing source guards already cover stop-vs-start, stale cleanup, revocation, sticky restart, and generation ownership; do not duplicate them. Add deterministic concurrency tests only if they exercise interleavings not represented by those source guards.
3. Continue DNS resolver path and IPv4/IPv6 data-plane audit; require packet/device evidence before acceptance. Current global Secure DNS is DoH-first with serialized queries but retains plaintext fallback; national mode places domestic resolvers before DoH fallback. Neither behavior is proof of zero DNS leakage.
4. Review CI permissions, workflow triggers, dependency/license inventory and AI patch gate before broadening autonomous write scope.
5. Reconcile the stale `CONTINUATION.md` header on PR #42: it names `c23e607` while the live PR #42 head is `05fcad8`; do not treat the checkpoint's embedded SHA as the live branch ref.

## Next engineering priorities

1. Audit plugin-managed and custom-native start/stop ownership boundaries; `kOwnVpnService=false` remains the active default until custom native service device acceptance.
2. Add deterministic tests for Stop-vs-Start, delayed failure-vs-new Start, process-death recovery, and stale cleanup interleavings where practical.
3. Validate DNS resolver routing through the selected core and confirm there is no IPv4/IPv6 bypass with packet-level/device tests.
4. Run Android device tests for notification Stop, VPN revocation, process death, foreground-service restrictions, native core hang/recovery, and repeated network handovers.
5. Validate real tunnel traffic, not just CONNECTED state, DNS replies, endpoint ping, TCP opens, or TLS handshakes.
6. Validate national/global routing on real operator networks separately.
7. Inspect APK package/version/signing metadata with Android SDK tools when available; do not reuse older artifacts as evidence for newer source.
8. Keep PR #42 Draft and unmerged until exact-head CI and required device acceptance are complete.

## Guardrails

- VPN-first: connection correctness, data-plane traffic, tunnel lifecycle, DNS/routing, IPv4/IPv6, and stability outrank AI features.
- Preserve owner changes and existing IP Clean sources/ranges/ports/scan behavior.
- Never infer domestic hosting or successful national reachability from country labels alone.
- Keep CI evidence separate from device/operator-network evidence.
- Do not claim install-ready, production-signed, leak-free, or carrier-validated without corresponding evidence.


## Additional live audit findings — 2026-11-23

- Live branch resolution: `audit/final-master` = `16590fb5bd2f074c79569ee51ccac56a09a42d92`; `main` = `c43d325f9803d4f6306415e511f6790deff9d87e`; PR #44 is open Draft with base `codex/continuation-mainline-20261122` at `05fcad8c5c046e647ae62584ba0ac0ed6baf57dd`. PR #42 is independently open Draft at that same base-branch HEAD. No merge was performed.
- The mainline `CONTINUATION.md` content has a stale embedded current-head field (`c23e607d...`) while GitHub's live PR #42 head is `05fcad8c...`; always trust the live ref/PR metadata and reconcile the checkpoint before relying on it.
- DNS static review: `_reliableVpnCfg` applies `mergeNationalDnsServers` in national mode and DoH-first ordering plus `enableParallelQuery=false` for global Secure DNS outside Ultra mode. Plaintext fallback entries remain configured globally, and national mode deliberately keeps domestic resolvers first. This is an explicit availability trade-off, not a strict no-plaintext guarantee. DNS routing through the intended core and IPv4/IPv6 leak behavior remain unverified without device packet evidence.
- Android service review: `requestStopAndPersist` serializes stop-generation invalidation and durable marker write under the reentrant `lifecycleLock`; `stopEverything` queues/executes cleanup asynchronously and the MethodChannel stop handler acknowledges the request before core/TUN shutdown is proven. `kOwnVpnService=false` remains the active plugin-managed path. Existing source guards already cover many lifecycle interleavings; no duplicate guards or speculative production changes were added.


## CI and release-supply-chain hardening — 2026-11-23

- Added a job-level owner gate to `.github/workflows/signed-release.yml`: the job runs only when `github.actor == github.repository_owner`. This gate is evaluated before any production signing or update-manifest secrets are exposed to steps.
- Added a source guard requiring every remote GitHub Action referenced by workflow YAML to use a full 40-character commit SHA; local `./` actions remain exempt.
- Pinned remote actions in all four workflow files to commit SHAs resolved from their upstream GitHub release refs: checkout `11d5960a326750d5838078e36cf38b85af677262`; setup-java `cf277c60eb25467037889841efdb72551f06f6c3`; Gradle setup `ed408507eac070d1f99cc633dbcf757c94c7933a`; Flutter action `1a449444c387b1966244ae4d4f8c696479add0b2`; upload-artifact `ea165f8d65b6e75b540449e92b4886f43607fa02`. Gradle's v4.4.3 annotated tag was dereferenced to its commit and its tag signature reported valid by GitHub.
- Commits: owner gate `c15b1537fa01f5e68d6047df54d397c953835f16`; owner-gate source guard `419aba25acd1b11fbd3492536853989c71d5bb8b`; consolidated workflow SHA pins and SHA guard `844a5f6341b9b2ad9e97e98f515b761a65aee776`.
- These workflow changes are not yet declared CI-validated. Wait for a successful run on the final live branch HEAD. The owner gate is a workflow authorization boundary, not a replacement for repository permissions or protected-secret controls.

## Resume checkpoint — 2026-11-23 (live-head reconciliation and workflow review)

- Live PR #44 metadata was refreshed before this checkpoint write: OPEN, DRAFT, mergeable, base `codex/continuation-mainline-20261122`, head `audit/final-master`, preceding head SHA `7c5c5a96367d635f3b0f96732c02d6354835125b`. This documentation checkpoint advances the branch to `aa62b09b339a2abd6da70899065903c9b4fc8710`; PR #44 remains unmerged and `main` was not changed.
- Current code-changing commit on the audit branch: `649147e8a3c96979f1bbab82c14ccff09f6bbf2d` (Android 11+ VPN owner-UID check and source guard). The live head `7c5c5a9` is a documentation-only `[skip ci]` checkpoint after that code commit.
- Exact-code CI Run 2157 (`45132996395`) for `649147e` completed SUCCESS. Successful steps include source guards, Flutter unit tests, Dart analysis, optimized arm64 release build, ELF 16 KiB alignment, APK ZIP alignment, and APK/source/symbol artifact uploads. Artifacts are CI-signed, not production-signed. No device/runtime acceptance is implied.
- Exact-head CI Run 2145 (`45094539188`) for earlier checkpoint `16590fb` also completed SUCCESS and produced arm64 APK, full-source ZIP, and symbols. It is historical evidence for that exact source head, not a replacement for Run 2157.
- PR #44 changed-file inventory was refreshed: 19 paths across four workflows, Android network identity/owner check, Smart Pilot/network-health code and tests, repair gate/orchestrator, and engineering/roadmap documentation.
- Workflow static review: Android build workflow declares `contents: read`; remote Actions are pinned to full commit SHAs. Signed release workflow requires the triggering actor to equal the repository owner, checks that the tag is reachable from main, and verifies the APK certificate against the configured keystore before publishing. These controls were inspected statically; no production release was run.
- King AI dataset collection is restricted to merged same-repository `king-ai/*` PRs into main, an explicit small file allowlist, all-success checks on the exact PR head, independent human approval on that exact SHA, and secret scanning. Training runs on a labeled self-hosted GPU runner, packages a candidate artifact, and does not deploy model weights.
- Repair gate/orchestrator review: automatic candidate patches are restricted to `lib/` and `test/`, reject binary/symlink/submodule/executable-mode changes and common secret patterns, check existing symlinks, and apply only to a temporary copy. Candidate code is not executed locally; CI and human diff review remain required. This is a structural gate, not a general sandbox.
- DNS policy review reconfirmed the intentional availability trade-off: national mode prefers domestic resolvers; global Secure DNS orders DoH before plaintext fallback. Unit tests cover ordering/filtering, but DNS resolution through the selected VPN core and leak resistance remain NOT TESTED at packet/device level.
- Open acceptance blockers remain: physical-device Start/Stop and process-death/revocation tests; competing-VPN ownership behavior on Android 11+; IPv4/IPv6 and DNS packet-level leak tests; real operator/national-network tests; performance/thermal/battery benchmarks; dependency license/SBOM/CVE inventory; comprehensive secret scan of Git history and artifacts; and full UI/feature inventory.
- Status remains **IN PROGRESS / VERIFIED WITH LIMITATIONS**. No merge, production release, or device acceptance was performed.
