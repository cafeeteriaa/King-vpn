# King VPN — continuation checkpoint

## Source of truth
- Repository: `cafeeteriaa/King-vpn`
- Active VPN feature branch: `fix/dns-auto-full-domain-inventory-20261124`
- Current implementation under validation: previous HEAD `647eea8feac0b34d3b66f24cfd399ed14f55e11e`; this checkpoint repairs the port-test regression and explicitly declares the network-state permission required by the new Android ownership query.
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
