# King VPN — continuation checkpoint

## Source of truth
- Repository: `cafeeteriaa/King-vpn`
- Active VPN feature branch: `fix/dns-auto-full-domain-inventory-20261124`
- Native tunnel-ownership implementation under validation: `d6b901bd96b67d69ab164151cfbf0ff42ef6ba64`.
- Parent implementation HEAD: `356d57cc9a111ebafedd16258e15bcc34fa86e3d`.
- PR #48 remains open Draft against `audit/unlimit-known-scanner-candidates-20261123`; no merge to `main`.
- No active GitHub Actions at this repair preparation; no workflow was cancelled.

## Changes under validation
- Pure `androidVpnTunnelEvidence` requires both the live KingVpnService TUN descriptor and an active VPN transport owned by this app.
- `KingVpnService.isKingVpnTunnelActive()` verifies active/non-stopping service state and a valid TUN file descriptor.
- `connectFrom` clears stale active state before failover replaces the current TUN.
- `MainActivity.kt` exposes service-owned tunnel state and Android VPN transport ownership; Android 11+ checks `NetworkCapabilities.ownerUid`.
- Android `tunUp()` uses both native signals with a short retry window and fails closed when native proof is unavailable; interface-name detection is retained only for non-Android.
- Added unit tests and source guards. No IP Clean resources, ranges, ports, UDP inventory, or scanner capabilities changed.

## Validation evidence
- Parent exact HEAD `6dcd53edfad08e19b0ff79290a70e71d041f232f`, CI run 2553 succeeded: source guards, 148 Flutter tests, Dart analyze exit 0, and ARM64 release build: https://github.com/cafeeteriaa/King-vpn/actions/runs/45354384055
- First CI for native ownership commit `d6b901bd96b67d69ab164151cfbf0ff42ef6ba64`, run 2554, failed in the Python source-guard step only: 238 guard tests ran, with two failures caused by stale test expectations for a one-line `if (evidence == true) return true;`; the implementation uses a braced block. Flutter unit tests, analyze, and Android build were skipped: https://github.com/cafeeteriaa/King-vpn/actions/runs/45356296860
- This repair changes only those source-guard assertions to match the actual braced implementation. It does not change production code.
- Exact-head CI must pass before the native tunnel ownership change is considered validated.

## Open limitations
- Android 11+ owner UID is checked. Android 10 and older use the custom service's live TUN descriptor plus active VPN transport because the owner field is not used there.
- The native checks prove service/TUN ownership, not end-to-end traffic. HTTP response verification remains a separate gate.
- No physical-device, competing-VPN, Android 10/11+, Iranian carrier, DNS packet-capture, or live IPv4/IPv6 data-plane test has been performed.
- DNS route/leak, native stop/start ordering, failover races, IPv6 data-plane, and CPU/battery profiling remain open.
- The feature branch is heavily diverged from `audit/final-master`; do not merge branches wholesale.

## First next action
1. Rerun exact-head CI after the source-guard syntax correction; require all Python source guards, Flutter tests, `flutter analyze`, and the ARM64 release build to pass.
2. If successful, inspect the exact-head artifact and checksum.
3. Then test competing-VPN takeover, service stop/revoke, Android 10 compatibility, Android 11+ owner UID, network handover, and DNS traffic through the selected TUN/core on physical devices.
