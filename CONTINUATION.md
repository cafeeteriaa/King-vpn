# King VPN — continuation checkpoint

## Source of truth
- Repository: cafeeteriaa/King-vpn
- Active branch: fix/personal-folder-uncapped-20261127
- Parent branch: fix/healthy-folder-unbounded-retention-20261127
- Revision: 65
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
