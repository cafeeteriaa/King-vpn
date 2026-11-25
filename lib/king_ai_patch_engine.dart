import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Applies deterministic, hash-anchored edits without asking the model to
/// regenerate an entire large source file.
class KingAiPatchEngine {
  KingAiPatchEngine._();

  static String apply({
    required String original,
    required String baseSha256,
    required List<Object?> operations,
  }) {
    final actualHash = sha256.convert(utf8.encode(original)).toString();
    if (baseSha256.toLowerCase() != actualHash) {
      throw const FormatException(
        'Patch base hash does not match the exact source file.',
      );
    }
    if (operations.isEmpty) {
      throw const FormatException('Patch must contain at least one operation.');
    }

    var updated = original;
    for (var index = 0; index < operations.length; index++) {
      final operation = operations[index];
      if (operation is! Map ||
          operation['find'] is! String ||
          operation['replace'] is! String) {
        throw FormatException('Malformed patch operation at index $index.');
      }
      final find = operation['find'] as String;
      final replacement = operation['replace'] as String;
      if (find.isEmpty) {
        throw FormatException('Empty patch anchor at index $index.');
      }
      final occurrences = _countOccurrences(updated, find);
      if (occurrences != 1) {
        throw FormatException(
          'Patch anchor at index $index must match exactly once; found $occurrences.',
        );
      }
      updated = updated.replaceFirst(find, replacement);
    }
    return updated;
  }

  static int _countOccurrences(String source, String needle) {
    var count = 0;
    var offset = 0;
    while (true) {
      final index = source.indexOf(needle, offset);
      if (index < 0) return count;
      count++;
      offset = index + needle.length;
    }
  }
}
