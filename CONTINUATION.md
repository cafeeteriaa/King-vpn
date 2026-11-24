# King VPN — continuation checkpoint

## Source of truth
- Repository: `cafeeteriaa/King-vpn`
- Active feature branch: `fix/dns-auto-full-domain-inventory-20261124`
- Code HEAD under validation: `a749e6dfa3b0a71ebd11d00e8460cc4ed98b9fee` (parent: `7021ed70a7b793d83517ad3ddf8572f959e7a18e`).
- PR #48 remains open Draft, based on `audit/unlimit-known-scanner-candidates-20261123`; not merged to `main`.
- All GitHub Actions active at the start of this repair: none. No workflow was cancelled.

## Change under validation
- Explicitly saved IP Clean IPv4/IPv6 ranges use the complete valid TCP port inventory (1–65535), with prioritized ordering and resumable per-port/per-range cursors.
- Exact configured VPN server IPs outside those ranges are tested only on the ports declared in their server records.
- Added `natPortsForActiveScan` and a Dart unit test that verifies the full inventory for explicit ranges and declared-port-only behavior for exact endpoints.
- Source guards now verify the explicit-range full-port path and the exact-endpoint guard.
- No source lists, range entries, ports, UDP inventory, or IP Clean features were deleted.

## Validation evidence
- Previous parent exact-head CI run 2542 succeeded for `7021ed70a7b793d83517ad3ddf8572f959e7a18e`: https://github.com/cafeeteriaa/King-vpn/actions/runs/45349053733.
- First CI attempt for `a749e6dfa3b0a71ebd11d00e8460cc4ed98b9fee`, run 2543, failed in the Python source-guard stage before Flutter tests/analyze/build. The sole failure was a stale assertion in `test_nat_range_scan_uses_budget_sized_per_port_batches` expecting the removed `.where(configuredPorts.contains)` filter. The production change and new Dart test were not reached by that workflow.
- Correcting that guard is the only change in the current follow-up commit; a new exact-head CI run is required.

## Open limitations
- Full TCP port inventory runs incrementally, one port and one bounded address slice per invocation; not an instantaneous exhaustive sweep.
- Broad active port testing applies only to ranges explicitly entered in IP Clean. Exact configured server addresses remain limited to declared ports; adjacent ranges are not inferred.
- No Android device, Iranian carrier, packet-level DNS capture, live tunnel, IPv6 data-plane, or CPU/battery profiling was available in this run.
- Android VPN ownership, DNS route/leak verification, service lifecycle and failover race validation remain open.

## First next action
1. Run the source guards again on the corrected exact HEAD, then require Flutter unit tests, `flutter analyze`, and arm64 release build to pass for that same SHA.
2. If CI passes, record its run URL/status and inspect the exact-head artifact before any APK is presented.
3. Continue Android device validation of VPN ownership and DNS traffic through the intended core/TUN path.
