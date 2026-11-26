# KING AutoSwitch and Psiphon integration

## Goal
Keep the existing Xray/V2Ray connection as the primary engine. If end-to-end
tunnel traffic fails, release its Android VPN ownership before trying Psiphon.
Keep each adapter lifecycle independent so a fallback cannot mutate Xray
configuration, server inventory, or the existing failover behavior.

## Confirmed Psiphon SDK facts
The official Psiphon Android MobileLibrary provides an embeddable Android
library and a PsiphonTunnel.HostService API. It reports asynchronous events
such as onConnecting/onConnected and local SOCKS/HTTP proxy listening ports.
Its official sample demonstrates routing a WebView through the local HTTP
proxy.

The public SDK interface does not expose a list of all internal Psiphon relay
endpoints for independent enumeration. Psiphon selects and manages its own
relay paths. KING must not invent a fake list of 20/30 Psiphon proxies.
Use the SDK's own connection/retry lifecycle plus end-to-end traffic tests.
Adaptive 20/30-item batches apply only to adapters that truly expose
independent probeable endpoints.

## Android VPN ownership
Android has one active VPN service slot per user/profile. Xray and Psiphon
must not run as competing full-device VPN services. The coordinator therefore
stops/releases the active engine before starting the next.

The Psiphon MobileLibrary sample proves local-proxy integration, not complete
device-wide routing. A full-device Psiphon adapter still needs a supported
TUN-to-proxy data path and explicit VPN lifecycle/consent handling. Do not
mark Psiphon as a full-device fallback until this is implemented and tested.
The existing KING source uses flutter_v2ray_client as its active tunnel path;
the custom kOwnVpnService flag is currently disabled. Do not flip it or
replace the plugin without a separate migration and device regression test.

## Coordinator contract
- Explicit priority: Xray first, Psiphon second.
- One adapter owns Android VPN at a time.
- CONNECTED is insufficient; require end-to-end traffic verification.
- On failure, release the previous adapter before starting the next.
- A user disconnect cancels pending transitions.
- Preserve existing Xray core, config store, source lists, and failover.
- Keep engine health separate from Xray server health.

## Adaptive batches
KingAdaptiveBatchRunner processes the complete iterable without truncating
inventory. It starts with 20 and accepts a next-batch decision based on runtime
measurements. The caller can increase to 30 or higher when CPU, memory,
latency, and network headroom permit, or decrease when resources are stressed.
It imposes no total inventory cap.

Do not wire this runner to Psiphon's private relay pool: the SDK manages that
pool internally and does not expose it as a public enumeration API. For
Psiphon, measure tunnel startup, proxy readiness, data-plane success,
reconnect time, and sustained throughput instead.

## Remaining implementation gates
1. Pin an exact Psiphon SDK version and verify artifact integrity/license.
2. Implement a lifecycle-safe Android host around PsiphonTunnel.
3. Implement complete-device TUN-to-Psiphon-proxy routing, not WebView-only.
4. Handle VPN consent/revocation, network changes, process death, stop timeout,
   and stale callbacks.
5. Wire the coordinator into the current _start/_failover path only after
   the complete-device Psiphon path passes Android instrumentation tests.
6. Run Flutter tests/analyze, Android release build, and real-device tests on
   multiple Android versions and restricted networks.

## Official upstream references
- https://github.com/Psiphon-Labs/psiphon-tunnel-core/tree/master/MobileLibrary/Android
- https://github.com/Psiphon-Labs/psiphon-tunnel-core/tree/master/MobileLibrary/Android/SampleApps/TunneledWebView
- Latest SDK release observed during research: 2.0.43.
