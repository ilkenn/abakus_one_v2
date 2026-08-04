import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The one storage seam for an integration credential's actual secret
/// value — Phase 8 (`docs/decisions.md` ADR-025), mirroring
/// `SessionStorage`'s (`features/auth`) exact reasoning: deliberately
/// narrow (read/write/delete by an opaque key, nothing else), not a
/// general-purpose key-value framework. Reuses the already-present
/// `flutter_secure_storage` dependency (used today only for the auth
/// session) rather than adding a new one — "zero new pub dependencies"
/// holds for the whole of Phase 8.
///
/// **No use case in this phase ever returns a value read from here to
/// a screen or an audit description** — `StoreIntegrationCredential`/
/// `RevokeIntegrationCredential` (8K) only write/delete; [readValue]
/// exists solely for a future real provider-adapter implementation
/// (out of scope this phase — "do NOT integrate providers yet") to
/// consume internally.
abstract interface class IntegrationCredentialStorage {
  Future<String?> readValue(String storageKey);
  Future<void> writeValue(String storageKey, String value);
  Future<void> deleteValue(String storageKey);
}

/// The real, `flutter_secure_storage`-backed implementation. Mirrors
/// `SecureSessionStorage`'s exact fail-safe/timeout shape: any failure
/// is swallowed rather than allowed to crash the caller, since a
/// broken/unavailable secure-storage platform channel is a real device
/// condition this codebase already treats as recoverable elsewhere.
class SecureIntegrationCredentialStorage
    implements IntegrationCredentialStorage {
  static const _timeout = Duration(seconds: 2);

  final FlutterSecureStorage _storage;

  const SecureIntegrationCredentialStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> readValue(String storageKey) async {
    try {
      return await _storage.read(key: storageKey).timeout(_timeout);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeValue(String storageKey, String value) async {
    try {
      await _storage.write(key: storageKey, value: value).timeout(_timeout);
    } catch (_) {
      // Best-effort, matching SecureSessionStorage's own precedent — a
      // failure here surfaces to the caller as "the credential was not
      // actually stored," never a crash.
    }
  }

  @override
  Future<void> deleteValue(String storageKey) async {
    try {
      await _storage.delete(key: storageKey).timeout(_timeout);
    } catch (_) {
      // Best-effort — nothing meaningful to recover from here either.
    }
  }
}
