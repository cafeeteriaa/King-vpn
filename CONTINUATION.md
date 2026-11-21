# King VPN — continuation checkpoint

## Source of truth
- Repository: `cafeeteriaa/King-vpn`
- Active development branch: `fix/domestic-rank-evidence-20261122`
- Base commit for this checkpoint: `6d184b1ff37ca1058807f223efa4e14bcc3cdde7`
- Resolve the exact current HEAD from the branch ref before making changes; do not infer it from this document.
- Never commit directly to `main`.

## Current work
- Remove the remaining unsupported national-mode ranking promotions based only on source-list names or the `IR` country label.
- Evidence ranking is now: verified national traffic > Iranian ASN assignment > Reality transport hint > CDN hint > other.
- The independent domestic ordering still places remembered endpoints with previously verified national traffic first.
- Relevant files: `lib/nnie_core.dart`, `lib/main.dart`, `test/nnie_core_test.dart`.

## Validation status
- Parent CI run 1915 for `3ae8452054487542832d513bfc494d32cc9a531e`: success.
- CI run 1916 for the parent implementation commit `6d184b1ff37ca1058807f223efa4e14bcc3cdde7`: in progress at last inspection; do not treat it as passed.
- The current rank-evidence change has not yet been tested or built; wait for its GitHub Actions run.
- No device-level network/VPN validation has been performed in this checkpoint.

## Guardrails
- Preserve all configured IP Clean sources, ranges, ports, and scan capabilities; do not impose arbitrary caps.
- Keep IPv4 and IPv6 support.
- Do not add Gemini, Grok, paid APIs, or API-key-dependent AI services.
- Do not claim a release is install-ready until the exact source commit passes unit tests, analysis, and Android release build, and the artifact is verified.
- Do not cancel active CI runs.

## Next actions
1. Inspect current branch HEAD and all active GitHub Actions runs.
2. Wait for run 1916 and the new branch run; inspect failed steps/logs if any.
3. If CI fails, fix only the demonstrated issue and rerun.
4. After CI success, verify APK artifact SHA-256 and package contents.
5. Continue VPN audit, especially real routing/DNS/failover/IPv6 behavior and Android VPN lifecycle; use source evidence and tests, not assumptions.
6. Update this checkpoint with verified outcomes and the next concrete task.
