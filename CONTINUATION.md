# King VPN — continuation checkpoint

## Current checkpoint — 2026-11-27 07:35 UTC
- Repository: `cafeeteriaa/King-vpn`.
- Development branch: `feature/personal-folder-streaming-mutations-20261127`.
- HEAD before this checkpoint commit: `a234129e8d63a3a6bb6981f43b75920ddbaf684e`; this commit records the current state and becomes the branch HEAD after the ref update.
- PR #68 is open Draft. PR #69 is closed without merge because the development branch already contains the semicolon fix; the regression guard is being retained directly on this branch.
- The actual Dart syntax issue was `lib/ip_auto_scan.dart:113`: the national-mode `ips` cascade lacked a terminating semicolon before `hostnames`. It is fixed in the development branch at `ed2ac9f100aec9c5bcc81fba? no`; the exact validated commit is `ed2ac9f100aec9c5bcc81e8837407b895250e819`.
- Exact development-code CI [45957884767](https://github.com/cafeeteriaa/King-vpn/actions/runs/45957884767), commit `ed2ac9f100aec9c5bcc81e8837407b895250e819`: SUCCESS. Source guards, Flutter tests, Dart analysis, ARM64 Release build, size report, and artifact uploads all passed.
- Verified artifact for that exact commit: artifact ID `15180290274`; ZIP SHA-256 `e271b0cd44de9d8d00abc6899c69b256878f4ed469724655cf3a5baf1510847e`; APK SHA-256 `25a52f19692dc273079e89ed5332c4c759f886d1dc8458e12af038f656fb8705`; size 122,885,758 bytes. It contains 19 ELF64/AArch64 native libraries; all PT_LOAD segments are at least 16 KiB aligned and all native-library ZIP data offsets are 16 KiB aligned. It is signed with a generated debug key, not a production release key.
- The isolated fix branch CI [45958072865](https://github.com/cafeeteriaa/King-vpn/actions/runs/45958072865), commit `f64a482c92f32246e5fee7856489929b67663937`, passed source guards, Flutter tests and Dart analysis but the APK build failed after three retries because Maven Central returned HTTP 429 for Kotlin Gradle Plugin 2.2.20 artifacts. No APK was produced for that commit.
- CI [45959282092](https://github.com/cafeeteriaa/King-vpn/actions/runs/45959282092), commit `a234129e8d63a3a6bb6981f43b75920ddbaf684e`, failed only in the new Python source guard because the regex was over-escaped. This commit corrects the pattern to use a single-backslash raw regex; the Dart source remains unchanged.
- Earlier CI [45957798844](https://github.com/cafeeteriaa/King-vpn/actions/runs/45957798844) exposed the missing semicolon and three Flutter test files failed to load. The development-code CI above proves the corrected source compiles, tests, analyzes and builds.
- The checkpoint commit's exact-head CI is pending; do not claim its build until the run completes.
- Main remains untouched at `9b36ae7dd9ac0379a3b3b84091752f9322bb649d`. No CI execution was cancelled by this work.
- Open engineering risks:
  - `_natAutoScanCandidates` still stores growing national SNI/port/TLS lists as one SharedPreferences JSON string rather than a streaming file-backed inventory.
  - `_natReadInventory` uses `readAsLines()` and a full deduplication map; `natNationalIpMemLoad` and `natNationalIpMemHosts` also materialize the complete inventory. The current JSONL append is durable but not bounded-memory.
  - Personal-folder startup/connection preparation still retains full in-memory caches; scheduler remains process-local Timer-based.
  - No real-device, Iranian-operator, actual TUN traffic, DNS-leak, IPv4/IPv6 handover, or battery tests have been performed.
- IP Clean source lists, ranges, ports, and scan capabilities were not removed or narrowed.
- First next action: verify CI for this checkpoint commit; then migrate national IP and SNI/port/TLS candidate inventories to crash-safe streaming cursor/page storage without truncating existing data.

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