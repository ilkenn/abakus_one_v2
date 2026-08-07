import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/models/auth_session.dart';

/// The one storage seam [AuthRepository] implementations depend on for
/// persisting a session — deliberately narrow (read/write/clear a single
/// [AuthSession], nothing else) rather than a general-purpose key-value
/// storage wrapper, per the explicit instruction against building a
/// general storage framework. Kept separate from `AuthRepository` so tests
/// can inject a fake here without touching a real platform channel —
/// `flutter_secure_storage` is backed by native code unavailable under
/// `flutter test`.
abstract interface class SessionStorage {
  Future<AuthSession?> readSession();
  Future<void> writeSession(AuthSession session);
  Future<void> clearSession();
}

/// The real, `flutter_secure_storage`-backed implementation. Any failure
/// while reading — corrupt JSON, a missing field, the plugin itself
/// throwing, or the platform channel never responding at all — is treated
/// as "no valid session" rather than allowed to crash the app or hang
/// bootstrap forever, per the explicit requirement that a broken/unreadable
/// session must fail safe. A bounded [_timeout] matters as much as the
/// `try`/`catch` here: an unregistered or unresponsive platform channel
/// doesn't throw, it simply never completes, so a `catch` alone can't
/// protect against it — only a timeout can.
class SecureSessionStorage implements SessionStorage {
  static const _sessionKey = 'auth_session';
  static const _timeout = Duration(seconds: 2);

  final FlutterSecureStorage _storage;

  const SecureSessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<AuthSession?> readSession() async {
    try {
      final raw = await _storage.read(key: _sessionKey).timeout(_timeout);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return AuthSession.tryFromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeSession(AuthSession session) async {
    try {
      await _storage
          .write(key: _sessionKey, value: jsonEncode(session.toJson()))
          .timeout(_timeout);
    } catch (_) {
      // Best-effort: if secure storage is unavailable on this device/
      // platform, the user simply won't be auto-logged-in next launch —
      // a safe failure mode, not a crash.
    }
  }

  @override
  Future<void> clearSession() async {
    try {
      await _storage.delete(key: _sessionKey).timeout(_timeout);
    } catch (_) {
      // Best-effort — nothing meaningful to recover from here either.
    }
  }
}
