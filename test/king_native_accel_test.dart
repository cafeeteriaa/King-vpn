import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/king_native_accel.dart';

void main() {
  group('KingNativeAccel optional loading', () {
    test('unsupported host platforms safely use the Dart implementation', () {
      if (Platform.isAndroid) return;
      expect(KingNativeAccel.tryExpandAddressRangeBatch('192.0.2.0/30', cursor: '0', limit: 2), isNull);
      expect(KingNativeAccel.isAvailable, isFalse);
    });
    test('native batch requests reject unreasonable sizes before FFI', () {
      expect(KingNativeAccel.tryExpandAddressRangeBatch('2001:db8::/64', cursor: '0', limit: 8193), isNull);
    });
    test('zero-sized native batches preserve the original Dart contract', () {
      expect(KingNativeAccel.tryExpandAddressRangeBatch('192.0.2.0/30', cursor: '2', limit: 0), isNull);
    });
  });
}
