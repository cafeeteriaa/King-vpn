# KING VPN Revision Ledger

Current revision: 62
Next revision: 63
Repository: cafeeteriaa/King-vpn
Revision branch: fix/personal-folder-uncapped-20261127
Parent revision branch: fix/healthy-folder-unbounded-retention-20261127
Revision PR: https://github.com/cafeeteriaa/King-vpn/pull/65
Consolidated integration PR: https://github.com/cafeeteriaa/King-vpn/pull/66

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

### Revision 59 — preserve small healthy-server inventories during outages
- Fixed a destructive edge case in `_resDaily`: the prior all-failed guard required at least five tested endpoints. With only one to four due entries, if every first and second-chance probe failed, the network-outage guard did not activate and the entries could be removed from the healthy folder.
- The guard now preserves the inventory whenever at least one probe completed and no endpoint succeeded (`tested > 0 && passed == 0`). This is a fail-safe rule: without any positive reachability evidence, the app does not infer that every saved endpoint is dead.
- Individual failed entries remain eligible for removal after the second chance only when the same maintenance round has at least one successful endpoint, providing positive evidence that the network is reachable.
- Added a regression source guard for the one-to-four-entry case.
- No IP Clean sources, CIDRs, address ranges, ports, scan cursors, or scan capabilities were changed.
- Exact-head CI is pending; no device-level outage test has yet been run.

### Revision 60 — remove destructive healthy-folder count eviction
- Removed the fixed 50,000-entry ceiling and oldest-entry eviction from _resAdd; newly verified healthy servers are no longer discarded solely because the in-memory map reached an arbitrary count.
- Removed the obsolete capacity field from the persisted snapshot metadata.
- Preserved duplicate refresh, personal-server exclusion, atomic file snapshot replacement, and the small-inventory outage guard from Revision 59.
- Added a regression source guard proving that _resAdd no longer contains a count ceiling or oldest-entry eviction.
- Important remaining scalability work: _resMap is still an in-memory working map and the current JSON snapshot is loaded as a whole. This revision removes data loss but does not yet claim memory-bounded paging or multi-million-entry scalability. The next stage must migrate to a disk-backed indexed/paged store before such scale is claimed.
- Exact-head CI and runtime/device validation are pending.

### Revision 61 — remove personal-server folder count and selection ceilings
- Removed the fixed 1,000-entry insertion ceiling from the personal-server folder.
- Removed the fixed 100-entry display/ping/selection ceiling; personalFolderServers now returns every valid stored entry, and both the personal-folder preparation and direct-connect paths use the complete list.
- Updated Persian UI copy and added a source guard against reintroducing the old count limits.
- Personal-folder persistence still uses SharedPreferences string-list storage and an in-memory cache. This revision removes artificial count gates but does not yet claim robust very-large-inventory persistence or memory-bounded paging; a transactional file-backed migration remains a follow-up.
- Exact-head CI and device validation are pending.
- Includes the restored engine catalog/coordinator/source modules required by the repository's engine tests; catalog groundwork does not imply native engine integration.
- OpenVPN is intentionally absent from the registry, import parser and runtime catalog, consistent with the native-core policy.

### Revision 62 — serialize personal-folder mutations
- Added a shared asynchronous mutation queue for personal-folder load, add, remove and last-good writes.
- Prevents overlapping read/modify/write operations from overwriting one another in the app's shared JSON preferences store.
- Added a source guard verifying all personal-folder mutation entry points use the serialized queue.
- Persistence is still SharedPreferences-backed with an in-memory cache; transactional disk-backed paging remains follow-up work.
- Exact-head CI and runtime validation are pending.

## Mandatory three-pass review protocol

Each numbered revision must be a substantial functional change and pass three separate reviews:
1. Architecture and behavior: feature preservation, global/National Net isolation, complete inventory traversal and no hidden truncation.
2. Persistence and concurrency: atomic/serialized writes, cursor commit rules, cancellation, partial-result retention and recovery.
3. Compatibility and verification: source guards, unit tests, static analysis, Android build and final diff review.

### Revision 62 review status
1. Architecture and behavior: pending.
2. Persistence/concurrency: pending; queue semantics and error recovery require test verification.
3. Compatibility/verification: pending exact-head CI, Flutter tests, Dart analysis and Android build.

### Revision 61 review status
1. Architecture and behavior: pending independent review of complete-folder selection and existing personal-only routing.
2. Persistence and concurrency: pending; verify SharedPreferences failure behavior and plan file-backed migration.
3. Compatibility and verification: pending source guards, Flutter tests, Dart analysis and Android build.

### Revision 60 review status
1. Architecture and behavior: pending independent review.
2. Persistence and concurrency: pending; verify atomic snapshot replacement and migration after capacity metadata removal.
3. Compatibility and verification: pending exact-head source guards, Flutter tests, Dart analysis and Android build.

### Revision 58 review status
1. Architecture and behavior: completed; function inventory compared against Revision 57 base and no existing NPV functions were lost.
2. Persistence and concurrency: completed; Gold snapshots, append-only inventories, mode-specific stores, cursor commit and partial-result paths reviewed.
3. Compatibility and verification: pending final CI rerun after the latest source-guard updates.

## Explicit safety boundaries

- No fixed total inventory ceiling is applied to stored resources or completed discoveries.
- Per-call scan batches, adaptive concurrency and background pacing are retained to protect device/network stability; cursors continue across batches.
- Explicit user-supplied IPv4/IPv6 CIDRs and address ranges are expanded through resumable cursor batches; the scanner does not materialize the entire address space in memory at once.
- Batch size, worker concurrency and background pacing remain resource controls. They do not impose a total address, result, or daily-probe ceiling.

## Numbering rule

Increment the revision number by exactly one for each substantial edit set. Record the new number and its PR in this file. Do not change the revision number for routine CI reruns or review-only corrections within the same revision.
