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
