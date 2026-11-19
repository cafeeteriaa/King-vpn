import 'dart:io';

import 'package:crypto/crypto.dart';

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
