# MASTER GOLDEN LAW — KING VPN SCANNER ENGINE
## Manual and automatic discovery, protocol checks, and real-tunnel validation

This policy governs every KING VPN scanner and its connection workflow.

All scanner observations, endpoint checks and traffic are used solely to establish, maintain, recover or verify connectivity for the KING VPN application.

## 1. Two independent scanner modes

### Manual scanner
- Receives the IP range and port range explicitly entered by the user.
- Supports IPv4 and IPv6 input.
- Runs protocol-appropriate checks within the supplied test scope.
- Reports reachability, latency, DNS/TLS/HTTP evidence and errors separately.
- Presents results for inspection and copying, and may pass selected values to the KING VPN configuration builder.
- Does not require saved server configurations or the automatic scanner.

### Automatic scanner
- Runs without the user entering an IP range for each run.
- Discovery inventory generation must not require saved server IPs, ports, SNI values, Host values or saved configuration records.
- Maintains independent discovery state, deduplication, cursors and resumable batches.
- Supports IPv4 and IPv6 and does not exclude observations because of provider, ISP, country, CDN or brand labels.
- May use saved configurations only as protocol-format examples during connection construction, never as the prerequisite or exclusive source for discovery.
- Pauses or yields when it would interfere with an active or starting VPN session.

The manual and automatic scanners must not depend on each other's queues, cursors, UI state or result stores.

## 2. Discovery inventory

Maintain distinct observations for IP addresses, domains, DNS answers, ports, SNI/Host values, TLS/ALPN behavior, transport hints and route diagnostics. Record provenance, first/last observation, last test, evidence and retry state.

Discovery must not silently discard an observation merely because its provider, owner, geography or technology label is unknown. Metadata labels are descriptive, not proof of reachability or quality.

IPv4 and IPv6 address spaces and global DNS/SNI/Host names are not practically enumerable as finite jobs. The implementation must not claim complete Internet-wide enumeration. Use independently maintained discovery mechanisms, bounded work, deduplication and resumable state. The TCP and UDP port-number inventories cover the complete numeric interval 1..65535 (ports 1 through 65535); port zero is not a normal connect target.

## 3. Active testing boundary

The scanner feature must not be exposed as a general-purpose port scanner. Keep inventory generation separate from active probing; KING VPN connectivity workflows are the only product purpose.

Keep discovery inventory separate from active network testing. Active checks must be protocol-appropriate, rate-controlled and confined to user-controlled or explicitly authorized test scope. Do not turn broad passive discovery into indiscriminate active port sweeps against arbitrary third-party public addresses.

This boundary must not be implemented by making discovery dependent on _goldSrv, saved configurations, a fixed provider list or a Cloudflare-only source. Unknown or not-yet-tested observations must remain distinguishable from failed observations; they must not be represented as verified healthy endpoints.

## 4. Scanner responsibilities

- IP/NAT: dual-stack parsing, range handling, address classification, route evidence and deduplication.
- TCP/Port: complete port-number inventory, bounded protocol-aware checks and distinct Open/Closed/Timeout/Error states.
- UDP: complete port-number inventory and protocol-specific validation; silence alone is not proof of closure or success.
- DNS: A/AAAA, resolver comparison, timeout/error classification and answer provenance.
- SNI/Host: protocol-compatible TLS/HTTP checks with exact evidence; a successful handshake is not a tunnel.
- TLS/ALPN: negotiated protocol, certificate/handshake evidence and errors.
- DPI/transport diagnostics: identify observable interference symptoms; a strategy catalog is not a native DPI engine.

## 5. Connection construction

Scanner observations may be combined with a protocol template to construct a KING VPN connection attempt. The saved configuration may supply protocol structure only; it must not define the discovery universe.

Only parameters supported by the selected core/protocol may be varied: IP, port, DNS/resolve method, SNI, Host, TLS, ALPN, transport and protocol-specific connection parameters. Do not emit malformed or unsupported combinations.

## 6. Real tunnel acceptance

