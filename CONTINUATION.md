# King VPN — continuation checkpoint

## Source of truth
- Repository: `cafeeteriaa/King-vpn`
- Active VPN feature branch: `fix/dns-auto-full-domain-inventory-20261124`
- Implementation parent HEAD before this checkpoint: `356d57cc9a111ebafedd16258e15bcc34fa86e3d`.
- This checkpoint adds native tunnel-ownership proof; resolve its exact implementation HEAD from the branch ref after push.
- PR #48 remains open Draft against `audit/unlimit-known-scanner-candidates-20261123`; no merge to `main`.
- No active GitHub Actions were present when preparing this change. No workflow was cancelled.

## Changes in this checkpoint
- Added a pure `androidVpnTunnelEvidence` decision helper: both a live KingVpnService TUN descriptor and an active VPN transport owned by this app are required; either definitive negative rejects the tunnel.
- Added `KingVpnService.isKingVpnTunnelActive()`, which requires the custom service instance to be active, not stopping, and to hold a valid TUN file descriptor.
- Cleared the service's stale active flag before starting a failover server, preventing the previous connection from being reported as active while its TUN is being replaced.
- Added native `vpn/bg` methods for service-owned TUN state and active VPN transport ownership. Android 11+ checks `NetworkCapabilities.ownerUid`; older Android versions require the service-owned TUN plus VPN transport.
- Reworked Android `tunUp()` to use both native signals with a short retry window and fail closed if native proof is unavailable. Generic interface-name detection is retained only for non-Android compatibility.
- Added Dart unit tests and source guards for positive, negative, incomplete, owner-UID, TUN-descriptor, and failover evidence.
- No IP Clean sources, ranges, ports, UDP inventory, or scanner capabilities were changed.

## Validation evidence
- Parent code HEAD `6dcd53edfad08e19b0ff79290a70e71d041f232f` passed CI run 2553: source guards, 148 Flutter tests, Dart analyze exit 0, and ARM64 release build: https://github.com/cafeeteriaa/King-vpn/actions/runs/45354384055
- The parent run's analyzer reported 248 info/warning-level lint findings under `--no-fatal-warnings --no-fatal-infos`; these remain technical debt.
- This checkpoint's native tunnel ownership change has not yet been validated by CI. Require exact-head source guards, Flutter tests, analyze, and ARM64 build before claiming success.
- No physical-device, competing-VPN, Android 10/11+, Iranian carrier, DNS packet-capture, or live IPv4/IPv6 data-plane test has been performed.

## Open limitations
- Android 11+ owner UID is checked. Android 10 and older cannot use this owner field; the custom service's own live TUN descriptor plus active VPN transport is used as the compatibility proof.
- The native check confirms service/TUN ownership, not end-to-end traffic. Actual HTTP responses through the core remain a separate acceptance gate.
- DNS route/leak verification, native stop/start ordering, failover races, IPv6 data-plane, and CPU/battery profiling remain open.
- The feature branch remains heavily diverged from `audit/final-master`; do not merge branches wholesale. Port only isolated fixes with matching tests.

## First next action
1. Run exact-head CI and fix any demonstrated failure without cancelling the run.
2. If CI passes, inspect the exact-head ARM64 artifact and checksum; it remains debug-key signed and not device-validated.
3. Test competing-VPN takeover, service stop/revoke, Android 10 compatibility, Android 11+ owner UID, and network handover on physical devices; then verify DNS traffic through the selected TUN/core path.
