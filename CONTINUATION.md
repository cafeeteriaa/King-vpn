# King VPN — continuation checkpoint

## Source of truth
- Repository: `cafeeteriaa/King-vpn`
- Active fix branch: `fix/healthy-folder-small-sample-outage-20261126`
- Parent SHA before this change: `46f0a9b695475a1e72c96abcca2b65ed2fcb7871`
- The containing commit SHA is resolved from the branch ref after commit creation; do not infer it from the file.
- Parent development branch: `fix/revision-58-network-identity-fragmentation-20261126`
- Parent PR #58: https://github.com/cafeeteriaa/King-vpn/pull/58 (open, base `main`; this work has not merged it).
- `main` HEAD observed: `c43d325f9803d4f6306415e511f6790deff9d87e`; no direct main changes.

## Changes
- Fixed `_resDaily` outage handling: previously the final no-success guard required `tested >= 5`. For a due inventory of 1–4 endpoints, all probes could fail twice without reaching either the `tested >= 8` or `tested >= 5` guard, allowing every second-pass failure to be removed.
- The guard now preserves the folder whenever at least one probe completed and no endpoint succeeded: `tested > 0 && passed == 0`.
- Per-entry pruning remains possible only when there is positive reachability evidence (at least one endpoint succeeds) and a failed entry also fails the second chance.
- Added a regression source guard in `test/test_healthy_folder_policy.py`.
- Updated `KING_REVISION.md` to Revision 59.
- No IP Clean inventory, source, range, CIDR, port, cursor, or scan capability was removed or narrowed.

## CI and validation
- Exact-head CI for this fix: pending; resolve by branch `fix/healthy-folder-small-sample-outage-20261126` and the commit SHA after the push.
- No local Flutter/Python test run was performed in this connector session. Do not claim tests, analyze, or APK build passed until exact-head CI confirms them.
- Parent branch CI at checkpoint start:
  - Run 45772387737, commit `0486a2811405d1e1d8a5f7e1ae6df891f448516e`: in progress at ARM64 release build — https://github.com/cafeeteriaa/King-vpn/actions/runs/45772387737
  - Run 45772594983, commit `46f0a9b695475a1e72c96abcca2b65ed2fcb7871`: pending — https://github.com/cafeeteriaa/King-vpn/actions/runs/45772594983
  - Run 45772440261, commit `e8ecff5338115d06434b5d6db8c8a58f7fd6b4a7`: GitHub reports cancelled; this work did not cancel it — https://github.com/cafeeteriaa/King-vpn/actions/runs/45772440261
- No workflow was intentionally cancelled.

## Open issues and limitations
- No physical Android device, Iranian carrier, competing-VPN, DNS packet-capture, end-to-end IPv4/IPv6, network-handover, or CPU/battery test has been performed.
- The healthy-server folder still has a 50,000-entry in-memory cap and oldest-entry eviction. This is separate from IP Clean scan ranges and port inventories, which were not changed. Do not simply remove the cap without a paged/file-backed design and measured memory behavior.
- The 48-hour maintenance cadence and small-sample outage behavior still need device/network validation.
- DNS leak/routing proof and native VPN lifecycle/failover profiling remain open.

## First next action
1. Check exact-head CI for this branch; if any step fails, inspect its log and repair the cause without weakening tests.
2. If CI passes, inspect the exact-run APK artifact, archive digest, APK SHA-256, ABI and signing identity before presenting it.
3. Then design a paged/file-backed healthy-server inventory to replace the 50,000-entry in-memory eviction safely, without changing IP Clean scope.
4. Continue with real-device VPN ownership, DNS routing/leak, IPv4/IPv6 and failover tests.
