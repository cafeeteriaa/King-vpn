# KING Net Melli — 13 Internal Engine Architecture

This document is the canonical, version-controlled reference for the 13 internal
Net Melli subsystem engines discovered during the 11 architecture review rounds.
These are **not external VPN protocol cores**. They coordinate and implement the
Net Melli diagnosis, discovery, scanning, compatibility, configuration, DPI,
validation, recovery, learning, and resource lifecycle.

## Canonical engine list

| # | Engine ID | Engine name | Responsibility |
|---:|---|---|---|
| 1 | `connection_orchestrator` | Connection Orchestrator | Owns the ordered Net Melli pipeline, cancellation, continuation, and recovery decisions. |
| 2 | `network_intelligence` | Network Intelligence | Classifies domestic/global/unknown reachability from independent TLS, DNS, IPv4, and IPv6 evidence with confidence. |
| 3 | `discovery` | Discovery | Maintains source-attributed Iranian IP/ASN/BGP inventory and discovers DNS, domains, and endpoints. |
| 4 | `scanner` | Scanner | Coordinates DNS, domain, IPv4/IPv6 endpoint, TCP-port, SNI, ALPN, and future UDP/CDN scan adapters. |
| 5 | `compatibility` | Compatibility | Evaluates whether a transport/configuration and transformation are applicable to the detected network/operator and endpoint. |
| 6 | `real_traffic_validator` | Real Traffic Validator | Accepts success only from requests that traverse the active core/TUN; DNS, ping, TLS handshake, and structural config checks are not tunnel proof. |
| 7 | `config_intelligence` | Config Intelligence | Compiles and ranks valid configuration variants while preserving the original configuration as the baseline. |
| 8 | `network_identity` | Network Identity | Tracks physical network type, carrier/ISP and ASN identity without treating VPN interfaces as the physical network. |
| 9 | `dpi_traffic_transformation` | DPI & Traffic Transformation | Selects only transformations supported by the active runtime and records evidence; research-only packet forgery is never reported as implemented. |
| 10 | `capability_orchestrator` | Capability Orchestrator | Resolves capability availability, dependencies, compatibility, and fallback choices. |
| 11 | `multi_engine_connector` | Multi-Engine Connector | Connects internal diagnosis, discovery, DNS, IP, SNI/ALPN and validation adapters under one scheduler/lease. It does not imply additional VPN cores are installed. |
| 12 | `ai_repair_optimization` | AI Repair & Optimization | Uses failure/success evidence to rank repairs and strategy variants; model-driven autonomous repair remains a separate capability until wired and tested. |
| 13 | `resource_health_manager` | Resource & Health Manager | Adapts workers and batch sizes, enforces slice budgets, controls RAM/CPU pressure, persists cursors, and yields safely. |

## Execution order

1. Connection Orchestrator starts one scan flight and acquires the shared scanner lease.
2. Network Intelligence and Network Identity collect independent route and operator evidence.
3. Discovery refreshes source-attributed Iranian IPv4 and IPv6 prefix inventory, preserving last-known-good data on failure.
4. Scanner runs DNS, domain, IP/port, and SNI/ALPN phases serially with durable cursors.
5. Compatibility and Capability Orchestrator evaluate applicable transformations and supported configuration variants.
6. Config Intelligence compiles/ranks variants. DPI & Traffic Transformation may only claim runtime support when an actual adapter exists.
7. Multi-Engine Connector shares the lease and evidence between internal scanners and probes.
8. Real Traffic Validator confirms the selected route only after a real request through the active core/TUN.
9. AI Repair & Optimization uses verified outcomes; Resource & Health Manager controls continuation and recovery.

## Evidence and status rules

- The network fingerprint is a SHA-256 digest used only to detect a physical-network change. It is not a carrier/ASN identifier. The operator token is collected separately by the interface/ASN detector, sanitized before diagnostics, and may remain unknown when the current network cannot reach public ASN sources.
- Operator network type is derived from the physical interface(s) owning the IPv4/IPv6 default route, not from every interface that is merely connected. Concurrent Wi-Fi and cellular default routes are labeled mixed; missing route evidence stays unknown rather than guessing.
- Adaptive configuration/compatibility learning is partitioned by access-network class and ASN as well as protocol, transport, security, port, and hashed host. Existing pre-partition learning remains a read-only fallback; new results are stored under the operator-aware key so historical evidence is not discarded.

- A phase completing means that phase's own work completed; it does not prove a VPN tunnel works.
- A full IP inventory pass is complete only when all configured cursor-backed IPv4 resources have been traversed. A yielded slice remains resumable and is not reported as complete.
- IPv6 prefixes are inventoried as prefixes. Broad IPv6 address spaces are not exhaustively enumerated; endpoint discovery and targeted validation are used.
- A configuration that parses or generates successfully is structurally validated, not traffic-validated.
- SNI/ALPN handshakes do not prove end-to-end tunnel traffic.
- The Real Traffic Validator only records success after a real request through the active core/TUN.
- Unsupported fake TCP/TLS/HTTP packet construction, raw packet injection, UDP forgery, and other research-only techniques remain explicitly unimplemented unless a safe, supported native adapter is implemented and tested.
- Resource controls bound concurrent work and memory per batch; they do not impose an artificial total-result ceiling. Discovery remains resumable and cursor-driven.

