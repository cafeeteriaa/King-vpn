# King VPN — continuation checkpoint

## Source of truth
- Repository: cafeeteriaa/King-vpn
- Active branch: feat/king-ai-multistage-engineering-20261127
- Parent branch: fix/personal-prep-cancellation-20261127
- Revision: 68
- Pull request: PR #72; parent PR #71; consolidated integration PR #66.
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

## Revision 68 — disk-backed personal inventory and compact identity index
- Startup keeps the first display page plus a compact parsed host:port identity index; it no longer materializes the full configuration archive in `personalFolderCache`.
- Personal-folder append/remove are streamed, transactional disk rewrites. The durable JSONL archive remains the source of truth; the visible page and count refresh after each committed mutation.
- The compact identity index is revision-aware and waits for in-flight rebuilds across mutations; stale rebuilds are discarded if the archive revision changes during a stream.
- Full-inventory behavior remains available through disk-backed cursors and exhaustive personal-only core fallback. The 50-row page and 32-entry preferred ranking window are working-set sizes, not inventory limits.

## Current checkpoint — 2026-11-27 09:31 Europe/Rome
- Repository: `cafeeteriaa/King-vpn`.
- Development branch: `fix/personal-prep-cancellation-20261127`, based on `fix/personal-folder-uncapped-20261127`.
- Parent SHA before this change: `e1efc276c6440361b5eb621fa91f1f810490d005`.
- PR: draft child PR targeting `fix/personal-folder-uncapped-20261127`; no merge to `main`.
- Active GitHub Actions before commit: none; no run was cancelled.

### Personal archive scan cancellation and redundant I/O
- Added a monotonic `PersonalFolderScanEpoch` and threaded it through prewarm, exact membership lookup, archive streaming, batch pings, preferred connection and exhaustive core fallback.
- A newer personal tap, non-personal tap or widget disposal invalidates prior work. Results returning after an awaited probe are discarded before mutating live rows/ranking.
- Connection preparation reuses the exact `personalFolderCount` refreshed by disk-backed startup/mutations; it falls back to a cancellable count only if the view is not initialized. This removes the routine extra full-file count scan before the actual archive scan.
- Added Dart tests for epoch invalidation and cancellable membership lookup, plus a Python source guard for runtime wiring.
- No IP Clean sources, ranges, CIDRs, ports, cursors or scanner capabilities were removed or narrowed. VPN/Proxy modes and personal-only routing remain unchanged.

### Validation
- Local Flutter/Dart tests and `flutter analyze`: not run; this container has no Flutter/Dart SDK and no outbound GitHub access.
- Python source guards, Flutter tests, Dart analysis and ARM64 release build: pending exact-head GitHub Actions.
- Three source review passes: (1) generation invalidation/stale-result handling, (2) JSONL preflight/cancellation and bounded working set, (3) personal-only routing/fallback and test/guard integration. These are source-level reviews, not device verification.
- CI run URL/status: pending child PR synchronize event.

### Open issues
- The compact `host:port` identity set remains proportional to archive size; full configuration strings are disk-backed rather than retained as one large list.
- The complete personal archive is still probed and remains eligible for real-core fallback by design; CPU/battery cost needs measurement on a real Android device.
- TUN traffic, DNS leak, IPv4/IPv6 handover, Iranian operator coverage, competing VPN behavior and failover still require physical-device validation.

### First next action
1. Verify the exact-head child PR workflow and inspect all Python guards, Flutter tests, Dart analysis and ARM64 build steps.
2. Fix any genuine failure without weakening guards or reducing the inventory.
3. On success, inspect the exact-run APK artifact and hashes, then continue Android DNS/routing and failover device tests.


## Revision 68 — Multi-stage KING AI engineering pipeline
- Owner feature requests are planned as 1–6 dependency-ordered stages.
- Each inference stage reads up to 6 existing files / 7,500 characters and can update up to 3 files. Prior-stage file outputs are reused as the next-stage input when relevant.
- Stage outputs are collected in KingAiPatchBundle with path validation, sequential-stage enforcement, stale-input conflict detection, an 18-file aggregate limit and a 180,000-character content budget.
- Only after every stage finishes is one atomic Git tree/commit and one Draft PR created. A missing context or invalid stage stops the run before PR creation; no partial PR is created.
- Captures one main commit SHA for all stage contexts and aborts if main advances before final PR creation, preventing mixed snapshots and stale overwrites.
- The autonomous background audit remains limited to at most two changed files and still cannot merge or release.
- Added test/king_ai_change_pipeline_test.dart and source guards for aggregation, conflict detection, limits and the autonomous safety boundary.
- Three source review passes are recorded in KING_REVISION.md. Exact-head CI, Flutter tests, Dart analysis, Android build and device validation are still pending until the PR workflow completes.
- Limitation: the local model still reads only existing files in lib/, test/ and tools/. It cannot create new files or change Android Native, Gradle, dependencies, CI, signing or security policy through this automated owner path.
