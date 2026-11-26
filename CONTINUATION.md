# King VPN — continuation checkpoint

## Source of truth
- Repository: cafeeteriaa/King-vpn
- Active branch: fix/healthy-folder-unbounded-retention-20261127
- Parent branch: fix/healthy-folder-small-sample-outage-20261126
- Revision: 60
- Main remains untouched. This work is isolated from the default branch and prior PRs.

## Revision 60 changes
- Removed the fixed 50,000-entry healthy-server count ceiling and oldest-entry eviction from lib/main.dart.
- Removed obsolete capacity metadata from the persisted snapshot.
- Updated test/test_healthy_folder_policy.py to guard against reintroducing a fixed count ceiling or eviction.
- Preserved Revision 59's network-outage protection and Revision 58's independent scan inventories.

## Explicit remaining work
- The healthy-folder map and JSON snapshot are still whole-inventory/in-memory. Do not claim paging, memory-bounded operation, or multi-million-entry readiness yet.
- Next implement a disk-backed indexed/paged inventory with transactional writes, migration/rollback, async page iteration for all consumers, and restart/cancellation tests.
- Exact-head CI, Flutter tests, Dart analysis, Android build and device tests are not yet confirmed for Revision 60.
- Do not merge to main until three independent reviews and exact-head CI pass.

## Three review passes
1. Architecture and behavior: pending.
2. Persistence, concurrency, migration and recovery: pending.
3. Compatibility, regression tests, Dart analysis and Android build: pending.
