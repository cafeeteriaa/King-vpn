# Personal-folder streaming pipeline

## Scope

This design moves the personal-server folder's durable mutation and connection-preparation paths away from building a full list of parsed `Server` objects. It does not claim that the entire application is constant-memory: the legacy `personalFolderCache` is still loaded at startup and is used by unrelated screens and membership checks.

## Data flow

1. `PersonalFolderStore` validates the primary JSONL snapshot before exposing records. If the primary is invalid, it validates and uses the backup. A partial prefix is never yielded from a corrupt primary.
2. `readBatches(batchSize: 128)` emits bounded batches. The batch size is a processing unit, not a maximum folder size.
3. The home-page connection preparation reads a 50-record display page separately, then streams the full durable archive through `PersonalFolderProbeCoordinator`.
4. A probe callback parses one link into a `Server`, marks it as personal, and calls the existing core-backed `_delayOnce` health check. The coordinator bounds concurrent probes by the configured delay gate.
5. Failed probes are retried once after the configured retry delay. Retry results update the visible row state as well as the candidate ranking.
6. Successful links are sorted by measured latency. `personalLastGood` breaks latency ties only; it never outranks a genuinely faster server.
7. If every probe fails, the store is streamed again to preserve the original archive order for the existing real-core connection/failover path.
8. Failover stores links rather than retaining a second full set of parsed `Server` instances; the selected link is parsed at the point of connection.

## Compatibility guarantees

- Existing VPN and Proxy modes are not replaced or expanded into a third mode.
- The existing core start/stop, engine selection, connection verification, personal-session handling, and personal failover paths remain in place.
- The personal archive is not truncated. Batch size and UI page size do not delete, skip, or cap stored records.
- If core-backed ping cannot identify a winner, the real connection path still gets the full ordered fallback inventory.
- Cancellation is generation-based; stale prewarm/probe work stops before consuming later batches.

## Memory and performance boundaries

This stage bounds transient parsed-server objects and probe concurrency. It still retains:
- the legacy startup `personalFolderCache` containing raw links;
- the successful ranked-link list used for deterministic failover;
- the current UI page and its rows.

The all-failed fallback also materializes the links into the existing failover list. Removing those remaining O(N) structures requires a separate disk-backed candidate index/queue and migration of all synchronous consumers such as `_inPF`, `_purgePersonalLeaks`, and legacy list entry points. That migration must preserve ordering, favorites, failover, and offline/online exclusion behavior; it must not be approximated by an arbitrary cap.

Storage mutations currently stream existing records into a staged replacement and rotate a validated backup. This bounds RAM for append/remove relative to the existing archive, but remains O(N) sequential I/O per mutation. The full-snapshot replacement path now writes JSONL records incrementally and validates the old primary with a streaming pass instead of building a second normalized list, a giant encoded string, or a full decoded copy merely to rotate the backup. It still freezes the caller's supplied iterable and keeps an exact deduplication set, so that API is not claimed to be constant-memory for unbounded input. A journal/index can be considered after correctness and recovery tests are established.

## Verification matrix

The coordinator tests cover:
- latency ordering and last-good tie-breaking;
- one retry for failed probes, including refreshing the visible result;
- full ordered fallback when all probes fail;
- maximum concurrent probes;
- cancellation before later batches and fallback.

The storage tests cover:
- 6,000-record inventory traversal in bounded batches;
- deduplicating append and transactional removal;
- backup recovery and membership checks.

The source guard ensures the personal-folder preparation path uses paged display data and streaming batches rather than calling `personalFolderServers()` to materialize the whole folder.

Android CI must still complete the Flutter unit-test, Dart analysis, and release APK stages on the final branch head before this stage is considered verified for merge.
