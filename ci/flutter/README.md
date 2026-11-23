# Flutter dependency snapshot

Dependency constraints and the lockfile were captured from the successful exact-head GitHub Actions run 2237 for commit `6364b62f8d9947d7f6140fdc13d4e7d8096eb5f9`.

- Flutter: 3.50.1; Dart: 3.14.0; Java: 21.0.13
- Packages: 116 total; 111 hosted packages have SHA-256 archive checksums
- Decompressed `pubspec.lock` SHA-256: `f531c1ac1fcee55851992a6d76bfb3893b7fc4b2508e20e4adb0cedaa0fa159c`

The manifest preserves the dependency names and constraints from that generated build. The lockfile is gzip-compressed; inspect it with `gzip -dc ci/flutter/pubspec.lock.gz`. CI checks the decompressed SHA-256 before `flutter pub get --enforce-lockfile`.

This snapshot provides deterministic package versions and hosted archive checksums. It is not a license, SBOM, vulnerability, or device-compatibility approval.
