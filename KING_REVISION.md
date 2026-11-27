# KING VPN Revision Ledger

Current revision: 75
Next revision: 76
Repository: cafeeteriaa/King-vpn
Revision branch: feature/isolate-safe-rust-acceleration-v1-20261127
Parent revision branch: feature/unified-scanner-scheduler-rust-production-v4-20261127
Parent PR: https://github.com/cafeeteriaa/King-vpn/pull/79
Revision PR: https://github.com/cafeeteriaa/King-vpn/pull/80
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


### Revision 68 — Multi-stage KING AI engineering pipeline
- Pull request: https://github.com/cafeeteriaa/King-vpn/pull/72
- Replaced the single-pass owner feature proposal path with a dependency-ordered plan of up to six implementation stages.
- Each model pass retains a bounded context (up to six existing files / 7,500 characters) and may change up to three files; completed outputs are passed forward when later stages touch the same file.
- Added stale-input conflict detection, source-path validation, per-stage and aggregate budgets, and an atomic bundle capped at 18 changed files / 180,000 content characters.
- All stages are combined into one Git tree/commit and one Draft PR. If a stage fails or the aggregate is invalid, no partial PR is created.
- Pinned every stage to one captured main commit SHA and aborts PR creation if main advances before the final commit, preventing mixed snapshots and stale overwrites.
- Preserved the narrower background-autonomous audit policy (at most two files, no merge/release); only explicit owner-authenticated feature requests use the larger staged pipeline.
- Added pipeline unit tests and source guards. The new pipeline and its tests are protected from local-model self-modification.
- Behavior-preserving CI unblocker: qualified the existing PersonalFolderStore snapshot decoder call so the inherited source guard can verify the public codec is used.
- Review pass 1: architecture and dependency ordering; verify the single-PR commit model and preservation of owner authentication.
- Review pass 2: path validation, stale-stage conflict handling, aggregate file/content budgets, secret checks and no-partial-PR behavior.
- Review pass 3: tests/source guards, compatibility with the existing local model context limits, and exact-head CI/build review.
- First exact-head CI run 45973769538 failed in the inherited PersonalFolderStore source guard before Flutter setup; the existing codec call was aligned without changing behavior. A rerun is pending. Flutter tests, Dart analysis, Android arm64 build and device validation are not yet verified. No merge or release is authorized by this revision.


### Revision 69 — optional Rust IPv4/IPv6 range accelerator
- Added a dependency-free Rust native library for IPv4/IPv6 address, CIDR and inclusive range batch generation with decimal cursors, including full IPv6 `/0` without `u128` overflow.
- Integrated it into `natExpandAddressRangeBatch` through optional Android FFI. The existing Dart BigInt implementation remains the fallback for non-Android platforms, missing libraries, invalid native output and FFI errors.
- Added Rust unit coverage for IPv4/IPv6 paging, IPv4 page wrap semantics, large IPv6 offsets, descending ranges, single IPs, invalid prefixes/families and the full IPv6 address space.
- Updated Android CI to run Rust Clippy/tests, compile `arm64-v8a` with the NDK and package the shared library; added direct Dart `ffi` dependency.
- Preserved scanner entry points, cursor behavior, VPN/Proxy behavior and existing inventories. Performance improvement is not claimed until benchmarked on hardware.
- Review pass 1 (architecture/behavior): compare CIDR/range semantics, cursor wrap and Dart fallback contract.
- Review pass 2 (FFI/security/reliability): inspect pointer ownership, output sizing, panic boundary, invalid response handling and ABI-specific packaging.
- Review pass 3 (compatibility/verification): inspect CI ordering, Cargo lock, existing scanner tests and full diff. Automated execution remains pending; this is not a build/test sign-off.
- Exact-head GitHub Actions, Flutter tests/analyzer, Android arm64 APK build and physical-device validation are pending. No merge or release is authorized by this revision.


### Revision 69 CI correction note
- The first Rust CI run exposed an incorrect test expectation: the existing IPv4 batch cursor deliberately wraps within the requested page. The implementation matched the pre-existing Dart behavior; the regression test was corrected to assert the same wrap order.
- The exact current head includes the corrected test, explicit unsafe blocks, a crate-level unsafe-operation lint, an FFI batch-size guard and preserved dynamic symbols. The new exact-head workflow result is pending.


