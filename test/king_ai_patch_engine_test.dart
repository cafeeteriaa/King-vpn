import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/king_ai_patch_engine.dart';

void main() {
  group('KingAiPatchEngine', () {
    String hashOf(String value) => sha256.convert(utf8.encode(value)).toString();

    test('applies multiple exact operations to a large source without rewriting it', () {
      final original = List<String>.generate(
        6000,
        (index) => 'line-$index: original-value',
      ).join('\n');
      final updated = KingAiPatchEngine.apply(
        original: original,
        baseSha256: hashOf(original),
        operations: [
          {'find': 'line-12: original-value', 'replace': 'line-12: updated-value'},
          {'find': 'line-5999: original-value', 'replace': 'line-5999: updated-value'},
        ],
      );
      expect(updated, contains('line-12: updated-value'));
      expect(updated, contains('line-5999: updated-value'));
      expect(updated, contains('line-3000: original-value'));
    });

    test('rejects stale base hashes before changing source', () {
      expect(
        () => KingAiPatchEngine.apply(
          original: 'before',
          baseSha256: hashOf('different'),
          operations: [{'find': 'before', 'replace': 'after'}],
        ),
        throwsFormatException,
      );
    });

    test('rejects missing or ambiguous anchors', () {
      for (final source in ['nothing here', 'alpha beta alpha']) {
        expect(
          () => KingAiPatchEngine.apply(
            original: source,
            baseSha256: hashOf(source),
            operations: [{'find': 'alpha', 'replace': 'omega'}],
          ),
          throwsFormatException,
        );
      }
    });

    test('applies operations sequentially and permits an anchor created earlier', () {
      const source = 'first';
      final result = KingAiPatchEngine.apply(
        original: source,
        baseSha256: hashOf(source),
        operations: [
          {'find': 'first', 'replace': 'second'},
          {'find': 'second', 'replace': 'third'},
        ],
      );
      expect(result, 'third');
    });

    test('rejects empty anchors and malformed operations', () {
      for (final operation in [
        {'find': '', 'replace': 'x'},
        {'find': 'x'},
        'not-an-object',
      ]) {
        expect(
          () => KingAiPatchEngine.apply(
            original: 'x',
            baseSha256: hashOf('x'),
            operations: [operation],
          ),
          throwsFormatException,
        );
      }
    });
  });
}
