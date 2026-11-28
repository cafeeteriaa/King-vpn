# KING VPN continuation checkpoint

Updated: 2026-11-28 (Europe/Rome)

## Repository state
- Repository: `cafeeteriaa/King-vpn`
- Active development branch: `feat/net-melli-runtime-hardening-20261128`
- Parent / pre-checkpoint HEAD SHA: `bba3cc009d4c2d5b8c4519df191da8142106c740`
- Current development PR: [#89](https://github.com/cafeeteriaa/King-vpn/pull/89), Draft, open, not merged
- PR base: `feat/king-national-scanner-engine-20261127` at `252637cbe08721db1c3675544b761de4b97e98bf`
- Default branch `main`: `9b36ae7dd9ac0379a3b3b84091752f9322bb649d`; untouched
- No `CONTINUATION.md` existed anywhere in the recursive tree at the pre-checkpoint HEAD. This file is being added now.
- No active Actions run was listed for this development branch immediately before this commit. No run was cancelled.

## Changes in this checkpoint
- Fixed the compile error in `test/king_nat_subsystem_engine_test.dart`: the `recordTransformationExecution` call now supplies the required `coverageComplete: true` argument.
- Strengthened the reset test to assert that one transformation attempt and its validated adapter evidence exist before the next independent run, then assert both are cleared after `beginRun`.
- No production VPN code, endpoint inventories, IP Clean sources, ranges, ports, cursors, or scanner capabilities were removed or narrowed.
- No Gemini, Grok, paid model, or API-key-dependent service was introduced.

## Validation evidence before this checkpoint
- GitHub Actions run [#4718](https://github.com/cafeeteriaa/King-vpn/actions/runs/46119623044), tested commit `bba3cc009d4c2d5b8c4519df191da8142106c740`: **failure**.
- Source-repair guard: passed.
- Focused national scanner tests: passed.
- Durable scanner journal tests: passed.
- Net Melli IPv4/IPv6 endpoint tests: passed.
- Full Flutter unit tests: 238 passed, 1 failed to compile because the test call omitted required named parameter `coverageComplete`.
- Flutter analysis and Android arm64 release build: skipped by workflow after unit-test failure; no APK artifact was produced for this run.
- This patch has not yet been validated by a new CI run. Do not claim it passes until the run for the resulting commit completes.

## Open engineering issues
1. The 13 internal Net Melli subsystem coordinator IDs are wired into the runtime, but this is not proof that every planned adapter or capability is implemented. UDP discovery, comprehensive CDN/DPI adapters, raw packet transformations, broad IPv6 enumeration, and autonomous AI repair remain partial or unimplemented until adapters and end-to-end tests exist.
2. Real-device tests are still required for Iranian mobile/fixed carriers, domestic vs global routing, active VPN handover, actual tunnel traffic, DNS leak behavior, IPv4/IPv6, battery and CPU use.
3. CI cannot establish production connectivity on Iranian carriers. No physical-device or carrier validation is claimed here.
4. The four-million profile store and the independent healthy-server folder must retain their separate storage/retention policies; do not conflate this with IP Clean inventory or cap its sources/ranges/ports.

## Review passes for this patch
1. API/compile review: verified the implementation signature requires `coverageComplete`; the failing call was the only missing argument found in this test file.
2. Test-semantics review: the test now proves evidence exists before reset and is empty after the next run; it uses only deterministic in-memory test evidence.
3. Regression/safety review: no production behavior, network scope, resource inventory, secrets, or credentials are changed.

## Exact first next action
Inspect the new GitHub Actions run for the resulting branch HEAD. If full unit tests pass, confirm `flutter analyze` and the optimized Android arm64 release build both run and pass; then inspect the artifact for that exact commit. If any stage fails, retrieve its job log, identify the concrete failure, and make the smallest evidence-backed correction. After CI settles, update this checkpoint with the resulting commit SHA, run URL/status, and artifact verification status. Keep PR #89 open and do not merge to `main`.
