import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A lossless slice of one complete source file for finite model contexts.
class KingAiSourceChunk {
  const KingAiSourceChunk({
    required this.path,
    required this.content,
    required this.chunkIndex,
    required this.chunkCount,
    required this.baseSha256,
  });

  final String path;
  final String content;
  final int chunkIndex;
  final int chunkCount;
  final String baseSha256;

  Map<String, Object> toJson() => {
        'path': path,
        'chunkIndex': chunkIndex,
        'chunkCount': chunkCount,
        'baseSha256': baseSha256,
        'content': content,
      };
}

class KingAiSourceChunker {
  KingAiSourceChunker._();

  /// Splits by Unicode scalar values, never dropping or splitting a surrogate
  /// pair. Concatenating returned chunks reproduces the original source.
  static List<KingAiSourceChunk> split({
    required String path,
    required String source,
    int maxChars = 6000,
  }) {
    if (maxChars < 1) {
      throw ArgumentError.value(maxChars, 'maxChars', 'Must be positive');
    }
    final baseSha256 = sha256.convert(utf8.encode(source)).toString();
    if (source.isEmpty) {
      return [
        KingAiSourceChunk(
          path: path,
          content: '',
          chunkIndex: 0,
          chunkCount: 1,
          baseSha256: baseSha256,
        ),
      ];
    }

    final parts = <String>[];
    var buffer = StringBuffer();
    var length = 0;
    for (final rune in source.runes) {
      buffer.writeCharCode(rune);
      length++;
      if (length >= maxChars) {
        parts.add(buffer.toString());
        buffer = StringBuffer();
        length = 0;
      }
    }
    if (length > 0) parts.add(buffer.toString());

    return List<KingAiSourceChunk>.generate(
      parts.length,
      (index) => KingAiSourceChunk(
        path: path,
        content: parts[index],
        chunkIndex: index,
        chunkCount: parts.length,
        baseSha256: baseSha256,
      ),
      growable: false,
    );
  }
}
