# King VPN — continuation checkpoint

## Source of truth
- Repository: `cafeeteriaa/King-vpn`
- Active VPN feature branch: `fix/dns-auto-full-domain-inventory-20261124`
- Implementation parent HEAD before this checkpoint commit: `5e3b34e85202ca10b1f8af48e9e7984a5bede028`.
- This checkpoint commit advances the branch; resolve its exact HEAD from the branch ref after push.
- PR #48 remains open Draft against `audit/unlimit-known-scanner-candidates-20261123`; no merge to `main`.
- Active GitHub Actions at commit preparation: none. No workflow was cancelled.

## Changes in this checkpoint
- Corrected the stale default-port inventory test: the default complete TCP-connect inventory is 1..65535, so it has 65,535 entries and does not include reserved port 0.
- Kept explicit `firstPort: 0` support and its 65,536-entry test, so the generic inventory helper has not removed that opt-in capability.
- Clarified the helper documentation to distinguish the default inventory from an explicit request for port 0.
- No IP Clean sources, CIDRs, ranges, ports, address candidates, UDP inventory, or scan features were removed or narrowed.

## Validation evidence
- Exact HEAD `5e3b34e85202ca10b1f8af48e9e7984a5bede028`, CI run 2552: source-repair guard passed; Flutter unit tests failed with 147 passed / 1 failed. The sole failure was the stale expectation that the default port inventory contains port 0 and has 65,536 entries. Analyze and Android build were skipped after the unit-test failure: https://github.com/cafeeteriaa/King-vpn/actions/runs/45353042246
- The failing test was inspected from the CI job log and reproduced as an assertion mismatch against the implementation default `firstPort = 1`; this checkpoint changes the test and documents that default.
- No local Flutter toolchain is available in this automation runtime; exact-head CI is the required validation path after this commit.

## Open limitations
- Full TCP port inventory remains incremental and resumable; it is not an instantaneous exhaustive scan.
- Broad active port testing remains scoped to explicitly configured IP Clean ranges. Exact saved VPN endpoint IPs use ports declared in their server records; no adjacent ranges are inferred.
- Port 0 is retained as an explicit helper option, but is excluded from default TCP connect attempts because `Socket.connect` cannot target TCP port 0.
- Android device/carrier testing, packet-level DNS leak capture, live IPv6 tunnel validation, VPN ownership/rival-VPN scenarios, and CPU/battery profiling remain unverified.
- DNS route/leak, native service lifecycle, and failover race validation remain open.

## First next action
1. Wait for the exact new HEAD's CI; require source guards, Flutter unit tests, `flutter analyze`, and the ARM64 release build to pass.
2. Inspect the artifact only if that exact commit's workflow succeeds.
3. Then continue device-level validation of DNS through TUN/core, VPN ownership and handover, IPv6 data plane, failover, and CPU/battery behavior.
