# KING VPN Revision Ledger

Current revision: 61
Next revision: 62
Repository: cafeeteriaa/King-vpn
Revision branch: fix/revision-58-network-identity-fragmentation-20261126
Revision PR: https://github.com/cafeeteriaa/King-vpn/pull/58

## Revision history

### 57 — Transactional fresh-resource storage
- Pull request: https://github.com/cafeeteriaa/King-vpn/pull/57
- Removed fixed entry and URL-length ceilings from the fresh-resource store.
- Serialized concurrent mutations and made snapshot replacement recoverable.
- Verification: GitHub Actions run 45747970274 passed source guards, unit tests, Dart analysis and Android arm64 release APK build.

### 58 — Network discovery, identity validation, fragmentation and inventory separation
- Pull request: https://github.com/cafeeteriaa/King-vpn/pull/58
- Restored the complete NPV helper module after the source-repair pass; verified that existing function inventory remains intact apart from the intentionally removed trimming helpers.
- Removed the 100,000-IP and 20,000-server Gold inventory ceilings, UI truncation and destructive deletion of historical IP/server records after a failed retest.
- Moved Gold IP/server/DNS state to serialized atomic file snapshots with temporary-file replacement, backup recovery and a serialized write queue.
- Removed the clean-IP result-count and total-time stops. Cloudflare IP verification now requires a validated TLS session for cloudflare.com, HTTP 200, Cloudflare server and cf-ray headers, and expected trace fields; plain HTTP/80 is not accepted as identity proof.
- Global and National Net IP/domain histories, DNS resolver inventories, range cursors and template inventories are stored and selected independently. National discovery no longer imports global Gold IPs, DNS resolvers or global hot-source templates.
- Added BigInt-backed cursor traversal for explicit IPv6 CIDRs and address ranges while preserving IPv4 traversal. The isolate returns exactly the batch whose addresses are probed; partial hits survive cancellation and incomplete cursors are not committed. DNS resolver probes now accept IPv4 and IPv6 resolver addresses.
- Removed the affected per-source, manual hit-count, server-count, queue-size and scan-deadline stops. Per-batch concurrency and background pacing remain explicit resource-safety controls, not total inventory ceilings.
- TLS/SNI checks use certificate validation. DNS target domains are built dynamically from the complete static project inventory plus hostnames and SNI values from active/global/National Net profile templates; the SNI scanner consumes that live domain inventory in cancellable adaptive batches.
- Fragmentation is no longer silently disabled by global, pilot, turbo or personal connection paths. One app-owned frag outbound is wired to every TLS/REALITY proxy outbound; stale references are removed when the user disables the setting.
- Added tests for IPv4/IPv6 cursor batches, Cloudflare trace identity validation, multiple TLS outbounds and fragment cleanup.
- Restored previously retired Fragment/Android fingerprint variants, removed the generated DPI matrix and learning/cursor map ceilings, and enabled fragmentation by default for fresh installs.
- Removed the Gold daily probe quota, the eight-hour National Net loop stop and ASN prefetch count truncation. The independent Pilot scanner now accepts IPv4/IPv6 CIDRs and address ranges and resumes from persisted cursors instead of stopping after 256 addresses.
- Replaced random 28-IP-per-CIDR Cloudflare sampling with persistent per-range cursors, so the clean-IP scanner traverses each published IPv4 range in resumable batches without a daily quota.
- Reused saved endpoint ports and domain hostnames from the active discovery mode only; DNS and SNI inventories now include the matching persisted host/domain history and matching profile-template inventory.
- Increased the healthy-server folder capacity from 5,000 to 50,000, migrated its snapshot from SharedPreferences to an app-private atomic JSON file, and made its 48-hour recheck independent of National Net mode while retaining network-outage protection.

### 59 — Append-only, streaming KING AI research memory
- Removed the production dependency on the 500-entry in-memory merge/truncation path. Research notes are now validated and appended to JSONL storage; the on-disk history has no total-record ceiling.
- Added serialized appends so concurrent foreground/background research writers cannot interleave records.
- Replaced whole-file `readAsLines()` retrieval with incremental file streaming. Ranking retains only the best matching unique URLs in memory, so RAM use depends on requested context size rather than total research-history size.
- Preserved trusted-HTTPS source validation, malformed-row rejection, 180-day relevance freshness, and the separation between private conversation memory and public technical research.
- Added Dart tests for 750+ stored rows, duplicate URL refresh, malformed records and untrusted domains, plus Python source guards for append-only/streaming production paths.
- Pull request: https://github.com/cafeeteriaa/King-vpn/pull/58
- Verification: pending CI for this revision; no Dart/Android success is claimed until the workflow completes.

