import 'dart:async';
import 'dart:convert';

/// Decodes public VPN source responses without buffering ordinary URI lists.
/// Base64 payloads retain the legacy whole-payload normalization path.
Stream<String> decodeConfigSourceLines(
  Stream<List<int>> bytes, {
  required RegExp linkRegex,
}) async* {
  final sourceLines = const Utf8Decoder(allowMalformed: true)
      .bind(bytes)
      .transform(const LineSplitter());
  final iterator = StreamIterator<String>(sourceLines);
  final prefix = <String>[];
  final base64Line = RegExp(r'^[A-Za-z0-9+/=_-]+$');
  var mode = 'plain';
  var encodedLength = 0;

  try {
    // Read only enough prefix to distinguish plain links, HTML, and Base64.
    while (await iterator.moveNext()) {
      final line = iterator.current.trim();
      if (line.isEmpty) continue;
      prefix.add(line);
      final lower = line.toLowerCase();
      if (lower.contains('<html') || lower.contains('<!doctype')) {
        mode = 'html';
        break;
      }
      if (line.contains('://')) {
        mode = 'plain';
        break;
      }
      if (!base64Line.hasMatch(line)) {
        mode = 'plain';
        break;
      }
      encodedLength += line.length;
      if (encodedLength >= 16) {
        mode = 'base64';
        break;
      }
    }

    if (mode == 'base64') {
      // Preserve established Base64 normalization semantics. This branch
      // buffers only Base64 payloads; ordinary URI lists remain network-streamed.
      final encoded = StringBuffer();
      for (final line in prefix) {
        encoded.write(line);
      }
      while (await iterator.moveNext()) {
        encoded.write(iterator.current.trim());
      }
      var b64 = encoded
          .toString()
          .replaceAll(RegExp(r'[^A-Za-z0-9+/=_-]'), '')
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      if (b64.length % 4 == 1) {
        b64 = b64.substring(0, b64.length - 1);
      }
      while (b64.length % 4 != 0) {
        b64 += '=';
      }
      final decoded = utf8.decode(
        base64.decode(b64),
        allowMalformed: true,
      );
      yield* Stream<String>.value(decoded).transform(const LineSplitter());
    } else if (mode == 'html') {
      Iterable<String> extract(String line) => linkRegex
          .allMatches(line.replaceAll('&amp;', '&'))
          .map((match) => match.group(0)!);
      for (final line in prefix) {
        for (final link in extract(line)) {
          yield link;
        }
      }
      while (await iterator.moveNext()) {
        for (final link in extract(iterator.current)) {
          yield link;
        }
      }
    } else {
      for (final line in prefix) {
        yield line;
      }
      while (await iterator.moveNext()) {
        yield iterator.current.trim();
      }
    }
  } finally {
    await iterator.cancel();
  }
}
