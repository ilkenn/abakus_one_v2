import 'package:abakus_one_v2/features/integrations/data/integration_credential_storage.dart';

/// An in-memory fake — `SecureIntegrationCredentialStorage` is backed
/// by native `flutter_secure_storage` code unavailable under
/// `flutter test`, mirroring every fake `SessionStorage` this codebase
/// already defines per-test-file (`features/auth`) rather than a real
/// platform-channel-backed implementation.
class FakeIntegrationCredentialStorage implements IntegrationCredentialStorage {
  FakeIntegrationCredentialStorage({this.failWrites = false});

  /// Simulates a broken secure-storage platform channel — Phase 8S
  /// security pass regression coverage for `StoreIntegrationCredential`'s
  /// "never persist a ref/audit entry for a write that didn't succeed"
  /// guarantee.
  final bool failWrites;

  final Map<String, String> _values = {};

  @override
  Future<String?> readValue(String storageKey) async => _values[storageKey];

  @override
  Future<bool> writeValue(String storageKey, String value) async {
    if (failWrites) return false;
    _values[storageKey] = value;
    return true;
  }

  @override
  Future<void> deleteValue(String storageKey) async {
    _values.remove(storageKey);
  }
}