### 60 — Persistent KING HEAL learning and verified-outcome feedback
- Replaced process-only heal action counters with an append-only JSONL event journal in the app support directory. Historical outcomes survive app restarts and have no total-entry ceiling.
- Journal replay is incremental; malformed/torn rows are skipped without discarding later valid records. Writes are serialized in-process and coordinated with an exclusive OS file lock.
- The learning loop now records the verified repair result after the data-plane check, rather than trusting an action's early return value (which could say CONNECTED while tunneled traffic is still broken).
- Removed the unused in-memory recent-event list so journal growth does not create a second unbounded RAM history.
- Added Python source-guard tests for persistence, streaming replay, lock usage, restore-before-planning, and verified-outcome ordering.
- Journal rows are checked against the finite action vocabulary of the heal engine before they can influence planner scores; arbitrary or tampered action names are ignored.
- Verification: CI pending for this commit; no Dart/Android success is claimed before the workflow completes.

### 61 — Context-aware KING HEAL decision engine
- Expanded persistent learning from global per-action counters to symptom-context × action outcomes. The context key is the sorted set of active diagnostic signals, so the same repair can learn separately for core-drop, no-healthy, no-data and other incident patterns.
- Added Laplace-smoothed success estimates with evidence weighting; one lucky result cannot dominate, and context evidence gains influence as observations accumulate.
- Integrated learned selection into the no-healthy/blacklist and core-drop paths, while retaining deterministic high-priority safety handling for stuck abort and missing TUN.
- Removed arbitrary 70% bulk deletion of failed servers and the unrelated fixed >60 trigger. Recovery now releases only entries whose recorded cooldown has actually expired; recent failure evidence is preserved.
- Removed a stale UI reference to the deleted in-memory recent-event list and display aggregate durable win/loss counts instead.
- Added source guards for context persistence, planner integration and non-destructive failure-history handling.
- Verification: source changes are committed; Dart/Android CI result is not yet available and is not claimed.

## Mandatory three-pass review protocol

Each numbered revision must be a substantial functional change and pass three separate reviews:
1. Architecture and behavior: feature preservation, global/National Net isolation, complete inventory traversal and no hidden truncation.
2. Persistence and concurrency: atomic/serialized writes, cursor commit rules, cancellation, partial-result retention and recovery.
3. Compatibility and verification: source guards, unit tests, static analysis, Android build and final diff review.

### Revision 58 review status
1. Architecture and behavior: completed; function inventory and mode-specific discovery paths reviewed.
2. Persistence and concurrency: completed; atomic snapshots, append-only histories, cursor commit and cancellation paths reviewed.
3. Compatibility and verification: completed on commit `e21d3416bb21f4ccb60dfff182526c45e74f156d`; GitHub Actions run #3711 passed source guards (230 Python tests), Flutter tests (132), Dart analysis, and optimized Android arm64 release APK build. Analyze emitted non-fatal deprecation/info findings that remain recorded in `docs/IMPLEMENTATION_STATUS_FA.md`.
- APK: 122,885,886 bytes (117.19 MiB).
- SHA-256: `0cc18d4b3f9780b35f083df1a1eebfba3213a1e5895958b18a5145315fdd5cb3`.
- CI verification does not replace real-device VPN connection and carrier testing.

## Explicit safety boundaries

- No fixed total inventory ceiling is applied to stored resources or completed discoveries.
- Per-call scan batches, adaptive concurrency and background pacing are retained to protect device/network stability; cursors continue across batches.
- Explicit user-supplied IPv4/IPv6 CIDRs and address ranges are expanded through resumable cursor batches; the scanner does not materialize the entire address space in memory at once.
- Batch size, worker concurrency and background pacing remain resource controls. They do not impose a total address, result, or daily-probe ceiling.

## Numbering rule

Increment the revision number by exactly one for each substantial edit set. Record the new number and its PR in this file. Do not change the revision number for routine CI reruns or review-only corrections within the same revision.
