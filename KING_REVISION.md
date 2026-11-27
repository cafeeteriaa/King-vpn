# KING VPN Revision Ledger

Current revision: 67
Next revision: 68
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

### Revision 63 — remove pending-queue and saved-list truncation
- Removed the hard 1,200-entry truncation from the national-network pending queue; entries already held by the active queue are no longer silently discarded at that count.
- Removed the 3,000-entry truncation and full-list shuffle allocation from the persisted list_cache snapshot; all fetchedAll entries are serialized in their current order.
- Added source guards against reintroducing either truncation.
- Per-batch concurrency and staged quick-start behavior remain separate from total inventory retention; further adaptive batching and disk-backed storage remain follow-up work.
- Exact-head CI and runtime validation are pending.

### Revision 64 — preserve all learned national winners and variants
- Removed the 50,000-key truncation from the learned national-network winner set (natGood).
- Removed the 3,000-entry eviction from the persisted normal-network variant-learning map (natVarNormal), so successful per-server learning is not discarded by a fixed count.
- Added source guards against reintroducing either count-based eviction.
- These collections can now grow with discovered/learned endpoints; a disk-backed/indexed design and profiling are required before very-large-scale claims. Other short-lived memoization caches remain bounded for actual memory safety and are not authoritative server inventories.
- Exact-head CI and runtime validation are pending.

### Revision 65 — migrate personal servers to an atomic file-backed snapshot
- Added a dedicated app-private JSONL store for personal VPN profiles, separate from the global preferences document and from public/healthy server inventories.
- Writes use a same-directory temporary file, flush, replacement, and a last-known-good backup; unreadable primary snapshots fall back to the backup.
- Existing installations migrate the legacy personal-folder list only when no valid file snapshot exists. The legacy key is removed only after the new snapshot has been persisted and flushed.
- Add/remove operations now write the complete personal-folder snapshot through the dedicated store; the last-good marker remains in preferences.
- Added source guards for migration, atomic replacement, recovery copy, and separation from legacy preferences.
- Important: UI/connection consumers still materialize the full folder into personalFolderCache. This is durable file-backed persistence, not yet memory-bounded pagination. A paged repository API and consumer migration remain required.
- Exact-head CI, migration tests, Android build and device recovery tests are pending.

### Revision 65.1 — protect valid backup during corrupt-primary recovery
- Hardened snapshot replacement so a corrupt primary file cannot overwrite the last known-good backup.
- The primary snapshot is validated before it is copied over the backup; invalid primary data is discarded while the valid backup remains available for recovery.
- Added a regression source guard for this crash/corruption sequence.
- Exact-head CI and Android fault-injection tests remain pending.

### Revision 65.2 — add lossless personal-folder snapshot codec tests
- Extracted pure JSONL encode/decode helpers from file I/O so record integrity can be tested without Android path-provider channels.
- Added Flutter tests for Unicode, embedded line breaks, case-insensitive deduplication, valid-empty versus corrupt snapshots, and 6,000-entry retention.
- Exact-head CI remains required; these tests are committed but have not yet been executed in this session.

### Revision 65.3 — serialize store-level writes and migrations
- Added a store-owned asynchronous mutation queue so file replacement and legacy migration remain serialized even if future callers bypass the personal-folder wrapper.
- Snapshot inputs are copied before entering the queue to prevent later caller mutation from changing the pending write.
- Added a source guard for both serialized entry points.
- Filesystem and Flutter tests are committed; exact-head CI has not yet run.

## Mandatory three-pass review protocol

Each numbered revision must be a substantial functional change and pass three separate reviews:
1. Architecture and behavior: feature preservation, global/National Net isolation, complete inventory traversal and no hidden truncation.
2. Persistence and concurrency: atomic/serialized writes, cursor commit rules, cancellation, partial-result retention and recovery.
3. Compatibility and verification: source guards, unit tests, static analysis, Android build and final diff review.

### Revision 65 review status
1. Storage architecture and legacy migration: pending.
2. Atomicity, crash recovery and concurrent writes: pending runtime tests.
3. Compatibility, tests, Dart analysis and Android build: pending.