An endpoint observation is not a verified VPN route. A route may be accepted only when:
1. The actual supported VPN core starts with the generated configuration.
2. The Android VPN/TUN path is active where applicable.
3. A real application request traverses that core/TUN path.
4. A valid application response is received and checked.
5. Stability evidence is collected where available.

Ping, DNS resolution, TCP connect, TLS handshake, ALPN selection or direct HTTP outside the tunnel must never independently mark a route healthy.

Keep endpoint reachability, core-start, TUN-active, in-tunnel-response and stable-route states separate. Only the central real-tunnel acceptance gate may promote a route into the usable connection pool.

## 7. Automatic replacement and retry

- A successfully verified route may be stored and made available to KING VPN's automatic connection selection.
- Failed or transient observations must be classified accurately; a timeout is not automatically a permanent failure.
- Preserve retry state and resume incomplete batches.
- Remove a route from the healthy pool when it fails the applicable real-tunnel health gate.
- Never interrupt the user's active connection merely to run background scans.

## 8. Resource management

Bound CPU, memory, battery use, socket count and concurrency. Use independent queues, cancellation, persisted cursors, deduplication and backoff. Prevent conflicting scanners from running simultaneously. Pause or yield when the VPN is active or starting if scanning could distort results or impair the tunnel.

## 9. DPI and native engines

A strategy list or diagnostic heuristic is not a DPI engine. Native packet/TUN adaptation requires actual Android integration, lifecycle handling, protocol adapter implementation, licensing/security review, resource bounds and device-level tests before it may be described as implemented.

## 10. Engineering status and tests

Use honest statuses:
- IMPLEMENTED
- TESTED
- PARTIAL
- NOT_IMPLEMENTED

Test manual/automatic independence, absence of saved-config prerequisites in discovery, dual-stack handling, complete port inventory, protocol-specific UDP behavior, DNS/SNI/TLS evidence, deduplication, resumability, VPN-session collision prevention and the real TUN traffic gate.

A CI pass proves only the checks that actually ran. It does not prove device-level behavior unless device tests ran.

### Implementation checkpoint — 2026-11-24
- Automatic SNI/IP candidate inventories are now generated from project-owned domain catalogs, DNS A/AAAA answers and CDN range inventory, and persisted under separate `sni_candidates` / `ip_candidates` result groups.
- Candidate inventories are saved and displayed even when no saved VPN server exists. They are explicitly unverified and are not promoted into healthy IP/server pools.
- Active SNI/TLS/ALPN checks now resolve each inventory domain independently and test its own DNS A/AAAA answers on TCP/443; saved VPN configurations are not required for those checks.
- Passive DNS inventory retains all valid IPv4/IPv6 observations, including private, link-local and ULA addresses; address scope is metadata, not a discovery filter.
- Automatic full TCP port checks remain bound to exact saved KING VPN endpoint IPs. User-supplied explicit ranges continue through the manual/range scanner. Do not turn passive global DNS/CDN observations into indiscriminate 1..65535 public-address sweeps.
- Active probe results remain reachability evidence only and are never promoted to verified VPN routes without a real core/TUN traffic test.
- CI run 2562 passed source guards, Flutter tests, Dart analysis and ARM64 release build. The subsequent candidate-inventory change is awaiting exact-HEAD CI; no device-level verification is claimed.

## Golden rule

**Manual scanning uses the range entered by the user. Automatic discovery runs independently of saved configurations. Neither mode may confuse endpoint reachability with real VPN tunnel traffic. Only verified in-tunnel application traffic can establish a healthy KING VPN route.**


## 2026-11-24 — National-mode candidate source separation

- Automatic scanner candidate discovery now uses a dedicated Iranian-service domain seed catalog while national mode is active.
- Global domain catalogs, front-SNI/relay seeds, live Cloudflare/CDN ranges, and hard-coded global fallback IPs are excluded from national-mode candidate inventory; these remain available in global mode.
- Saved VPN endpoint hosts remain included as project-specific candidates. Active endpoint validation scope and all user-configured IP/range scanning behavior are unchanged.
- This is a source-selection correction, not proof that any Iranian service IP is reachable during a national-network outage. Real reachability still requires tests from an actual Iranian carrier/network and final core/TUN traffic verification.
