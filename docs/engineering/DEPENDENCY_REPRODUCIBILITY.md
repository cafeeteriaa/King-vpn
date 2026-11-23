# Flutter dependency reproducibility — KING VPN

## Evidence

GitHub Actions run 2237 (`45154539745`) completed successfully for exact source commit `6364b62f8d9947d7f6140fdc13d4e7d8096eb5f9`. Its full-source artifact `king-vpn-full-source-2237` (artifact ID `14807149342`) supplied the generated Flutter manifest and lockfile.

The dependency snapshot contains 116 packages, including 111 hosted packages with SHA-256 archive checksums. Toolchain provenance is Flutter 3.50.1, Dart 3.14.0, and Java 21.0.13. The checked-in manifest preserves the dependency names and constraints from that successful build.

## CI behavior

The Android build pins Flutter to 3.50.1, copies the checked-in manifest and compressed lockfile into the generated Flutter host, checks the decompressed lockfile SHA-256, and runs `flutter pub get --enforce-lockfile`. Per-run unconstrained `flutter pub add` resolution is removed.

## Acceptance boundary

This change is not marked TESTED or BUILT until a fresh exact-head GitHub Actions run succeeds. The dependency snapshot does not establish license compatibility, SBOM completeness, CVE status, production signing, or Android device/network acceptance. Those remain separate gates.
