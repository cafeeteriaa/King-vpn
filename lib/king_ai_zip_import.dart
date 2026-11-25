import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// ZIP extraction for owner-supplied project archives. Rejects traversal,
/// symbolic links, encrypted entries, duplicate paths and ZIP-bomb ratios.
class KingAiZipImport {
  KingAiZipImport._();

  static const int _eocd = 0x06054b50;
  static const int _zip64Eocd = 0x06064b50;
  static const int _zip64Locator = 0x07064b50;
  static const int _central = 0x02014b50;
  static const int _local = 0x04034b50;
  static const int _maxExpansionRatio = 1000;
  static const int _chunkSize = 65536;

  static String? normalizeEntryPath(String raw) {
    if (raw.isEmpty || raw.contains('\u0000')) return null;
    final path = raw.replaceAll('\\', '/');
    if (path.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(path)) return null;
    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') return null;
      parts.add(part);
    }
    return parts.isEmpty ? null : parts.join('/');
  }

  static Future<List<String>> extract({
    required File archiveFile,
    required Directory destination,
  }) async {
    if (!await archiveFile.exists()) {
      throw FileSystemException('ZIP archive does not exist', archiveFile.path);
    }
    final archiveLength = await archiveFile.length();
    if (archiveLength < 22) throw const FormatException('ZIP archive is too short.');
    if (await destination.exists()) {
      if (!await destination.list(followLinks: false).isEmpty) {
        throw FileSystemException('Import destination must be empty', destination.path);
      }
    } else {
      await destination.create(recursive: true);
    }
    final root = await destination.resolveSymbolicLinks();
    final file = await archiveFile.open();
    final extracted = <String>[];
    final seen = <String>{};
    try {
      final tailLength = archiveLength < 65557 ? archiveLength : 65557;
      await file.setPosition(archiveLength - tailLength);
      final tail = await file.read(tailLength);
      final eocdAt = _findSignature(tail, _eocd);
      if (eocdAt < 0 || eocdAt + 22 > tail.length) {
        throw const FormatException('ZIP end record is missing.');
      }
      final end = ByteData.sublistView(tail);
      final disk = end.getUint16(eocdAt + 4, Endian.little);
      final centralDisk = end.getUint16(eocdAt + 6, Endian.little);
      final diskCount16 = end.getUint16(eocdAt + 8, Endian.little);
      final count16 = end.getUint16(eocdAt + 10, Endian.little);
      var count = count16;
      var centralSize = end.getUint32(eocdAt + 12, Endian.little);
      var centralOffset = end.getUint32(eocdAt + 16, Endian.little);
      final commentLength = end.getUint16(eocdAt + 20, Endian.little);
      final absoluteEocd = archiveLength - tailLength + eocdAt;
      var directoryLimit = absoluteEocd;
      if (disk != 0 || centralDisk != 0) {
        throw const FormatException('Multi-disk ZIP is not supported.');
      }
      if (eocdAt + 22 + commentLength != tail.length) {
        throw const FormatException('ZIP end record/comment bounds are invalid.');
      }
      if (diskCount16 == 0xffff || count16 == 0xffff ||
          centralSize == 0xffffffff || centralOffset == 0xffffffff) {
        final locatorOffset = absoluteEocd - 20;
        if (locatorOffset < 0) {
          throw const FormatException('ZIP64 locator is missing.');
        }
        await file.setPosition(locatorOffset);
        final locatorBytes = await file.read(20);
        if (locatorBytes.length != 20) {
          throw const FormatException('ZIP64 locator is truncated.');
        }
        final locator = ByteData.sublistView(locatorBytes);
        if (locator.getUint32(0, Endian.little) != _zip64Locator ||
            locator.getUint32(4, Endian.little) != 0 ||
            locator.getUint32(16, Endian.little) != 1) {
          throw const FormatException('Invalid or multi-disk ZIP64 locator.');
        }
        final zip64Offset = _uint64(locator, 8, 'ZIP64 end-record offset');
        if (zip64Offset + 56 > locatorOffset) {
          throw const FormatException('ZIP64 end-record bounds are invalid.');
        }
        directoryLimit = zip64Offset;
        await file.setPosition(zip64Offset);
        final zip64Bytes = await file.read(56);
        if (zip64Bytes.length != 56) {
          throw const FormatException('ZIP64 end record is truncated.');
        }
        final zip64 = ByteData.sublistView(zip64Bytes);
        final zip64RecordSize = _uint64(zip64, 4, 'ZIP64 end-record size');
        if (zip64.getUint32(0, Endian.little) != _zip64Eocd ||
            zip64RecordSize < 44 || zip64Offset + 12 + zip64RecordSize > locatorOffset ||
            zip64.getUint32(16, Endian.little) != 0 ||
            zip64.getUint32(20, Endian.little) != 0) {
          throw const FormatException('Invalid ZIP64 end record.');
        }
        final entriesOnDisk = _uint64(zip64, 24, 'ZIP64 disk entry count');
        count = _uint64(zip64, 32, 'ZIP64 entry count');
        centralSize = _uint64(zip64, 40, 'ZIP64 central-directory size');
        centralOffset = _uint64(zip64, 48, 'ZIP64 central-directory offset');
        if (entriesOnDisk != count) {
          throw const FormatException('Multi-disk ZIP64 archives are not supported.');
        }
      } else if (diskCount16 != count16) {
        throw const FormatException('Multi-disk ZIP is not supported.');
      }
      if (centralOffset + centralSize > directoryLimit) {
        throw const FormatException('ZIP directory bounds are invalid.');
      }
      await file.setPosition(centralOffset);
      final centralBytes = await file.read(centralSize);
      if (centralBytes.length != centralSize) {
        throw const FormatException('ZIP central directory is truncated.');
      }
      final directory = ByteData.sublistView(centralBytes);
      var cursor = 0;
      for (var i = 0; i < count; i++) {
        if (cursor + 46 > centralBytes.length ||
            directory.getUint32(cursor, Endian.little) != _central) {
          throw FormatException('Malformed ZIP entry ' + i.toString());
        }
        final madeBy = directory.getUint16(cursor + 4, Endian.little);
        final flags = directory.getUint16(cursor + 8, Endian.little);
        final method = directory.getUint16(cursor + 10, Endian.little);
        final crc = directory.getUint32(cursor + 16, Endian.little);
        var compressed = directory.getUint32(cursor + 20, Endian.little);
        var expanded = directory.getUint32(cursor + 24, Endian.little);
        final nameLength = directory.getUint16(cursor + 28, Endian.little);
        final extraLength = directory.getUint16(cursor + 30, Endian.little);
        final commentSize = directory.getUint16(cursor + 32, Endian.little);
        final diskStart = directory.getUint16(cursor + 34, Endian.little);
        final external = directory.getUint32(cursor + 38, Endian.little);
        var localOffset = directory.getUint32(cursor + 42, Endian.little);
        final recordLength = 46 + nameLength + extraLength + commentSize;
        if (cursor + recordLength > centralBytes.length) {
          throw const FormatException('ZIP central directory entry is truncated.');
        }
        if ((flags & 1) != 0) throw const FormatException('Encrypted ZIP entry rejected.');
        if (method != 0 && method != 8) {
          throw FormatException('Unsupported ZIP compression method: ' + method.toString());
        }
        final nameBytes = centralBytes.sublist(cursor + 46, cursor + 46 + nameLength);
        final extraBytes = centralBytes.sublist(
          cursor + 46 + nameLength,
          cursor + 46 + nameLength + extraLength,
        );
        final rawName = (flags & 0x800) != 0
            ? utf8.decode(nameBytes, allowMalformed: false)
            : latin1.decode(nameBytes);
        if (diskStart != 0 && diskStart != 0xffff) {
          throw const FormatException('Multi-disk ZIP entry is not supported.');
        }
        if (compressed == 0xffffffff || expanded == 0xffffffff ||
            localOffset == 0xffffffff || diskStart == 0xffff) {
          final zip64 = _zip64ExtraValues(
            extraBytes,
            needExpanded: expanded == 0xffffffff,
            needCompressed: compressed == 0xffffffff,
            needOffset: localOffset == 0xffffffff,
            needDisk: diskStart == 0xffff,
          );
          var index = 0;
          if (expanded == 0xffffffff) expanded = zip64[index++];
          if (compressed == 0xffffffff) compressed = zip64[index++];
          if (localOffset == 0xffffffff) localOffset = zip64[index++];
          if (diskStart == 0xffff && zip64[index] != 0) {
            throw const FormatException('Multi-disk ZIP64 entry is not supported.');
          }
        }
        final path = normalizeEntryPath(rawName);
        cursor += recordLength;
        if (path == null) throw FormatException('Unsafe ZIP path: ' + rawName);
        if (!seen.add(path)) throw FormatException('Duplicate normalized ZIP path: ' + path);
        final unixHost = (madeBy >> 8) == 3;
        final mode = (external >> 16) & 0xffff;
        final unixType = mode & 0xf000;
        if (unixHost && unixType == 0xa000) {
          throw FormatException('ZIP symbolic link rejected: ' + path);
        }
        if (unixHost && unixType != 0 && unixType != 0x8000 && unixType != 0x4000) {
          throw FormatException('ZIP special filesystem entry rejected: ' + path);
        }
        final isDirectory = rawName.endsWith('/') ||
            rawName.endsWith(r'\') || (unixHost && (mode & 0xf000) == 0x4000);
        if (isDirectory) {
          final dir = Directory(_join(destination.path, path));
          await dir.create(recursive: true);
          if (!_inside(root, await dir.resolveSymbolicLinks())) {
            throw FormatException('ZIP directory escaped import root: ' + path);
          }
          continue;
        }
        if (expanded > 0 &&
            (compressed == 0 || expanded / compressed > _maxExpansionRatio)) {
          throw FormatException('Suspicious ZIP expansion ratio: ' + path);
        }
        if (localOffset + 30 > centralOffset) {
          throw FormatException('Invalid local ZIP offset: ' + path);
        }
        await file.setPosition(localOffset);
        final localBytes = await file.read(30);
        if (localBytes.length != 30) throw FormatException('Truncated local header: ' + path);
        final local = ByteData.sublistView(localBytes);
        if (local.getUint32(0, Endian.little) != _local) {
          throw FormatException('Invalid local header: ' + path);
        }
        final localFlags = local.getUint16(6, Endian.little);
        final localMethod = local.getUint16(8, Endian.little);
        final localNameLength = local.getUint16(26, Endian.little);
        final localExtraLength = local.getUint16(28, Endian.little);
        if (localFlags != flags || localMethod != method) {
          throw FormatException('ZIP local/central metadata mismatch: ' + path);
        }
        final localNameBytes = await file.read(localNameLength);
        if (localNameBytes.length != localNameLength) {
          throw FormatException('Truncated local filename: ' + path);
        }
        final localName = (localFlags & 0x800) != 0
            ? utf8.decode(localNameBytes, allowMalformed: false)
            : latin1.decode(localNameBytes);
        if (normalizeEntryPath(localName) != path) {
          throw FormatException('ZIP local/central filename mismatch: ' + path);
        }
        final localExtra = await file.read(localExtraLength);
        if (localExtra.length != localExtraLength) {
          throw FormatException('Truncated local extra data: ' + path);
        }
        final dataOffset = localOffset + 30 + localNameLength + localExtraLength;
        if (dataOffset + compressed > centralOffset ||
            dataOffset + compressed > archiveLength) {
          throw FormatException('ZIP data bounds invalid: ' + path);
        }
        final output = File(_join(destination.path, path));
        await output.parent.create(recursive: true);
        if (!_inside(root, await output.parent.resolveSymbolicLinks())) {
          throw FormatException('ZIP file escaped import root: ' + path);
        }
        await _writeEntry(
          file: file, output: output, offset: dataOffset,
          compressed: compressed, expanded: expanded, expectedCrc: crc,
          method: method,
        );
        extracted.add(path);
      }
      if (cursor != centralBytes.length) {
        throw const FormatException('Unexpected trailing central-directory bytes.');
      }
      return extracted;
    } catch (_) {
      if (await destination.exists()) await destination.delete(recursive: true);
      rethrow;
    } finally {
      await file.close();
    }
  }

  static Future<void> _writeEntry({
    required RandomAccessFile file,
    required File output,
    required int offset,
    required int compressed,
    required int expanded,
    required int expectedCrc,
    required int method,
  }) async {
    final source = _readRange(file, offset, compressed);
    final decoded = method == 8 ? ZLibDecoder(raw: true).bind(source) : source;
    final sink = output.openWrite();
    var size = 0;
    var crc = 0xffffffff;
    try {
      await for (final chunk in decoded) {
        size += chunk.length;
        if (size > expanded) {
          throw FormatException('ZIP entry exceeded declared size: ' + output.path);
        }
        crc = _crc32(crc, chunk);
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (size != expanded || ((crc ^ 0xffffffff) & 0xffffffff) != expectedCrc) {
      await output.delete().catchError((_) => output);
      throw FormatException('ZIP entry size/CRC mismatch: ' + output.path);
    }
  }

  static Stream<List<int>> _readRange(
      RandomAccessFile file, int offset, int length) async* {
    await file.setPosition(offset);
    var remaining = length;
    while (remaining > 0) {
      final bytes = await file.read(remaining < _chunkSize ? remaining : _chunkSize);
      if (bytes.isEmpty) throw const FormatException('ZIP data truncated.');
      remaining -= bytes.length;
      yield bytes;
    }
  }

  static int _uint64(ByteData data, int offset, String field) {
    final low = data.getUint32(offset, Endian.little);
    final high = data.getUint32(offset + 4, Endian.little);
    if (high > 0x7fffffff) {
      throw FormatException('$field exceeds the platform integer range.');
    }
    return (high << 32) | low;
  }

  static List<int> _zip64ExtraValues(
    Uint8List extra, {
    required bool needExpanded,
    required bool needCompressed,
    required bool needOffset,
    required bool needDisk,
  }) {
    var cursor = 0;
    while (cursor + 4 <= extra.length) {
      final header = ByteData.sublistView(extra, cursor);
      final id = header.getUint16(0, Endian.little);
      final length = header.getUint16(2, Endian.little);
      final start = cursor + 4;
      if (start + length > extra.length) {
        throw const FormatException('Malformed ZIP extra-field bounds.');
      }
      if (id == 0x0001) {
        final values = <int>[];
        var position = start;
        final end = start + length;
        void take64(String field) {
          if (position + 8 > end) {
            throw FormatException('ZIP64 extra field is missing $field.');
          }
          values.add(_uint64(ByteData.sublistView(extra), position, field));
          position += 8;
        }
        if (needExpanded) take64('expanded size');
        if (needCompressed) take64('compressed size');
        if (needOffset) take64('local-header offset');
        if (needDisk) {
          if (position + 4 > end) {
            throw const FormatException('ZIP64 extra field is missing disk number.');
          }
          values.add(ByteData.sublistView(extra).getUint32(position, Endian.little));
        }
        return values;
      }
      cursor = start + length;
    }
    throw const FormatException('Required ZIP64 extra field is missing.');
  }

  static int _findSignature(List<int> bytes, int signature) {
    for (var i = bytes.length - 22; i >= 0; i--) {
      if (bytes[i] == (signature & 255) &&
          bytes[i + 1] == ((signature >> 8) & 255) &&
          bytes[i + 2] == ((signature >> 16) & 255) &&
          bytes[i + 3] == ((signature >> 24) & 255)) return i;
    }
    return -1;
  }

  static int _crc32(int crc, List<int> bytes) {
    var value = crc;
    for (final byte in bytes) {
      value ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        value = (value & 1) != 0 ? (value >> 1) ^ 0xedb88320 : value >> 1;
      }
    }
    return value & 0xffffffff;
  }

  static String _join(String root, String relative) =>
      root + Platform.pathSeparator +
      relative.replaceAll('/', Platform.pathSeparator);

  static bool _inside(String root, String path) =>
      path == root || path.startsWith(root + Platform.pathSeparator);
}
