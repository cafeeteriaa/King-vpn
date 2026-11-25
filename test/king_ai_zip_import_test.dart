import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/king_ai_zip_import.dart';

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

Uint8List _storedZip(String name, String content) {
  final nameBytes = utf8.encode(name);
  final data = utf8.encode(content);
  final crc = _crc32(data);
  final local = Uint8List(30 + nameBytes.length + data.length);
  final l = ByteData.sublistView(local);
  l.setUint32(0, 0x04034b50, Endian.little);
  l.setUint16(4, 20, Endian.little);
  l.setUint16(6, 0x800, Endian.little);
  l.setUint16(8, 0, Endian.little);
  l.setUint32(14, crc, Endian.little);
  l.setUint32(18, data.length, Endian.little);
  l.setUint32(22, data.length, Endian.little);
  l.setUint16(26, nameBytes.length, Endian.little);
  local.setRange(30, 30 + nameBytes.length, nameBytes);
  local.setRange(30 + nameBytes.length, local.length, data);

  final central = Uint8List(46 + nameBytes.length);
  final c = ByteData.sublistView(central);
  c.setUint32(0, 0x02014b50, Endian.little);
  c.setUint16(4, 0x0314, Endian.little);
  c.setUint16(6, 20, Endian.little);
  c.setUint16(8, 0x800, Endian.little);
  c.setUint16(10, 0, Endian.little);
  c.setUint32(16, crc, Endian.little);
  c.setUint32(20, data.length, Endian.little);
  c.setUint32(24, data.length, Endian.little);
  c.setUint16(28, nameBytes.length, Endian.little);
  central.setRange(46, central.length, nameBytes);

  final end = Uint8List(22);
  final e = ByteData.sublistView(end);
  e.setUint32(0, 0x06054b50, Endian.little);
  e.setUint16(8, 1, Endian.little);
  e.setUint16(10, 1, Endian.little);
  e.setUint32(12, central.length, Endian.little);
  e.setUint32(16, local.length, Endian.little);
  return Uint8List.fromList([...local, ...central, ...end]);
}

Uint8List _storedZip64(String name, String content) {
  final nameBytes = utf8.encode(name);
  final data = utf8.encode(content);
  final crc = _crc32(data);
  final local = Uint8List(30 + nameBytes.length + data.length);
  final l = ByteData.sublistView(local);
  l.setUint32(0, 0x04034b50, Endian.little);
  l.setUint16(4, 45, Endian.little);
  l.setUint16(6, 0x800, Endian.little);
  l.setUint16(8, 0, Endian.little);
  l.setUint32(14, crc, Endian.little);
  l.setUint32(18, data.length, Endian.little);
  l.setUint32(22, data.length, Endian.little);
  l.setUint16(26, nameBytes.length, Endian.little);
  local.setRange(30, 30 + nameBytes.length, nameBytes);
  local.setRange(30 + nameBytes.length, local.length, data);

  final central = Uint8List(46 + nameBytes.length + 28);
  final c = ByteData.sublistView(central);
  c.setUint32(0, 0x02014b50, Endian.little);
  c.setUint16(4, 0x032d, Endian.little);
  c.setUint16(6, 45, Endian.little);
  c.setUint16(8, 0x800, Endian.little);
  c.setUint16(10, 0, Endian.little);
  c.setUint32(16, crc, Endian.little);
  c.setUint32(20, 0xffffffff, Endian.little);
  c.setUint32(24, 0xffffffff, Endian.little);
  c.setUint16(28, nameBytes.length, Endian.little);
  c.setUint16(30, 28, Endian.little);
  c.setUint32(42, 0xffffffff, Endian.little);
  central.setRange(46, 46 + nameBytes.length, nameBytes);
  final extraAt = 46 + nameBytes.length;
  final extra = ByteData.sublistView(central, extraAt);
  extra.setUint16(0, 0x0001, Endian.little);
  extra.setUint16(2, 24, Endian.little);
  extra.setUint64(4, data.length, Endian.little);
  extra.setUint64(12, data.length, Endian.little);
  extra.setUint64(20, 0, Endian.little);

  final zip64Offset = local.length + central.length;
  final zip64 = Uint8List(56);
  final z = ByteData.sublistView(zip64);
  z.setUint32(0, 0x06064b50, Endian.little);
  z.setUint64(4, 44, Endian.little);
  z.setUint16(12, 45, Endian.little);
  z.setUint16(14, 45, Endian.little);
  z.setUint64(24, 1, Endian.little);
  z.setUint64(32, 1, Endian.little);
  z.setUint64(40, central.length, Endian.little);
  z.setUint64(48, local.length, Endian.little);

  final locator = Uint8List(20);
  final p = ByteData.sublistView(locator);
  p.setUint32(0, 0x07064b50, Endian.little);
  p.setUint32(4, 0, Endian.little);
  p.setUint64(8, zip64Offset, Endian.little);
  p.setUint32(16, 1, Endian.little);

  final end = Uint8List(22);
  final e = ByteData.sublistView(end);
  e.setUint32(0, 0x06054b50, Endian.little);
  e.setUint16(8, 0xffff, Endian.little);
  e.setUint16(10, 0xffff, Endian.little);
  e.setUint32(12, 0xffffffff, Endian.little);
  e.setUint32(16, 0xffffffff, Endian.little);
  return Uint8List.fromList([...local, ...central, ...zip64, ...locator, ...end]);
}

void main() {
  test('normalizes safe paths and rejects traversal/absolute paths', () {
    expect(KingAiZipImport.normalizeEntryPath('../escape.txt'), isNull);
    expect(KingAiZipImport.normalizeEntryPath('/absolute.txt'), isNull);
    expect(KingAiZipImport.normalizeEntryPath('C:/drive.txt'), isNull);
    expect(KingAiZipImport.normalizeEntryPath('safe/./file.txt'), 'safe/file.txt');
    expect(KingAiZipImport.normalizeEntryPath(r'safe\file.txt'), 'safe/file.txt');
  });

  test('extracts a valid stored source file and verifies its CRC', () async {
    final temp = await Directory.systemTemp.createTemp('king-ai-zip-');
    try {
      final archive = File(temp.path + '/project.zip');
      await archive.writeAsBytes(_storedZip('lib/example.dart', 'const value = 42;'));
      final destination = Directory(temp.path + '/workspace');
      final paths = await KingAiZipImport.extract(
        archiveFile: archive,
        destination: destination,
      );
      expect(paths, ['lib/example.dart']);
      expect(
        await File(destination.path + '/lib/example.dart').readAsString(),
        'const value = 42;',
      );
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('extracts ZIP64 archives and reads ZIP64 entry sizes and offsets', () async {
    final temp = await Directory.systemTemp.createTemp('king-ai-zip64-');
    try {
      final archive = File(temp.path + '/project.zip');
      await archive.writeAsBytes(_storedZip64('lib/large_project.dart', 'const zip64 = true;'));
      final destination = Directory(temp.path + '/workspace');
      final paths = await KingAiZipImport.extract(
        archiveFile: archive,
        destination: destination,
      );
      expect(paths, ['lib/large_project.dart']);
      expect(
        await File(destination.path + '/lib/large_project.dart').readAsString(),
        'const zip64 = true;',
      );
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('rejects a missing archive without creating a destination', () async {
    final temp = await Directory.systemTemp.createTemp('king-ai-zip-');
    try {
      final destination = Directory(temp.path + '/project');
      await expectLater(
        KingAiZipImport.extract(
          archiveFile: File(temp.path + '/missing.zip'),
          destination: destination,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await destination.exists(), isFalse);
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
