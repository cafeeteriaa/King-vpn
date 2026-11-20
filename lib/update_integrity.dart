import 'dart:io';

import 'package:crypto/crypto.dart';

/// Initial downloads must be the exact APK asset in the official repository;
/// GitHub's asset hosts are accepted only after a trusted release redirect.
bool isAllowedUpdateDownloadUri(
  Uri uri, {
  bool allowReleaseAssetHosts = false,
}) {
  if (uri.scheme.toLowerCase() != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      uri.hasQuery ||
      uri.hasFragment) {
    return false;
  }

  final host = uri.host.toLowerCase();
  if (host == 'github.com') {
    // The update manifest is owner-managed. Accept only the APK asset from
    // this repository, not arbitrary GitHub repositories or arbitrary files.
    return RegExp(
      r'^/cafeeteriaa/king-vpn/releases/download/[^/]+/king-vpn[.]apk

/// Validates an expected SHA-256 digest and compares it with downloaded bytes.
/// Invalid or missing digests always fail closed.
bool verifySha256Bytes(List<int> bytes, String expectedHex) {
  final expected = expectedHex.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) return false;
  final actual = sha256.convert(bytes).toString();
  if (actual.length != expected.length) return false;
  var difference = 0;
  for (var i = 0; i < actual.length; i++) {
    difference |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return difference == 0;
}

/// Streams a downloaded APK from disk so large update files do not need to be
/// loaded into memory. Missing or malformed digests fail closed.
Future<bool> verifySha256File(File file, String expectedHex) async {
  final expected = expectedHex.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) return false;
  if (!await file.exists()) return false;
  final actual = await sha256.bind(file.openRead()).first;
  final actualHex = actual.toString();
  if (actualHex.length != expected.length) return false;
  var difference = 0;
  for (var i = 0; i < actualHex.length; i++) {
    difference |= actualHex.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return difference == 0;
}

/// Resolve one HTTP redirect and fail closed unless the next hop is an
/// allowlisted HTTPS GitHub release host. Relative locations are supported.
Uri? resolveAllowedUpdateRedirect(Uri currentUri, String? location) {
  final value = location?.trim();
  if (value == null || value.isEmpty) return null;
  try {
    final resolved = currentUri.resolve(value);
    return isAllowedUpdateDownloadUri(resolved, allowReleaseAssetHosts: true)
        ? resolved
        : null;
  } on FormatException {
    return null;
  }
}
,
      caseSensitive: false,
    ).hasMatch(uri.path);
  }

  // GitHub's signed asset hosts are accepted only as redirect destinations;
  // a remote manifest cannot point directly at an unrelated asset.
  return allowReleaseAssetHosts &&
      (host == 'release-assets.githubusercontent.com' ||
          host == 'objects.githubusercontent.com');
}

/// Validates an expected SHA-256 digest and compares it with downloaded bytes.
/// Invalid or missing digests always fail closed.
bool verifySha256Bytes(List<int> bytes, String expectedHex) {
  final expected = expectedHex.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) return false;
  final actual = sha256.convert(bytes).toString();
  if (actual.length != expected.length) return false;
  var difference = 0;
  for (var i = 0; i < actual.length; i++) {
    difference |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return difference == 0;
}

/// Streams a downloaded APK from disk so large update files do not need to be
/// loaded into memory. Missing or malformed digests fail closed.
Future<bool> verifySha256File(File file, String expectedHex) async {
  final expected = expectedHex.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) return false;
  if (!await file.exists()) return false;
  final actual = await sha256.bind(file.openRead()).first;
  final actualHex = actual.toString();
  if (actualHex.length != expected.length) return false;
  var difference = 0;
  for (var i = 0; i < actualHex.length; i++) {
    difference |= actualHex.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return difference == 0;
}

/// Resolve one HTTP redirect and fail closed unless the next hop is an
/// allowlisted HTTPS GitHub release host. Relative locations are supported.
Uri? resolveAllowedUpdateRedirect(Uri currentUri, String? location) {
  final value = location?.trim();
  if (value == null || value.isEmpty) return null;
  try {
    final resolved = currentUri.resolve(value);
    return isAllowedUpdateDownloadUri(resolved) ? resolved : null;
  } on FormatException {
    return null;
  }
}
