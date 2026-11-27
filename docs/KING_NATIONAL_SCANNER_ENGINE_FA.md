# KING VPN — National Net scanner pipeline

## Scope

This pipeline is only for the app's explicitly selected National Net mode. It
does not reuse or mutate the global scanner's cursors, DNS cache, or IP
inventory. The global idle path remains on `KingScanScheduler` and
`ipAutoBackground`'s existing mode gate.

## Runtime order

1. **Network diagnosis** — `NatNetworkDiagnosis.refresh()` records domestic
   and global reachability evidence before national DNS selection.
2. **DNS discovery** — `dnsxAutoPick` tests the national resolver set against
   the existing national domain inventory and writes to national-only state.
3. **Configured endpoint discovery** — `_natDomainFirst` resolves and probes
   only endpoints present in the supplied national config/template inventory
   and national endpoint memory. It does not expand a hostname into an
   unrelated subnet or invent ports.
4. **Configured range discovery** — `natRangeScanStep` advances the isolated
   national range cursors. The existing Rust FFI range expander is used only
   after ABI and Dart/Rust parity validation; Dart remains the fallback.
5. **Existing exact-IP/core verification** — after discovery, the previous
   background verifier still runs on its existing retry interval, uses the
   existing VPN core, and persists its own results/cursors.

## Coordination and correctness

- `KingNationalScannerEngine` is a single-flight coordinator. Concurrent timer
  requests coalesce into one sequential follow-up cycle; scanner phases never
  run concurrently through this coordinator.
- The mode is captured and rechecked at every phase boundary. A user stop,
  connection request, mode switch, or app-state change cancels later phases.
- Each phase reports completed, failed, cancelled, or skipped; a thrown probe
  does not become a successful scan result.
- DNS, endpoint and range implementations remain in their existing modules.
  The coordinator does not duplicate socket, DNS-wire, range-expansion, or
  persistent-store implementations.
- Individually verified endpoint hits are retained when the mode is still
  national, even if a later phase is cancelled. An incomplete range batch does
  not advance its cursor, so its remaining work is retried safely.
- The pre-existing connect ladder remains responsible for config compatibility,
  the curated DPI/transport strategy matrix, core startup, end-to-end tunnel
  traffic validation, failover, and self-healing. A TCP-open or DNS answer is
  never treated as proof of a working VPN tunnel.

## Language boundaries

- **Dart:** phase coordination, cancellation, scanner integration, cursor and
  inventory ownership, config compatibility and connection orchestration.
- **Rust:** optional IPv4/IPv6 range-batch expansion through the existing
  versioned FFI. It does not open sockets or make connection-success claims.
- **Kotlin/Android:** existing VPNService/core lifecycle and platform bridge.
  This scanner revision does not alter native VPN permissions or service APIs.

## Validation status

Unit and source-guard tests are added for ordering, mode isolation, cancellation,
failure reporting, and overlapping-cycle coalescing. CI/build status must be
read from the exact pull-request head; source changes alone are not a build
result.
