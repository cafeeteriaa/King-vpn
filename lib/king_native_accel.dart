import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _ExpandNative = IntPtr Function(Pointer<Utf8>, Pointer<Utf8>, Uint32, Pointer<Uint8>, IntPtr);
typedef _ExpandDart = int Function(Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Uint8>, int);

/// Optional Android FFI bridge. Failures preserve the established Dart path.
class KingNativeAccel {
  KingNativeAccel._();
  static const int maxNativeBatchSize = 8192;
  static const int minNativeBatchSize = 64;
  static bool _benchmarkComplete = false;
  static bool _preferNative = false;
  static final BigInt _maxNativeCursor = BigInt.parse('340282366920938463463374607431768211455');
  static bool _loadAttempted = false;
  static DynamicLibrary? _library;
  static _ExpandDart? _expand;

  static bool get shouldBenchmark => !_benchmarkComplete && isAvailable;

  static bool get useNative =>
      _benchmarkComplete && _preferNative && isAvailable;

  static void completeBenchmark({
    required bool equivalent,
    required bool nativeFaster,
  }) {
    _benchmarkComplete = true;
    _preferNative = equivalent && nativeFaster;
  }

  static void disableNative() {
    _benchmarkComplete = true;
    _preferNative = false;
  }

  static bool get isAvailable {
    _ensureLoaded();
    return _library != null && _expand != null;
  }

  static void _ensureLoaded() {
    if (_loadAttempted) return;
    _loadAttempted = true;
    if (!Platform.isAndroid) return;
    try {
      final library = DynamicLibrary.open('libking_native_core.so');
      _expand = library.lookupFunction<_ExpandNative, _ExpandDart>('king_expand_range_batch');
      _library = library;
    } catch (_) {
      _library = null;
      _expand = null;
    }
  }

  static ({List<String> addresses, String nextCursor})? tryExpandAddressRangeBatch(
    String range, {required String cursor, required int limit}
  ) {
    final parsedCursor = BigInt.tryParse(cursor);
    if (!Platform.isAndroid || limit <= 0 || limit > maxNativeBatchSize ||
        (parsedCursor != null && (parsedCursor.isNegative || parsedCursor > _maxNativeCursor))) {
      return null;
    }
    _ensureLoaded();
    final expand = _expand;
    if (expand == null) return null;
    Pointer<Utf8>? nativeRange;
    Pointer<Utf8>? nativeCursor;
    Pointer<Uint8>? output;
    try {
      nativeRange = range.toNativeUtf8(allocator: malloc);
      nativeCursor = cursor.toNativeUtf8(allocator: malloc);
      final capacity = (limit * 48 + 128).clamp(256, 400000).toInt();
      output = calloc<Uint8>(capacity);
      final written = expand(nativeRange, nativeCursor, limit, output, capacity);
      if (written < 0 || written > capacity) return null;
      final decoded = utf8.decode(output.asTypedList(written), allowMalformed: false);
      final separator = decoded.indexOf('\n');
      if (separator < 0) return null;
      final nextCursor = decoded.substring(0, separator);
      if (BigInt.tryParse(nextCursor) == null) return null;
      final addresses = decoded.substring(separator + 1).split('\n')
          .where((value) => value.isNotEmpty).toList(growable: false);
      if (addresses.length > limit ||
          addresses.any((value) => InternetAddress.tryParse(value) == null)) return null;
      return (addresses: addresses, nextCursor: nextCursor);
    } catch (_) {
      return null;
    } finally {
      if (nativeRange != null) malloc.free(nativeRange);
      if (nativeCursor != null) malloc.free(nativeCursor);
      if (output != null) calloc.free(output);
    }
  }
}
