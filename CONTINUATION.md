# King VPN — mainline continuation checkpoint

## Source of truth (refresh from GitHub at every continuation)
- Repository: `cafeeteriaa/King-vpn`
- Default branch: `main`
- Main HEAD at checkpoint: `c43d325f9803d4f6306415e511f6790deff9d87e`
- Mainline continuation branch: `codex/continuation-mainline-20261122`, created directly from that exact main commit.
- Main does not currently contain `CONTINUATION.md`; this file is being introduced on the continuation branch through a draft PR, not committed directly to main.
- Existing branch `fix/domestic-rank-evidence-20261122` is a separate long-lived line. Compared with main it is 103 commits ahead and 0 behind at inspection; it is not the current mainline HEAD.
- Existing PR #41 is draft, open, and targets `fix/domestic-evidence-priority-20261122`, not main. Do not merge it or retarget it without reviewing its full 103-commit divergence and tests. Its latest head was `0825a029250a8b3511d83f5a4f18cf4a523d83b5`.

## Latest mainline changes inspected
- Latest main commit `c43d325f9803d4f6306415e511f6790deff9d87e`: adds a source guard that verifies `autoScanSheet` forwards live `isVpnActive` and `isVpnWanted` predicates to `autoScanRun`.
- Relevant scanner source: `lib/auto_scanners.dart`; the scanner refuses to start while VPN is active or wanted, rechecks during the scan, discards partial results on cancellation, and closes TLS/raw sockets in `finally`.
- DNS cancellation cleanup fix is present in main history: `b5ac93c2fecc33af11ce60f809ea7127f9d03807` (guarantee UDP socket closure on cancellation cleanup).
- Main contains NNIE, national-engine, DNS, NAT IP scanning and focused tests. The old branch's IPv4-only Iranian ASN classification change is not in main; do not assume it is shipped.

## CI / build evidence
- Main commit `c43d325f9803d4f6306415e511f6790deff9d87e`: GitHub Actions run 1393 (run ID `44785612381`) completed successfully.
- All workflow steps completed successfully, including Python source guards, Flutter unit tests, Dart analysis, Android arm64 release APK build, APK size/hash report, source ZIP, symbols, and APK artifact upload.
- APK artifact: `king-vpn-arm64-release-1393`, artifact ID `14654661908`, archive size 49,012,358 bytes, GitHub artifact archive digest `sha256:602e25b28ce81e0f7d001531222bf47261ae29bdd223eae0dded83719da29ab8`. This digest is for the downloaded artifact ZIP, not the inner APK. The workflow step reports the APK's own SHA-256; inspect that summary/log before quoting the APK digest.
- Workflow explicitly reports the APK is signed with a generated Flutter debug key, not a production signing key. Thus CI proves an arm64 release-mode APK was built, not that a production-signed distribution is ready.
- Separate feature-branch run 1919 (run ID `44955779075`) was still in progress at last inspection, on old implementation commit `7b9da526df4f81a8faf2d7d6ae2e213506c88550`; unit tests and Dart analysis had passed, arm64 APK build was still running. Do not cancel it.
- Runs 1922/1923 were pending for the old feature branch checkpoint `0825a029250a8b3511d83f5a4f18cf4a523d83b5`; they do not validate main.
- No real device/operator connectivity test has been performed. CI does not prove access on Iranian mobile/fixed networks.

## Engineering guardrails
- Preserve IP Clean sources, ranges, ports and scan capabilities; avoid arbitrary limits unless justified by device-safety and tested.
- Preserve IPv4 and IPv6 routing/reachability. Do not infer Iranian IPv6 ASN ownership from country labels.
- Rank domestic endpoints using observed successful national traffic first; ASN/transport/CDN hints remain weaker evidence.
- DNS replies alone are not proof of data-path reachability; tunnel traffic must be verified separately.
- Do not add Gemini, Grok, paid APIs, or API-key-dependent AI services.
- Never call a build install-ready until the exact final source commit passes source guards, Flutter tests, Dart analysis, arm64 release build, APK artifact/package/checksum verification. A debug-key build is not a production-signed release.
- Do not merge to main or cancel active CI runs without explicit authorization.

## Next work
1. Resolve the new branch HEAD and CI run triggered by this checkpoint PR.
2. Audit the live VPN path in `lib/main.dart`, `lib/national_engine.dart`, `lib/network_health.dart`, and Android VPN plugin patching for actual route/DNS policy application, not just policy selection.
3. Trace DNS lifecycle end-to-end: cancellation, socket disposal, IPv4/IPv6 resolver handling, DNS leak prevention, and behavior across network changes.
4. Trace failover from tunnel drop through server selection and reconnection; verify stale timers and concurrent connect/disconnect requests cannot race.
5. Review Android service/plugin lifecycle and the previously observed `vpn/bg` MissingPluginException class of failure.
6. Add targeted pure tests/source guards for each demonstrated defect; run the actual CI workflow on the exact commit.
7. Inspect and verify the APK's inner file, ABI, package metadata, APK SHA-256 and signing status before making any installation claim.
8. Validate national/global traffic behavior on real networks separately; no operator-level claims without such evidence.
