import 'package:flutter_test/flutter_test.dart';

import '../lib/king_ai_source_chunker.dart';

void main() {
  group('KingAiSourceChunker', () {
    test('preserves every source character across multiple chunks', () {
      final source = List<String>.generate(
        12000,
        (index) => 'line-$index\n',
      ).join();
      final chunks = KingAiSourceChunker.split(
        path: 'lib/large.dart',
        source: source,
        maxChars: 777,
      );
      expect(chunks.length, greaterThan(1));
      expect(chunks.map((chunk) => chunk.content).join(), source);
      expect(chunks.every((chunk) => chunk.chunkCount == chunks.length), isTrue);
      expect(chunks.every((chunk) => chunk.baseSha256 == chunks.first.baseSha256), isTrue);
      expect(chunks.map((chunk) => chunk.chunkIndex), List<int>.generate(chunks.length, (i) => i));
    });

    test('splits very long single lines without dropping content', () {
      final source = 'x' * 50001;
      final chunks = KingAiSourceChunker.split(
        path: 'lib/one_line.dart',
        source: source,
        maxChars: 1024,
      );
      expect(chunks.length, 49);
      expect(chunks.map((chunk) => chunk.content).join(), source);
    });

    test('preserves non-BMP Unicode characters', () {
      final source = 'الف😀' * 5000;
      final chunks = KingAiSourceChunker.split(
        path: 'lib/unicode.dart',
        source: source,
        maxChars: 19,
      );
      expect(chunks.map((chunk) => chunk.content).join(), source);
      expect(chunks.every((chunk) => !chunk.content.contains('\uFFFD')), isTrue);
    });

    test('represents an empty file and rejects invalid chunk sizes', () {
      final chunks = KingAiSourceChunker.split(
        path: 'lib/empty.dart',
        source: '',
      );
      expect(chunks.single.content, isEmpty);
      expect(chunks.single.chunkCount, 1);
      expect(
        () => KingAiSourceChunker.split(path: 'x', source: 'y', maxChars: 0),
        throwsArgumentError,
      );
    });
  });
}
