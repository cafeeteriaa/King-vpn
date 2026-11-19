import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local owner gate for user-requested code/feature changes.
///
/// The password is never persisted. Only a random salt and a PBKDF2 verifier
/// are stored in Android Keystore-backed secure storage. Autonomous background
/// repair deliberately does not depend on this interactive owner session.
class KingAiOwnerAuth {
  KingAiOwnerAuth._();

  static final KingAiOwnerAuth instance = KingAiOwnerAuth._();

  static const Duration sessionLifetime = Duration(minutes: 15);
  static const int _minimumPasswordLength = 12;
  static const int _maxFailuresBeforeLock = 5;

  static const String _saltKey = 'king_ai_owner_salt_v1';
  static const String _verifierKey = 'king_ai_owner_verifier_v1';
  static const String _failuresKey = 'king_ai_owner_failures_v1';
  static const String _lockUntilKey = 'king_ai_owner_lock_until_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  // Argon2id is memory-hard and recommended by the cryptography package
  // for password hashing. 32 MiB keeps the one-time unlock cost bounded on
  // mid-range Android devices while resisting large-scale GPU guessing.
  final Argon2id _kdf = Argon2id(
    memory: 32 * 1024,
    parallelism: 2,
    iterations: 3,
    hashLength: 32,
  );

  DateTime? _sessionExpiresAt;

  Future<bool> get isConfigured async =>
      (await _storage.read(key: _saltKey)) != null &&
      (await _storage.read(key: _verifierKey)) != null;

  bool get hasActiveSession {
    final expires = _sessionExpiresAt;
    if (expires == null || !DateTime.now().isBefore(expires)) {
      _sessionExpiresAt = null;
      return false;
    }
    return true;
  }

  Future<void> setInitialPassword(String password) async {
    if (await isConfigured) {
      throw StateError('Owner password is already configured.');
    }
    _validatePassword(password);
    final salt = _randomBytes(16);
    final verifier = await _derive(password, salt);
    await _storage.write(key: _saltKey, value: base64Encode(salt));
    await _storage.write(key: _verifierKey, value: base64Encode(verifier));
    await _storage.delete(key: _failuresKey);
    await _storage.delete(key: _lockUntilKey);
    _sessionExpiresAt = DateTime.now().add(sessionLifetime);
  }

  /// Password changes require a currently authenticated owner session.
  Future<void> changePassword(String password) async {
    if (!hasActiveSession) {
      throw StateError('Owner authentication is required.');
    }
    _validatePassword(password);
    final salt = _randomBytes(16);
    final verifier = await _derive(password, salt);
    await _storage.write(key: _saltKey, value: base64Encode(salt));
    await _storage.write(key: _verifierKey, value: base64Encode(verifier));
    await _storage.delete(key: _failuresKey);
    await _storage.delete(key: _lockUntilKey);
    _sessionExpiresAt = DateTime.now().add(sessionLifetime);
  }

  Future<bool> authenticate(String password) async {
    if (!await isConfigured) return false;

    final lockRaw = await _storage.read(key: _lockUntilKey);
    final lockUntil = lockRaw == null ? null : int.tryParse(lockRaw);
    if (lockUntil != null &&
        DateTime.now().millisecondsSinceEpoch < lockUntil) {
      return false;
    }

    final saltRaw = await _storage.read(key: _saltKey);
    final verifierRaw = await _storage.read(key: _verifierKey);
    if (saltRaw == null || verifierRaw == null) return false;

    final salt = base64Decode(saltRaw);
    final expected = base64Decode(verifierRaw);
    final actual = await _derive(password, salt);
    if (_constantTimeEquals(actual, expected)) {
      await _storage.delete(key: _failuresKey);
      await _storage.delete(key: _lockUntilKey);
      _sessionExpiresAt = DateTime.now().add(sessionLifetime);
      return true;
    }

    final previous =
        int.tryParse(await _storage.read(key: _failuresKey) ?? '') ?? 0;
    final failures = previous + 1;
    await _storage.write(key: _failuresKey, value: failures.toString());
    if (failures >= _maxFailuresBeforeLock) {
      final exponent = (failures - _maxFailuresBeforeLock).clamp(0, 10);
      final seconds = min(3600, 30 * (1 << exponent));
      final until = DateTime.now()
          .add(Duration(seconds: seconds))
          .millisecondsSinceEpoch;
      await _storage.write(key: _lockUntilKey, value: until.toString());
    }
    _sessionExpiresAt = null;
    return false;
  }

  void lock() => _sessionExpiresAt = null;

  Future<List<int>> _derive(String password, List<int> salt) async {
    final key = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    return key.extractBytes();
  }

  static List<int> _randomBytes(int count) {
    final random = Random.secure();
    return List<int>.generate(count, (_) => random.nextInt(256));
  }

  static void _validatePassword(String password) {
    if (password.length < _minimumPasswordLength ||
        password.trim() != password ||
        password.contains(RegExp(r'\s'))) {
      throw ArgumentError(
        'Choose a password with at least 12 characters and no spaces.',
      );
    }
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    var difference = a.length ^ b.length;
    final length = max(a.length, b.length);
    for (var i = 0; i < length; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      difference |= left ^ right;
    }
    return difference == 0;
  }
}
