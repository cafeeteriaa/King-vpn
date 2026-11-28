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

## Permanent acceptance criteria

- Preserve the 13 engine IDs and responsibilities above.
- Do not replace these internal engines with the external VPN core catalog.
- Keep one central scanner scheduler; do not create competing parallel scanners.
- Maintain durable cursor, deduplication, cancellation, and last-known-good inventory.
- Require end-to-end traffic evidence before marking a route/config healthy.
- Review architecture, security/resource behavior, and regression/tests independently.
