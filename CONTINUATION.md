# King VPN — continuation checkpoint

## Current checkpoint — 2026-11-27 07:18 UTC
- Repository: `cafeeteriaa/King-vpn`.
- Isolated repair branch: `fix/national-ip-auto-blocks-syntax-20261127`.
- Parent SHA at branch creation and before this commit: `73f2c4a5a759e6aeed5f5a798e6bb3eea48f3197`.
- Source development branch: `feature/personal-folder-streaming-mutations-20261127`, forked at the exact SHA above. Its PR #68 remains Draft; no merge to `main`.
- Repair: `lib/ip_auto_scan.dart` had a missing semicolon terminating the national-mode `ips` cascade before the `hostnames` cascade in `_ipAutoBlocks`. Added the terminator and a Python source guard so this parser-level regression is caught before Flutter analysis.
- Tests executed locally in this run: none; repository files were inspected through GitHub. The new source guard is committed but awaits exact-commit CI.
- CI on the source branch at checkpoint: run [45957565918](https://github.com/cafeeteriaa/King-vpn/actions/runs/45957565918) was pending for `73f2c4a5a759e6aeed5f5a798e6bb3eea48f3197`; run [45956858397](https://github.com/cafeeteriaa/King-vpn/actions/runs/45956858397) remained in progress on older SHA `ff59d665c46a0c1a6f6db86bb4015441d9d762be`. Neither was cancelled by this repair.
- CI for this isolated repair branch: not yet started at checkpoint creation. Do not claim tests, analysis, APK build, or device validation until the exact repair commit has evidence.
- Review passes: (1) syntax/cascade boundary inspected; (2) regression guard added; (3) full compatibility/build review pending exact-head CI.
- Open engineering risks:
  - `_natAutoScanCandidates` still persists the growing national SNI/port/TLS candidate collections as one SharedPreferences JSON string; it is not yet a streaming file-backed store.
  - National IP JSONL append exists, but `natNationalIpMemLoad` and `natNationalIpMemHosts` materialize the complete inventory in memory. A cursor/page reader is still needed before claiming bounded-memory scanning.
  - Personal-folder startup and connection preparation still retain full in-memory caches; this boundary is documented in Revision 67.
  - The scan scheduler is process-local Timer-based, not a persistent Android background worker. Core-outbound candidate checks do not prove Android TUN traffic or real national route health.
  - No real-device, Iranian-operator, DNS-leak, IPv4/IPv6 handover, or battery test was performed in this run.
- IP Clean source lists, ranges, ports, and scan capabilities were not removed or narrowed.
- First next action: inspect the exact repair-branch CI (source guards, Flutter tests, `flutter analyze`, ARM64 release build); if successful, inspect the artifact for that exact commit, then continue the disk-backed national candidate/IP inventory design with transactional cursors.

## Source of truth
- Repository: cafeeteriaa/King-vpn
- Active branch: fix/personal-folder-uncapped-20261127
- Parent branch: fix/healthy-folder-unbounded-retention-20261127
- Revision: 67
- Pull request: PR #65; consolidated integration PR #66; parent Revision 60 is PR #64.
- Default branch is untouched.

## Revision 61 changes
- Removed the personal-folder 1,000-entry insertion ceiling.
- Removed the 100-entry limit from the personal folder's display/preparation and direct-connect selection paths.
- All valid personal entries are now passed to the existing personal-only ping/connect path; personal servers remain isolated from public/healthy server pools.
- Updated source guards and Persian UI wording.

## Revision 62 changes
- Serialized personal-folder load/add/remove/last-good operations through one async mutation queue to prevent overlapping SharedPreferences snapshot writes from losing updates.
- Added a source guard for serialized mutation entry points.

## Revision 63 changes
- Removed the 1,200-entry pending queue truncation in national-mode cache merging.
- Removed the 3,000-entry list_cache truncation and shuffle allocation; the complete fetchedAll list is now saved.
- Added regression source guards for both cases.

## Revision 64 changes
- Removed the 50,000-entry cap on learned national winners.
- Removed the 3,000-entry cap on the persisted normal-network variant map.
- Added source guards for both learning-retention paths.

## Revision 65 changes
- Added a dedicated app-private JSONL personal-folder store with atomic temp-file replacement and a backup snapshot.
- Migrates existing personal-folder preferences only when no valid new snapshot exists; removes the legacy key only after successful persistence.
- Add/remove now persist through the dedicated file store; last-good marker remains in preferences.
- The current UI still materializes the complete folder in memory; true paged consumers remain follow-up work.

## Revision 65.1 recovery hardening
- Preserve a valid backup if the primary JSONL snapshot is corrupt; only rotate a validated primary into the backup slot.
- Added a source guard for corrupt-primary/valid-backup recovery.

## Revision 65.2 tests
- Added a pure JSONL codec and Flutter tests covering Unicode/newline preservation, deduplication, corruption detection and 6,000-entry retention.
- Tests are committed but still need a fresh GitHub Actions run.

## Revision 65.3 concurrency hardening
- Added a store-level serialized mutation queue for snapshot writes and legacy migration.
- Copies each pending snapshot before queued execution.
- Added a source guard for the queue.

## Remaining work and validation
- SharedPreferences string-list storage and the in-memory personalFolderCache remain. This is not yet a file-backed, memory-bounded inventory; design and migrate transactionally before claiming very-large-folder readiness.
- Exact-head CI, Flutter tests, Dart analysis, Android build, and device tests are pending.
- Preserve personal-only routing and owner-supplied server data during any storage migration.

## Three review passes
1. Architecture/behavior: pending.
2. Persistence/concurrency/migration: pending.
3. Compatibility/tests/build/final diff: pending.


## Revision 66 — transactional personal-folder updates and crash-safe rotation
- Personal-folder add/remove now build a proposed snapshot, persist it first, and update the in-memory cache only after the durable store operation succeeds.
- Failed writes leave the current in-memory folder unchanged; add reports zero newly committed entries.
- Duplicate detection is case-insensitive across both existing and newly added links.
- Backup rotation stages and flushes a separate backup temporary file before renaming it over the prior backup.
- The primary snapshot is replaced by same-directory rename without deleting the committed primary first; Android/Linux use filesystem rename replacement semantics.
- Added regression tests for injected write failure and overlapping writes, plus source guards for cache commit ordering and non-destructive backup rotation.
- Exact-head CI, Flutter tests, Dart analysis, Android build and device-level fault injection remain pending.


## Revision 67 — streaming page reads and paged personal-folder screen
- Added PersonalFolderPage and PersonalFolderStore.readPage(offset, limit, query).
- Page reads stream JSONL records from disk, retain only the requested page in memory, and calculate the exact matching total while scanning. Page size is a view batch, not a maximum inventory size.
- Corrupt primary data falls back to the backup for paged reads as well as full snapshot reads.
- Replaced the personal-folder sheet's eager full-list copy with page navigation, archive-wide search, exact total count and long-press removal.
- Selecting a row now marks the parsed profile as personal and invokes the selected profile's own connect path; the all-folder smart-connect action remains separate.
- Added Flutter tests for multi-page inventories, case-insensitive archive-wide search and backup recovery, plus source guards for streaming pagination.
- Important remaining boundary: application startup and personal-folder connection preparation still populate/use the complete personalFolderCache and _personalPingAll list. The UI now pages its disk reads, but the whole application is not yet memory-bounded. Next step is migrating connection preparation and other cache consumers to a disk-backed iterator/cursor without breaking personal-only routing or failover.
- Three review passes for this revision: (1) API/UI architecture and personal-only behavior, (2) streaming/backup/error paths and page navigation, (3) source/test compatibility and diff review. These are source-level reviews only.
- Exact-head CI, Dart analysis, Flutter tests, Android build and device verification remain pending.