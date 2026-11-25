import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Sparse, rebuildable byte-offset index for a newline-delimited inventory.
/// The snapshot remains authoritative; stale or damaged indexes are rebuilt.
class FreshResourceOffsetIndex {
  FreshResourceOffsetIndex._();

  static const int stride = 256;
  static const int _headerSize = 36;
  static const List<int> _magic = <int>[
    0x4b, 0x46, 0x52, 0x49, 0x44, 0x58, 0x30, 0x31,
  ];

  static Future<FreshResourceIndexPage> readPage({
    required File snapshot,
    required File index,
    required int offset,
    required int limit,
    required String? Function(String) normalize,
  }) async {
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    if (!await snapshot.exists()) {
      return FreshResourceIndexPage(items: const <String>[], hasMore: false);
    }

    var header = await _readValidHeader(snapshot, index);
    header ??= await _rebuild(snapshot, index, normalize);
    if (offset >= header.count) {
      return FreshResourceIndexPage(items: const <String>[], hasMore: false);
    }

    final slot = offset ~/ stride;
    final indexFile = await index.open();
    int startByte;
    try {
      await indexFile.setPosition(_headerSize + slot * 8);
      final encoded = await indexFile.read(8);
      if (encoded.length != 8) {
        throw const FormatException('Truncated resource offset index');
      }
      startByte = ByteData.sublistView(Uint8List.fromList(encoded))
          .getUint64(0, Endian.little);
    } finally {
      await indexFile.close();
    }

    if (startByte >= header.snapshotLength) {
      header = await _rebuild(snapshot, index, normalize);
      if (offset >= header.count) {
        return FreshResourceIndexPage(items: const <String>[], hasMore: false);
      }
      final retry = await index.open();
      try {
        await retry.setPosition(_headerSize + slot * 8);
        final encoded = await retry.read(8);
        if (encoded.length != 8) {
          throw const FormatException('Rebuilt resource offset index is truncated');
        }
        startByte = ByteData.sublistView(Uint8List.fromList(encoded))
            .getUint64(0, Endian.little);
      } finally {
        await retry.close();
      }
    }

    final skip = offset - slot * stride;
    final items = <String>[];
    var validSeen = 0;
    var hasMore = false;
    await for (final line in snapshot
        .openRead(startByte)
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final link = normalize(line);
      if (link == null) continue;
      if (validSeen < skip) {
        validSeen++;
        continue;
      }
      if (items.length == limit) {
        hasMore = true;
        break;
      }
      items.add(link);
      validSeen++;
    }
    return FreshResourceIndexPage(
      items: List<String>.unmodifiable(items),
      hasMore: hasMore,
    );
  }

  static Future<_IndexHeader?> _readValidHeader(
    File snapshot,
    File index,
  ) async {
    if (!await index.exists()) return null;
    final snapshotStat = await snapshot.stat();
    final input = await index.open();
    try {
      if (await input.length() < _headerSize) return null;
      final bytes = await input.read(_headerSize);
      if (bytes.length != _headerSize) return null;
      for (var i = 0; i < _magic.length; i++) {
        if (bytes[i] != _magic[i]) return null;
      }
      final data = ByteData.sublistView(Uint8List.fromList(bytes));
      final storedStride = data.getUint32(8, Endian.little);
      final snapshotLength = data.getUint64(12, Endian.little);
      final modifiedMicros = data.getUint64(20, Endian.little);
      final count = data.getUint64(28, Endian.little);
      final entryCount = (count + stride - 1) ~/ stride;
      final expectedLength = _headerSize + entryCount * 8;
      if (storedStride != stride ||
          snapshotLength != snapshotStat.size ||
          modifiedMicros != snapshotStat.modified.microsecondsSinceEpoch ||
          await input.length() != expectedLength) {
        return null;
      }
      return _IndexHeader(snapshotLength: snapshotLength, count: count);
    } on FileSystemException {
      return null;
    } finally {
      await input.close();
    }
  }

  static Future<_IndexHeader> _rebuild(
    File snapshot,
    File index,
    String? Function(String) normalize,
  ) async {
    final snapshotStat = await snapshot.stat();
    final temp = File(index.path + '.tmp-$pid-' +
        DateTime.now().microsecondsSinceEpoch.toString());
    RandomAccessFile? output;
    var count = 0;
    var byteOffset = 0;
    var lineStart = 0;
    final lineBytes = BytesBuilder(copy: false);

    Future<void> consumeLine() async {
      final decoded = utf8.decode(lineBytes.takeBytes());
      if (normalize(decoded) != null) {
        if (count % stride == 0) {
          final encoded = ByteData(8)..setUint64(0, lineStart, Endian.little);
          await output!.writeFrom(encoded.buffer.asUint8List());
        }
        count++;
      }
    }

    try {
      output = await temp.open(mode: FileMode.write);
      await output.writeFrom(List<int>.filled(_headerSize, 0));
      await for (final chunk in snapshot.openRead()) {
        for (final byte in chunk) {
          if (byte == 0x0a) {
            await consumeLine();
            lineStart = byteOffset + 1;
          } else {
            lineBytes.addByte(byte);
          }
          byteOffset++;
        }
      }
      if (lineBytes.length > 0) await consumeLine();

      final header = ByteData(_headerSize);
      header.buffer.asUint8List().setAll(0, _magic);
      header.setUint32(8, stride, Endian.little);
      header.setUint64(12, snapshotStat.size, Endian.little);
      header.setUint64(20, snapshotStat.modified.microsecondsSinceEpoch, Endian.little);
      header.setUint64(28, count, Endian.little);
      await output.setPosition(0);
      await output.writeFrom(header.buffer.asUint8List());
      await output.flush();
      await output.close();
      output = null;
      await temp.rename(index.path);
      return _IndexHeader(snapshotLength: snapshotStat.size, count: count);
    } catch (_) {
      try {
        await output?.close();
      } catch (_) {
        // Preserve the original index-build failure.
      }
      rethrow;
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } on FileSystemException {
        // Best-effort cleanup only.
      }
    }
  }
}

class FreshResourceIndexPage {
  const FreshResourceIndexPage({required this.items, required this.hasMore});
  final List<String> items;
  final bool hasMore;
}

class _IndexHeader {
  const _IndexHeader({required this.snapshotLength, required this.count});
  final int snapshotLength;
  final int count;
}
