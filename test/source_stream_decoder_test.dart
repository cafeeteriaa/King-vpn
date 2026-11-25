import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../lib/source_stream_decoder.dart';

Stream<List<int>> _chunked(String value, int chunkSize) async* {
  final bytes = utf8.encode(value);
  for (var offset = 0; offset < bytes.length; offset += chunkSize) {
    final end = offset + chunkSize < bytes.length
        ? offset + chunkSize
        : bytes.length;
    yield bytes.sublist(offset, end);
  }
}

void main() {
  final linkRegex = RegExp(
    r'(vmess|vless|trojan|ss)://[^\s<>"]+',
    caseSensitive: false,
  );

  test('decodes UTF-8 and plain URI lines across arbitrary byte chunks', () async {
    final lines = await decodeConfigSourceLines(
      _chunked('سلام\nvless://id@example.com:443\nvmess://YWJj\n', 3),
      linkRegex: linkRegex,
    ).toList();

    expect(lines, [
      'سلام',
      'vless://id@example.com:443',
      'vmess://YWJj',
    ]);
  });

  test('preserves multiline Base64 subscription decoding', () async {
    final plain = 'vless://one@example.com:443\nvmess://two@example.com:443';
    final encoded = base64.encode(utf8.encode(plain));
    final wrapped = [
      for (var i = 0; i < encoded.length; i += 12)
        encoded.substring(i, i + 12 < encoded.length ? i + 12 : encoded.length),
    ].join('\n');

    final lines = await decodeConfigSourceLines(
      _chunked(wrapped, 5),
      linkRegex: linkRegex,
    ).toList();

    expect(lines, [
      'vless://one@example.com:443',
      'vmess://two@example.com:443',
    ]);
  });

  test('extracts HTML links and restores escaped ampersands', () async {
    const html =
        '<!DOCTYPE html><html><body><a href="vless://id@example.com:443?x=1&amp;y=2">link</a></body></html>';

    final lines = await decodeConfigSourceLines(
      _chunked(html, 7),
      linkRegex: linkRegex,
    ).toList();

    expect(lines, ['vless://id@example.com:443?x=1&y=2']);
  });

  test('returns no lines for an empty response', () async {
    final lines = await decodeConfigSourceLines(
      const Stream<List<int>>.empty(),
      linkRegex: linkRegex,
    ).toList();

    expect(lines, isEmpty);
  });
}
