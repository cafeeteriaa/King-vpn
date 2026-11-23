# King VPN — Engineering Project State

Updated: 2026-11-23
Repository: `cafeeteriaa/King-vpn`
Active audit/continuation branch: `audit/final-master`
Primary VPN implementation branch under separate review: `codex/continuation-mainline-20261122`
Base branch: `main`

## Live source of truth — refresh on every resume

- Current audit branch HEAD at this checkpoint: `36f4af0172aa78b6fc1777e735bbdb0465af7021`.
- PR #44 is OPEN, DRAFT, mergeable, and NOT merged; its current head is the audit branch above. Keep it Draft; do not merge without explicit owner authorization.
- Current `main` SHA: `c43d325f9803d4f6306415e511f6790deff9d87e`; no changes were made to `main`.
- PR #42 remains OPEN and DRAFT at `05fcad8c5c046e647ae62584ba0ac0ed6baf57dd`; PR #43 and #41 remain separate Draft workstreams. Re-read live PR metadata before relying on any of these values.
- Exact-head CI for audit HEAD `36f4af0172aa78b6fc1777e735bbdb0465af7021`: Run `45094289369`, observed `pending` at 2026-11-23 01:23 UTC.
- Previous audit CI Run `45094163106` for documentation checkpoint `9a4b0cddeff3f9ee132b5996e496b7db54029ac0`: observed `in_progress`; Unit Tests and Dart Analysis had passed, ARM64 release APK build was still running, and alignment/artifact steps had not yet completed.
- Last completed exact-code CI Run `45075391129` for `da2733be49b96497edf166311401271e8d2ef2fb`: SUCCESS, including unit tests, Dart analysis, ARM64 release build, 16 KiB ELF/ZIP alignment and artifact upload. This result does not certify later source commits or device runtime.
- Latest code-changing commit in PR #44 at this checkpoint: `da2733be49b96497edf166311401271e8d2ef2fb` (test fixture aligned with the three-probe contract); later commits `9a4b0cd` and `36f4af0` are documentation-only.
- PR #44 contains 13 changed files (README, MainActivity, engineering/AI/roadmap docs, Smart Pilot/network-health implementation and tests, patch gate and repair orchestrator). Re-read its live diff before making changes.
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
- Native lifecycle ownership review was added to `FINAL_MASTER_AUDIT.md`: `kOwnVpnService=false) remains the active default; custom service stop acknowledgement is asynchronous and is not proof that the core/TUN is down. Potential interaction with plugin stop remains a device-validation item, not a proven production bug.
- Existing code and features were preserved; no engine activation, main-branch change, PR merge, or release was performed.

### Current validation boundary

- Latest fully completed CI evidence: Run `45075391129` / commit `da2733be` — SUCCESS.
- A subsequent run for `9a4b0cdd` had passed Unit Tests and Dart Analysis and was observed building the ARM64 APK; final completion was not yet observed.
- Run `45094289369` for current audit HEAD `36f4af01` was pending when checked.
- Device-level Start/Stop, process death, VPN revocation, DNS leak, IPv4/IPv6 packet flow, and Iranian operator-network validation remain NOT TESTED.
- Do not describe any CI artifact as production-signed, install-ready, leak-free, or carrier-validated without separate evidence.

### Immediate continuation order

1. Recheck completion of Runs `45094163106` and `45094289369`; inspect failed steps/logs if either fails.
2. Continue the Android plugin/custom-service ownership audit without changing `kOwnVpnService=false) until device acceptance.
3. Add deterministic coverage for process-death recovery and stop/start ownership only where existing tests do not already cover the interleavings.
4. Continue DNS resolver path and IPv4/IPv6 data-plane audit; require packet/device evidence before acceptance.
5. Review CI permissions, workflow triggers, dependency/license inventory and AI patch gate before broadening autonomous write scope.

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
