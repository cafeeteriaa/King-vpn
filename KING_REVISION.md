# KING VPN Revision Counter

- Current revision: **58**
- Previous revision: **57** — fresh-resource storage work (PR #57).
- Repository: `cafeeteriaa/King-vpn`
- Counter scope: substantive, user-visible engineering edit batches; not GitHub commit IDs.
- Increment rule: increment exactly once for each completed substantial edit batch. Commits that are only corrections within the same batch do not create another revision.
- Review rule: every revision must record three distinct review passes:
  1. Architecture, compatibility, and preservation of existing behavior.
  2. Correctness, concurrency, resource lifecycle, and failure recovery.
  3. Tests, static analysis, build validation, and a final diff review.
- A revision is not marked complete until its three passes and available automated checks are recorded. Failed or pending checks must remain explicitly marked as such.
- Do not silently reset, reuse, skip, or decrement a revision number. Update this file in the same change batch as the implementation and include the revision number in the branch/PR title and description.

## Revision 58 — in progress

Scope:
- Audit and repair altered, removed, or arbitrarily restricted IP, SNI, DNS, DPI, port, Host, and domain discovery/application paths.
- Trace TLS ClientHello fragmentation from variant generation through core-config serialization and the actual Android VPN-core connection path; do not count UI-only configuration as implemented.
- Preserve distinct global and national-network engines and their inventories.
- Replace destructive fixed truncation with resumable, cursor-backed processing where technically practical; keep only transparent device/network safety controls that prevent resource exhaustion, and never silently discard unprocessed inventory.

Three review passes: pending implementation.
Automated validation: pending.
