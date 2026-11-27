# King VPN — continuation checkpoint

## Current verified checkpoint — 2026-11-27 07:30 UTC
- Repository: `cafeeteriaa/King-vpn`.
- Development branch: `feature/personal-folder-streaming-mutations-20261127`.
- HEAD before this checkpoint commit: `ed2ac9f100aec9c5bcc81e8837407b895250e819`; this commit records the current state and becomes the branch HEAD after the ref update.
- PR #68 remains Draft and targets the uncapped personal-folder branch. PR #69 is a temporary stacked syntax-repair PR; this checkpoint ports its regression guard into the development branch so the duplicate PR can be retired after this commit's CI.
- The missing semicolon in `lib/ip_auto_scan.dart::_ipAutoBlocks` is already fixed on this development branch. Added a Python source guard that requires the national `ips` cascade to terminate before the `hostnames` cascade.
- Exact development-head CI [45957884767](https://github.com/cafeeteriaa/King-vpn/actions/runs/45957884767), commit `ed2ac9f100aec9c5bcc81e8837407b895250e819`: SUCCESS. Python guards, Flutter tests, Dart analysis, ARM64 Release build, size report, and artifact uploads all succeeded.
- Verified artifact from that exact commit: artifact ID `15180290274`, ZIP SHA-256 `e271b0cd44de9d8d00abc6899c69b256878f4ed469724655cf3a5baf1510847e`; APK SHA-256 `25a52f19692dc273079e89ed5332c4c759f886d1dc8458e12af038f656fb8705`, 122,885,758 bytes. The archive contains one ARM64 APK with 19 ELF64/AArch64 native libraries; every PT_LOAD alignment is at least 16 KiB and each native-library ZIP data offset is 16 KiB aligned. The workflow uses a generated debug signing key, not a production release key.
- Isolated repair-branch CI [45958072865](https://github.com/cafeeteriaa/King-vpn/actions/runs/45958072865), commit `f64a482c92f32246e5fee7856489929b67663937`: source guards, Flutter tests, and Dart analysis SUCCESS; ARM64 build FAILED after three retries because Maven Central returned HTTP 429 while downloading Kotlin Gradle Plugin 2.2.20 artifacts. This is an external dependency rate-limit failure, not a Dart/source compilation failure. No APK was produced for that isolated commit.
- Earlier source-branch CI [45957798844](https://github.com/cafeeteriaa/King-vpn/actions/runs/45957798844) exposed the missing semicolon at `lib/ip_auto_scan.dart:113`, which prevented three Flutter test files from loading. The fix is present in `ed2ac9f`. Earlier guard-only failure [45957565918](https://github.com/cafeeteriaa/King-vpn/actions/runs/45957565918) was caused by a stale source assertion for the old SharedPreferences-to-`natScanHits` handoff; later tests were aligned with the file-backed inventory path.
- The first isolated guard attempt [45957863923](https://github.com/cafeeteriaa/King-vpn/actions/runs/45957863923) failed because its own assertion escaped the newline incorrectly; the guard was corrected to a whitespace regex and passed on the development-head CI.
- Main remains untouched at `9b36ae7dd9ac0379a3b3b84091752f9322bb649d`. No CI run was cancelled by this work.
- Open engineering risks:
  - `_natAutoScanCandidates` still stores growing national SNI/port/TLS lists as one SharedPreferences JSON string rather than a streaming file-backed inventory.
  - `_natReadInventory` currently uses `readAsLines()` and a full deduplication map; `natNationalIpMemLoad` and `natNationalIpMemHosts` also materialize the entire inventory. This is not bounded-memory despite JSONL append storage.
  - Personal-folder startup and connection preparation still retain full in-memory caches; scheduler remains process-local Timer-based, not a persistent Android background worker.
  - No real-device, Iranian-operator, DNS-leak, actual TUN traffic, IPv4/IPv6 handover, or battery test has been performed.
- IP Clean source lists, ranges, ports, and scan capabilities were not removed or narrowed.
- First next action: validate CI for this checkpoint commit; then replace full-file national inventory reads and SharedPreferences candidate snapshots with crash-safe streaming cursor/page storage, preserving all existing records and mode isolation.

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