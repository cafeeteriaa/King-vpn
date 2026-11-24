# King VPN — continuation checkpoint

## Source of truth
- Repository: `cafeeteriaa/King-vpn`
- Active VPN feature branch: `fix/dns-auto-full-domain-inventory-20261124`
- Validated implementation HEAD SHA: `6dcd53edfad08e19b0ff79290a70e71d041f232f`.
- Parent of the validated implementation commit: `5e3b34e85202ca10b1f8af48e9e7984a5bede028`.
- PR #48 remains open Draft against `audit/unlimit-known-scanner-candidates-20261123`; no merge to `main`.
- A documentation-only checkpoint commit follows the validated implementation commit; use the branch ref for the current metadata-only HEAD.
- GitHub Actions at checkpoint: no queued/running workflows. No workflow was cancelled in this run.

## Changes in the validated implementation
- Clarified `natBuildFullPortInventory`: its default is the complete connectable range 1..65535; port 0 remains available only when a caller explicitly requests `firstPort: 0`.
- Corrected the stale test to expect 65,535 default ports and no port 0; the explicit zero-based test still verifies all 65,536 numeric values when requested.
- No production scan behavior, IP Clean source, IP range, port inventory, UDP inventory, or scan capability was deleted or narrowed by this correction.

## Validation evidence
- Previous exact HEAD `5e3b34e85202ca10b1f8af48e9e7984a5bede028`, CI run 2552 failed only because a stale test expected the default inventory to include reserved TCP port 0 (147 passed, 1 failed). Source-repair guards passed; analyze/build were skipped: https://github.com/cafeeteriaa/King-vpn/actions/runs/45353042246
- Corrected exact HEAD `6dcd53edfad08e19b0ff79290a70e71d041f232f`, CI run 2553 completed `success`: https://github.com/cafeeteriaa/King-vpn/actions/runs/45354384055
- Source-repair guard: passed.
- Flutter unit tests: 148 passed.
- `flutter analyze --no-fatal-warnings --no-fatal-infos`: exit 0. It reported 248 info/warning-level lint findings; they were not fatal under the workflow flags and remain technical-debt items.
- ARM64 release APK build: passed on the exact validated HEAD.
- APK artifact: `king-vpn-arm64-release-2553`, artifact ID `14902276138`, archive size 49,055,073 bytes, GitHub SHA-256 `31df95ff43b32741c6ec91c6318d3157449cce31f08bd1ee130033b2a4eb14ea`.
- Downloaded ZIP SHA-256 matched GitHub metadata. It contains exactly `app-arm64-v8a-release.apk`, 122,951,294 bytes; extracted APK SHA-256 `98254694072adbde178f1dee91657a64159316fe86a50a77f7c31338aa6bae95`.
- Independent APK inspection: 19 ARM64 native libraries; 58 ELF LOAD segments; minimum alignment 16,384 bytes; all stored native-library data offsets are 16 KiB aligned.
- The workflow uses a generated Flutter debug key, not the production signing key. No physical-device, competing-VPN, Iranian carrier, live DNS packet-capture, or real-world IPv4/IPv6 data-plane test was performed.

## Open limitations and risks
- The default full TCP-connect inventory is 1..65535. Port 0 is reserved and not a valid TCP connect destination; the generic helper still supports an explicit `firstPort: 0` request. UDP active validation remains protocol-specific.
- Full TCP port inventory runs incrementally with resumable range/port cursors; it is not an instantaneous sweep. Broad active testing remains scoped to explicit IP Clean ranges; exact configured server IPs use ports declared in their server records.
- This branch is intentionally not merged wholesale with `audit/final-master`: the branches are heavily diverged (352 commits ahead / 505 behind at the last comparison, common base `c43d325f9803d4f6306415e511f6790deff9d87e`). Port only independently verified fixes; do not perform a broad merge.
- In this branch, `tunUp()` still relies on generic interface-name detection and `MainActivity.kt` does not expose service-owned tunnel state plus Android VPN owner-UID verification. A competing VPN may therefore create a false-positive interface signal. Do not reuse plugin-daemon liveness as proof of the custom `KingVpnService` TUN.
- DNS route/leak verification, native service stop/start ordering, failover races, Android VPN ownership/handover, IPv6 data-plane validation, and CPU/battery profiling remain open.
- No Android device or Iranian carrier is available to this CI run; a green build is not evidence of live connectivity in Iran.

## First next action
1. Add a small, testable native proof for the custom `KingVpnService` TUN (established descriptor + active core/service state) and a separate Android active-network `TRANSPORT_VPN` owner-UID check on Android 11+. Make definitive negative ownership fail closed; retain a clearly labeled compatibility fallback only where the platform cannot expose ownership.
2. Wire `tunUp()` to require both service-owned tunnel evidence and the matching active VPN network before accepting a tunnel; add source guards and tests for a competing VPN, stop/revoke, and missing native evidence.
3. Then audit DNS resolver routing through the TUN/core and test failover/network handover; do not claim device-level success without device evidence.
