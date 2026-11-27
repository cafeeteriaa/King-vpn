## Current checkpoint — 2026-11-27 08:53 Europe/Rome

- Repository: `cafeeteriaa/King-vpn`.
- Development branch: `fix/native-bridge-contract-validation-20261127`.
- Parent development branch: `fix/personal-folder-uncapped-20261127`.
- Parent SHA before this change: `ce8fa5731514162a4377048e9d4d871d143127f3`.
- Implementation commit SHA: resolve from this branch ref after commit creation; exact-head CI is pending.
- Parent PRs #65 and #66 remain Draft/open and unmerged. No changes are being merged to `main`.
- Active GitHub Actions at branch creation: none. No workflow was cancelled.
- The parent already exposed a versioned `vpn/bg` bridge and exponential retry. This revision strengthens the handshake contract; it does not claim real-device VPN validation.

## Revision 68 — validate the full native background bridge contract

- Added a pure Dart contract validator for protocol version, channel name, expected app package, attached Flutter engine, all three consumed capabilities (`alive`, `back`, `vpnSettings`) and positive Android SDK metadata.
- `_probeBgBridge` now rejects incomplete, detached, wrong-package or incompatible bridge responses and enters its existing retry/backoff path.
- Added unit tests for valid metadata, wrong package, detached engine, missing capabilities, protocol mismatch and invalid SDK.
- Added a source guard connecting the runtime handshake to the pure contract validator.
- No IP Clean sources, ranges, CIDRs, ports, cursors, or scanner behavior changed.

## Validation

- New tests: `test/native_bridge_contract_test.dart`; source guard in `test/test_source_guards.py`.
- Local Flutter/Python execution: not performed in this connector session.
- Exact-head source guards, Flutter tests, Dart analysis, ARM64 release build and artifact inspection: pending CI.
- Three source-level review passes completed: (1) protocol/feature contract, (2) engine lifecycle and retry behavior, (3) unit/source-guard compatibility. These are not device-test sign-off.

## Open issues

- The personal-folder startup and connection preparation paths still materialize O(N) collections; UI paging alone does not make connection preparation memory-bounded.
- The native VPN service, real TUN traffic, DNS leak behavior, IPv4/IPv6 handover, competing VPN, failover and CPU/battery usage still need physical-device validation.
- Parent PRs #65/#66 are diverged from their base refs and must remain Draft until ancestry is reconciled and three reviews plus exact-head CI are complete.

## First next action

1. Inspect exact-head CI for this bridge-contract commit; diagnose any failure from the job log without weakening tests.
2. If CI passes, inspect the exact-run APK artifact, archive digest, APK SHA-256, ABI and signing identity.
3. Then continue Android service lifecycle and real tunnel/DNS/failover validation, keeping VPN/Proxy modes and personal-only routing intact.

---

# King VPN — continuation checkpoint

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