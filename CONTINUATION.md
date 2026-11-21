# King VPN — continuation checkpoint

## Source of truth
- Repository: `cafeeteriaa/King-vpn`
- Active development branch: `fix/domestic-rank-evidence-20261122`
- Current implementation commit before this checkpoint refresh: `7b9da526df4f81a8faf2d7d6ae2e213506c88550`
- Parent implementation commit: `6d184b1ff37ca1058807f223efa4e14bcc3cdde7`
- PR: #41, draft, targeting `fix/domestic-evidence-priority-20261122` (the exact parent commit), not `main`.
- Never commit directly to `main`; do not merge the draft PR until all validation gates pass.

## Current work
- Removed unsupported national-mode ranking promotions based only on source-list names or the `IR` country label.
- Evidence rank is: previously verified national traffic > Iranian ASN assignment > Reality transport hint > CDN hint > other.
- The independent domestic ordering still places remembered endpoints with previously verified national traffic first.
- Changed files in this branch delta: `CONTINUATION.md`, `lib/main.dart`, `lib/nnie_core.dart`, `test/nnie_core_test.dart`.
- Current branch is exactly one commit ahead of its parent checkpoint branch and has no behind commits.

## Validation status
- Exact head `7b9da526df4f81a8faf2d7d6ae2e213506c88550`: GitHub Actions run 1919 (run ID `44955779075`) was observed in progress. Build job ID `137003431545`; checkout passed and source-guard step was running at last inspection. No test, analysis, APK build, or artifact success is claimed yet.
- Previous checkpoint references CI run numbers 1915/1916. The available workflow-run lookup did not return a run for parent commit `6d184b1ff37ca1058807f223efa4e14bcc3cdde7`; do not rely on the old in-progress claim without a fresh Actions check.
- No device-level network/VPN validation has been performed.

## Guardrails
- Preserve all configured IP Clean sources, ranges, ports, and scan capabilities; do not impose arbitrary caps.
- Keep IPv4 and IPv6 support.
- Do not add Gemini, Grok, paid APIs, or API-key-dependent AI services.
- Do not claim a release is install-ready until the exact final source commit passes source guards, Flutter unit tests, analysis, Android arm64 release build, and artifact verification.
- No device/operator test has been done; CI does not establish real-world connectivity on Iranian networks.
- Do not cancel active CI runs.

## Next actions
1. Re-resolve the current branch HEAD after this checkpoint update.
2. Inspect the new Actions run for that exact HEAD; allow existing runs to finish without cancellation.
3. Inspect job steps/logs and fix only demonstrated failures.
4. Verify APK artifact presence, size, SHA-256, and package contents after successful build.
5. Continue VPN audit: real routing, DNS, failover, IPv4/IPv6, Android VPN lifecycle, and national/global route evidence.
6. Keep this file synchronized with verified outcomes and the next concrete task.
