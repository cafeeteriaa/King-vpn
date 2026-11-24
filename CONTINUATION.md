# King VPN — continuation checkpoint

## Source of truth
- Repository: `cafeeteriaa/King-vpn`
- Active feature branch: `fix/dns-auto-full-domain-inventory-20261124`
- Parent HEAD before this checkpoint: `7021ed70a7b793d83517ad3ddf8572f959e7a18e`
- PR #48: open Draft, base `audit/unlimit-known-scanner-candidates-20261123`; not merged to `main`.
- No GitHub Actions run was active on this branch when this change was prepared. No run was cancelled.

## Change prepared for exact-head CI
- IP Clean's explicit user-entered IPv4/IPv6 ranges now retain the complete valid TCP port inventory (1–65535), in priority order with resumable per-port/per-range cursors.
- Exact IP endpoints derived from configured VPN server records remain scoped to the port declared by each server record; a separate explicit range does not widen those exact-host probes.
- Added pure scope-selection logic and Dart coverage for full-range inventory and exact-endpoint port behavior.
- Updated source guards for the active-range/full-port contract.
- No source catalogs, user ranges, endpoint records, UDP inventory, or scanner features were deleted.

## Validation
- New source commit: pending creation; parent is the HEAD listed above.
- Focused test added: `test/nat_ip_scan_test.dart` — explicit ranges retain all 65,535 TCP ports; exact configured endpoints retain only declared ports.
- Source guard added/updated: `test/test_source_guards.py`.
- New-change Flutter tests, `flutter analyze`, and arm64 release build: pending exact-head GitHub Actions.
- Last completed exact-head CI before this change: run 2542, success for `7021ed70a7b793d83517ad3ddf8572f959e7a18e`: https://github.com/cafeeteriaa/King-vpn/actions/runs/45349053733 (source guards, Flutter tests, Dart analysis, arm64 APK build and artifact upload).

## Open limitations
- The full port inventory is resumed one port and one bounded address slice at a time; it is not an instantaneous exhaustive sweep.
- Active range scanning is limited to ranges explicitly entered in IP Clean. Exact configured server IPs are not expanded to adjacent networks and are tested on their declared ports only.
- No real Android device, Iranian carrier, live tunnel traffic, DNS packet capture, or CPU/battery profiling was performed in this run.
- Android VPN ownership, DNS leak verification, and service lifecycle/failover runtime checks remain open.

## First next action
1. Wait for a GitHub Actions run whose tested SHA equals the new source commit; inspect source guards, Flutter tests, `flutter analyze`, arm64 build and artifact metadata.
2. If CI passes, update this file with the exact source SHA and run URL/status, then continue Android device VPN-owner and DNS data-plane validation.