## Current implementation boundary

The runtime coordinator is in `lib/king_national_scanner.dart` as
`KingNatSubsystemEngine`. It exposes all 13 engine states and connects them to
the current scanner phases, route evidence, operator identity, configuration
planning, resource budgets, and actual tunnel-traffic checks in `lib/main.dart`.

This registry and lifecycle integration is not a claim that every planned
sub-capability is complete. UDP discovery, comprehensive CDN/DPI adapters,
raw packet transformations, broad IPv6 enumeration, and full autonomous AI
repair require their own compatible implementations and evidence. Keep these
states partial/deferred until the implementation and tests exist.

## Tunnel validation evidence contract

- A successful request to one destination is recorded as connectivity probe evidence only.
- The validator becomes `completed` only after the stable-check path reports at least two successful destinations through the active core/TUN.
- The Connection Orchestrator cannot become `completed` from finishing the preflight scan; it waits for stable multi-destination tunnel proof.
- The Multi-Engine Connector additionally requires every durable scan phase, the complete IP inventory pass, restored phase-adapter edges, and stable tunnel proof. A successful individual adapter or a caller-provided aggregate boolean is insufficient.
- Failed stable checks and stable checks with fewer than two destinations remain non-complete.
- Diagnostics expose probe totals separately from stable pass/failure totals; route classification, DNS, SNI/ALPN, and config parsing cannot promote tunnel validation.

## Permanent acceptance criteria

- Preserve the 13 engine IDs and responsibilities above.
- Do not replace these internal engines with the external VPN core catalog.
- Keep one central scanner scheduler; do not create competing parallel scanners.
- Maintain durable cursor, deduplication, cancellation, and last-known-good inventory.
- Require end-to-end traffic evidence before marking a route/config healthy.
- Review architecture, security/resource behavior, and regression/tests independently.

## Runtime completion and adaptive resource contract (2026-11-28)

- Completing DNS, domain, IP, or SNI work in one invocation records phase-local evidence only. The Scanner engine remains partial/deferred until the complete required phase set has run and the durable IP inventory pass is complete.
- Discovery remains partial/deferred while any configured range cursor is pending. A non-empty prefix inventory is not equivalent to a completed traversal.
- recordResourceBudget is a diagnostics boundary, not a policy layer: it preserves the scheduler's positive worker, slice-duration, and port-batch values without applying secondary fixed ceilings. Resource policy is calculated by the adaptive scheduler from device capacity.
- Endpoint probe concurrency reuses natAdaptiveConcurrency; the prior independent 32-connection clamp has been removed.
- Address-wave sizing is derived from adaptive workers and the measured slice/port budget. The prior fixed 768-address wave ceiling has been removed; each wave still yields to cancellation and the durable range cursor.
- These changes remove duplicate hard ceilings, not resource safety. CPU-aware concurrency, bounded execution slices, cancellation, and resumable cursor traversal remain in force.
- Regression tests cover budgets above the former coordinator ceilings and prevent a single completed phase or non-empty inventory from falsely completing Discovery/Scanner.

## Dual-stack DNS evidence (2026-11-28)

- Resolver discovery now issues independent A (QTYPE 1) and AAAA (QTYPE 28) queries for each tested domain. Both use the same strict transaction-ID, QR/opcode, question, source-address/port, RCODE, answer-owner and CNAME-chain validation.
- A answers must be globally routable IPv4 addresses; AAAA answers must be globally routable IPv6 unicast addresses. Unspecified, loopback, link-local, unique-local, multicast, documentation and IPv4-mapped IPv6 ranges are rejected.
- DNS resolver scoring counts each domain once when either family returns a usable address, and reports IPv4 and IPv6 success counts separately. An IPv4-only resolver is therefore not falsely penalized for a domain without AAAA records.
- The per-resolver domain batch is reduced from eight to four because each domain now opens two concurrent family probes. This preserves approximately the former socket fan-out instead of doubling resource pressure.
- DNS success remains resolver evidence only; it is never promoted to proof of a working domestic/global data path or a validated VPN tunnel.
- Resolver transport itself now accepts both IPv4 and IPv6 literal addresses, binds the matching socket family, and verifies the response source by address bytes plus UDP/53 rather than string formatting. Global mode includes well-known public IPv6 resolver endpoints; national mode does not silently substitute those global resolvers for domestic ones. Manual DNS input accepts either address family.
- IPv6 DNS answers are accepted only from the global-unicast allocation 2000::/3; special-use protocol assignments, transition/translation, documentation and other non-global ranges are rejected. DNS name compression pointers must reference a prior in-packet offset; malformed forward or out-of-range pointers are rejected rather than being interpreted as truncated names.
- A yielded scan slice keeps discovery and scanner state `deferred` with its durable cursor, not `partial`; the distinction is covered by the coordinator regression test.
