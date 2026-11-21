# King VPN — continuation checkpoint

## Source of truth (re-resolve on every continuation)
- Repository: `cafeeteriaa/King-vpn`
- Default branch: `main` (the repository default branch; the working continuation is on the feature branch below).
- Active development branch: `fix/domestic-rank-evidence-20261122`
- HEAD before this checkpoint refresh: `199b4987db229e40f0c68db35d9d06400d0027f3`
- Parent branch: `fix/domestic-evidence-priority-20261122`, parent commit `6d184b1ff37ca1058807f223efa4e14bcc3cdde7`.
- Branch comparison at last inspection: 2 commits ahead, 0 behind; changed paths are `CONTINUATION.md`, `lib/main.dart`, `lib/nnie_core.dart`, and `test/nnie_core_test.dart`.
- PR #41 is open and draft, targeting the parent feature branch (not `main`). Do not merge it until all validation gates pass.
- `CONTINUATION.md` is present on the active branch. A request for the same path on `main` returned 404; do not assume main contains this checkpoint.

## Current implementation
- National candidate evidence ordering: previously verified national traffic > Iranian ASN IPv4 assignment > Reality transport hint > CDN hint > other.
- Source-list names and country labels are intentionally not inputs to the ranking score.
- Previously verified endpoint memory is kept ahead of other candidates in the independent domestic ordering.
- Relevant code: `lib/main.dart`, `lib/nnie_core.dart`; focused tests: `test/nnie_core_test.dart`.
- The IPv4 ASN membership helper explicitly rejects IPv6. IPv6 reachability has separate evidence in NNIE core, but equivalent Iranian IPv6 ASN classification is not present in the inspected path. Next investigate authoritative IPv6 allocation data before adding a bounded, classification-only index; never infer IPv6 ownership from country labels or broaden scanning.

## Validation status at checkpoint refresh
- Implementation commit `7b9da526df4f81a8faf2d7d6ae2e213506c88550`, CI run 1919 (run ID `44955779075`): source guard, dependency setup, Flutter unit tests, and Dart analysis were observed completed successfully. Android arm64 release APK build was still in progress at last inspection. No artifact had been listed yet; no completed Build is claimed.
- Latest branch HEAD before this documentation refresh was `199b4987db229e40f0c68db35d9d06400d0027f3`, a documentation-only checkpoint commit after the implementation commit. Its CI run 1921 (run ID `44955823669`) was queued/pending at last inspection and had no jobs yet.
- Recheck both runs and the exact current HEAD. The next checkpoint-only commit will itself trigger another CI run; do not infer its outcome from the earlier run.
- No device/operator network validation has been performed. CI cannot prove real connectivity on Iranian mobile/fixed operators.

## Guardrails
- Preserve all configured IP Clean sources, ranges, ports, and scan capabilities; do not impose arbitrary caps.
- Keep IPv4 and IPv6 routing/reachability support; do not claim IPv6 ASN classification exists until implemented and tested.
- Do not add Gemini, Grok, paid APIs, or API-key-dependent AI services.
- Never claim install readiness until the exact final source commit passes source guards, Flutter tests, Dart analysis, Android arm64 release build, and APK artifact verification (including checksum and package inspection).
- Do not merge to `main` or cancel active CI runs without explicit authorization.

## Next actions
1. Re-resolve branch HEAD and fetch its `CONTINUATION.md` before acting.
2. Inspect CI run 1919 through completion; its APK build is the current blocker. Inspect logs if it fails.
3. Inspect queued run 1921 and the run triggered by this checkpoint refresh.
4. If a build fails, fix only the demonstrated cause, commit to this feature branch, and rerun CI.
5. If APK build succeeds, verify artifact name, size, SHA-256, ABI/package contents; do not call it install-ready until all checks pass.
6. Continue VPN audit: DNS leak/timeout handling, routing policy wiring, failover lifecycle, IPv4/IPv6 behavior, Android VPN service lifecycle, and real national/global traffic evidence.
7. Add evidence-backed IPv6 ASN classification only after identifying reliable IPv6 prefixes; add unit tests for IPv6 CIDR parsing and matching before integrating.