### Revision 64 review status
1. Learning retention behavior: pending independent review.
2. Persistence/memory growth: pending profiling and disk-backed migration.
3. Compatibility/verification: pending exact-head CI, Flutter tests, Dart analysis and Android build.

### Revision 63 review status
1. Queue and inventory behavior: pending independent review of queue consumers and retry/cursor semantics.
2. Persistence and memory: pending; full list_cache snapshot remains in SharedPreferences and needs disk-backed migration.
3. Compatibility and verification: pending exact-head CI, Flutter tests, Dart analysis and Android build.

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


### Revision 66 — crash-safe personal-folder persistence and transactional cache updates
- Reworked snapshot rotation so the previous valid backup is never deleted before its replacement is fully staged and flushed.
- Replaced delete-before-rename of the primary snapshot with same-directory rename replacement on Android/Linux, avoiding an intentional missing-file window.
- Add/remove operations now persist the proposed full snapshot before publishing the new in-memory cache; failed writes retain the previous cache.
- Made add deduplication case-insensitive and report only entries successfully committed to disk.
- Added tests for failed staged writes, serialized overlapping snapshots, and source guards for cache commit ordering and safe backup rotation.
- Review pass 1 (architecture/behavior): reviewed personal-only inventory isolation, public API compatibility and full-folder retention.
- Review pass 2 (persistence/recovery): reviewed primary/backup rotation, staged writes, corrupt-primary recovery and mutation serialization.
- Review pass 3 (compatibility/tests): source and test changes re-read; automated execution is still pending, so this pass is not a test/build sign-off.
- No CI result is available yet for the new exact head. No merge or release is authorized by this revision.


### Revision 67 — streaming pagination for the personal-server folder
- Added a disk-streamed page API that reads JSONL records incrementally, stores only the requested page in the result, and computes the exact filtered result count across the archive.
- Added primary-corruption fallback to the last valid backup for paged reads.
- Rebuilt the personal-folder bottom sheet around 50-row pages, explicit previous/next navigation, archive-wide link/domain/IP search, exact result counts and page-scoped deletion.
- A row tap now preserves the profile's personal classification and routes the selected profile through its direct personal connection path; smart-connect across the whole folder remains available as a separate action.
- Added tests for multi-page traversal beyond 100 entries, case-insensitive full-archive search and backup fallback, plus source guards for paged UI/store integration.
- Review pass 1: reviewed page API boundaries, UX state transitions and preservation of the existing VPN/Proxy modes.
- Review pass 2: reviewed streamed parsing, exact counts, corrupt-primary fallback, empty results and page navigation after removal.
- Review pass 3: re-read the changed Dart files and tests; no Dart formatter/analyzer or runtime test has been executed yet.
- Important limitation: the app's startup loader and personal connection/ping path still materialize/use the complete personalFolderCache. This revision pages the folder screen's disk reads; it does not yet deliver end-to-end memory-bounded personal inventory processing.
- Exact-head CI, Flutter tests, Dart analysis, Android build and device-level connection/recovery validation remain pending. No merge or release is authorized by this revision.

### Revision 68 — validate the complete Android background bridge contract
- Added a pure validator for the versioned `vpn/bg` handshake: protocol version, channel, expected package name, attached Flutter engine, `alive`, `back`, `vpnSettings` capabilities, and positive Android SDK metadata.
- The Dart probe now rejects incomplete or mismatched native metadata and uses the existing exponential retry path rather than accepting a partial handler.
- Added unit tests for valid metadata, wrong package, detached engine, missing capabilities, protocol mismatch and invalid SDK, plus a source guard for runtime integration.
- Review pass 1: verified every capability consumed by Dart is part of the handshake and package identity is checked against the app constant.
- Review pass 2: verified an invalid/detached response falls through the existing retry/backoff path; no VPN start/stop behavior or TUN routing was changed.
- Review pass 3: checked pure unit-test cases and source-guard integration; exact-head CI and device validation remain pending.
- No IP Clean resources, ranges, CIDRs, ports, cursors or scan behavior were modified.
