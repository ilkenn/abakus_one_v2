import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Caches the non-key-material state a trusted-device session needs across
/// app restarts — the server-assigned `deviceId` (once registered) and the
/// currently active session's id/expiry. Deliberately separate from
/// [SecureDeviceKeyStore]: this holds session/identity bookkeeping, never
/// private key bytes — a cleaner boundary for what each class's storage
/// actually needs to protect, even though both happen to use
/// [FlutterSecureStorage] as their backing store (a session id is itself a
/// 12-hour bearer credential for device-gated POS actions, so it still
/// belongs in encrypted-at-rest storage, not plain `shared_preferences`).
class DeviceSessionCache {
  DeviceSessionCache({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _deviceIdKey(String namespace) => 'trusted_device_id_$namespace';
  String _sessionKey(String namespace) => 'trusted_device_session_$namespace';

  Future<String?> readDeviceId(String namespace) {
    return _storage.read(key: _deviceIdKey(namespace));
  }

  Future<void> writeDeviceId(String namespace, String deviceId) {
    return _storage.write(key: _deviceIdKey(namespace), value: deviceId);
  }

  Future<({String sessionId, DateTime expiresAt})?> readSession(
    String namespace,
  ) async {
    final raw = await _storage.read(key: _sessionKey(namespace));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return (
        sessionId: decoded['sessionId'] as String,
        expiresAt: DateTime.parse(decoded['expiresAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSession(
    String namespace, {
    required String sessionId,
    required DateTime expiresAt,
  }) {
    return _storage.write(
      key: _sessionKey(namespace),
      value: jsonEncode({
        'sessionId': sessionId,
        'expiresAt': expiresAt.toIso8601String(),
      }),
    );
  }

  Future<void> clearSession(String namespace) {
    return _storage.delete(key: _sessionKey(namespace));
  }

  /// Clears every cached value for [namespace] — the deliberate,
  /// operator-confirmed recovery path alongside [DeviceKeyStore.deleteKey]
  /// for a revoked/retired device or a detected storage corruption.
  Future<void> clearAll(String namespace) async {
    await _storage.delete(key: _deviceIdKey(namespace));
    await _storage.delete(key: _sessionKey(namespace));
  }
}