### Revision 69 — restore dynamic source discovery build integrity
- Root cause of the Flutter test compilation failure was confirmed on the PR #72 base: `king_dynamic_source_discovery.dart` contained repeated class-member blocks and truncated raw string literals; later missing-member errors in `king_local_ai.dart` and switch errors in `iran_ai_extras.dart` were parser cascades.
- Replaced the duplicated/corrupt source-discovery file with one complete incremental implementation preserving the five GitHub search queries, 100-result pages, 10-page GitHub API boundary, 2-minute cycle budget, four workers, 12-hour cache TTL, 15-minute retry delay, path scoring, safe raw URL policy, and persistent query/page cursor.
- Added partial-result persistence on cancellation, atomic cache replacement with backup recovery, strict Git-ref and raw URL validation, and truncated-tree handling. Existing cached feeds are retained and merged; no total feed/repository cap is introduced.
- Expanded policy tests and source guards to prevent duplicate class blocks and loss of the incremental checkpoint/worker behavior.


### Revision 69 — remove duplicated KING AI method tails
- After repairing the dynamic-source parser blocker, the next compiler pass exposed a second pre-existing structural corruption in `king_local_ai.dart`: the complete `KingLocalAi` class closed at line 2014, followed by repeated out-of-class copies of `createRepairPullRequest`, `_createRepairPullRequest`, `_planOwnerFeature`, `createOwnerFeatureProposal` and `dispose`.
- Kept the complete original class implementation, including GitHub/CI repair, owner planning, proposal generation and disposal; removed only the duplicate invalid tails after the class boundary.
- Added source guards asserting one class and one copy of each critical method so this duplication cannot silently return.


### Revision 70 — versioned Rust/Dart native bridge contract
- Pull request: https://github.com/cafeeteriaa/King-vpn/pull/75
- Added a versioned native ABI contract and Dart-side compatibility checks while preserving the optional Rust fallback model.

### Revision 71 — cross-language VPN service diagnostics
- Pull request: https://github.com/cafeeteriaa/King-vpn/pull/76
- Added a versioned diagnostics contract across Android, Kotlin and Dart with explicit absent/error fallback values.

### Revision 72 — watchdog health telemetry
- Pull request: https://github.com/cafeeteriaa/King-vpn/pull/77
- Added monotonic watchdog and health-probe telemetry without treating core CONNECTED as proof of working data-plane.

### Revision 73 — validated physical network underlay handover
- Pull request: https://github.com/cafeeteriaa/King-vpn/pull/78
- Added Android monitoring of validated physical Wi-Fi/cellular underlays and protocol-v3 diagnostics; exact-head CI run 46005789109 passed ARM64 APK packaging and upload.

### Revision 74 — production Rust range batches and serialized scanner orchestration
- Pull request: https://github.com/cafeeteriaa/King-vpn/pull/79
- Routed the production NAT range generator through the shared optional Rust/Dart batch API.
- Added a lifecycle-aware idle scheduler that runs DNS then IP, coalesces repeated requests, and cancels safely on connection, mode, lifecycle or competing-scan changes.
- Added cross-scanner exclusion guards, cancellation propagation, scheduler tests, production-sized cursor tests and Persian architecture documentation.
- Exact-head CI is pending; no merge or release is authorized until all checks pass and Samsung device validation is completed.


### Revision 75 — isolate-safe Rust acceleration calibration
- Pull request: https://github.com/cafeeteriaa/King-vpn/pull/80
- Moved Rust-vs-Dart calibration to the long-lived UI isolate so repeated short-lived compute isolates do not independently benchmark the native engine on every scanner batch.
- Passed the calibrated native-selection decision into worker isolates; each worker validates exact cursor and address parity on its first native batch, then reuses the native path for the rest of that batch.
- Any missing library, malformed native response or parity mismatch falls back to Dart and disables native selection in the owning UI isolate for subsequent work.
- Added worker fallback/parity tests and source guards for the calibration boundary. Exact-head CI and independent review are pending; no device-level performance claim is made.
