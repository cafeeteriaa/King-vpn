# MASTER GOLDEN LAW — KING VPN
## Universal discovery, scanning and real tunnel traffic validation

This policy governs discovery and evaluation for IP, DNS, SNI, DPI, ports, Host and Domain candidates in KING VPN.

## 0. Exclusive KING VPN purpose

Every discovery result, endpoint, protocol hint, port, DNS answer, SNI/Host value, DPI strategy and transport candidate exists solely to establish, maintain, recover or verify connectivity for the KING VPN application. Scanner traffic and candidate data must not be exposed as a general-purpose port scanner, proxy service, relay service, traffic generator, vulnerability scanner or unrelated network utility. Do not add a second-purpose consumer for these results.

A candidate may be used only as an input to the KING VPN connection workflow. Endpoint reachability is preliminary evidence; only the central real-core + Android TUN + actual in-tunnel application-response gate can promote it to a usable VPN route. Stop or pause discovery when it would interfere with an active/starting VPN session, and do not route unrelated application traffic through discovered endpoints outside the VPN tunnel.

The discovery inventory is source-neutral: do not discard candidates because they are unfamiliar, absent from saved configs, non-Cloudflare, or associated with a particular ISP, country, CDN or provider. Keep discovered candidates and failures resumable. The complete TCP and UDP port-number inventories cover 1..65535 (port 0 is not a normal connect target); preferred/configured ports may affect scheduling only, not inventory membership.

## 1. Discovery inventory

Maintain a federated, continuously refreshed inventory from:
- IPv4 and IPv6 literals and DNS A/AAAA answers.
- Publicly published DNS, domain, SNI, Host and relay catalogs.
- Hosts and ports explicitly present in configured VPN server records.
- Announced/published network ranges and project-maintained sources.
- DPI/transport strategies and native engines, with honest implementation status.

The theoretical address spaces (all IPv4 and IPv6 addresses) are not finite practical scan jobs; continuously discover from federated sources and resolve observed domains instead of claiming exhaustive Internet enumeration. The TCP and UDP port inventories each contain every connect port from 1 through 65535. Keep inventory generation separate from active probing: inventory completeness does not authorize indiscriminate probes against unrelated public hosts. Use resumable cursors, bounded batches, deduplication and fair rotation so known sources are not starved.

## 2. No label-based exclusion

Do not reject a candidate solely because of country, ISP, operator, provider, ownership category, technology label, or domestic/global classification. These labels may be recorded as metadata but are not evidence of reachability or quality.

## 3. Authorized active testing

Passive discovery and public metadata collection may be broad and source-neutral. Active tests are strictly VPN-connectivity checks, not a general scanning feature. Run protocol-appropriate checks only for candidates within a defined, user-controlled or explicitly configured test scope; do not blindly sweep all 65535 ports across every third-party IP discovered on the Internet. Unknown ports and hosts remain in the candidate inventory and are not silently deleted merely because they are not configured yet. A candidate outside the current active-test scope stays queued for later VPN-specific evaluation when a suitable scope/configuration exists. Any reachability result remains preliminary and cannot independently make a usable route.

## 4. One acceptance contract

A candidate becomes a usable route only after:
1. The VPN core starts with that candidate's configuration.
2. The Android VPN/TUN path is active where applicable.
3. An application request is sent through the actual tunnel/core data path.
4. A real HTTP/application response is received and validated.
5. Latency, response status/bytes, throughput and repeat stability are recorded where available.

DNS resolution, ICMP/Ping, TCP connect, TLS handshake, ALPN selection, or an HTTP response made outside the candidate tunnel are discovery evidence only. They must never independently promote a candidate into the usable-route pool.

The connection path's _tunnelTrafficOk / _stableTunnelTrafficOk gates are the current application-level tunnel verification points. Keep scanner reachability results separate from verified route results.

## 5. Retry and persistence

- Preserve failed candidates as retryable observations; do not permanently blacklist on a single transient failure.
- Persist per-source cursors only after a batch completes and its results are committed.
- Resume incomplete batches without skipping candidates.
- Keep candidate, endpoint-reachability, core-outbound, tunnel-verified and stable-route states distinct.
- Record last attempt, failure class and next retry eligibility.

## 6. DPI and native engines

A strategy catalog is not a DPI engine. A native DPI/packet adaptation engine must have real Android TUN integration, lifecycle handling, protocol adapter, licensing/security review, CPU/RAM bounds and device-level tests before it can be marked executable.

Use only honest states: IMPLEMENTED, TESTED, VERIFIED, BLOCKED, NOT IMPLEMENTED.

## 7. Engineering acceptance

Do not claim full Internet-wide IPv4/IPv6 enumeration or complete global DNS/SNI/Host inventories; those are not finite, practically enumerable public lists. Maximize coverage through published sources, federated inventories, dual-stack resolution, resumable scans and repeat discovery.

A change is complete only when source-level tests and available CI/build checks pass. Clearly distinguish code written, tests run, tests passed, and device verification.

## Golden rule

**No ownership, geography, ISP, provider or technology label may by itself prevent discovery or evaluation. A candidate may enter KING VPN's usable-route pool only after real Internet traffic is proven through the actual VPN tunnel, within an authorized testing scope.**
