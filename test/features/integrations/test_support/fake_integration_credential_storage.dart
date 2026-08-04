import 'package:abakus_one_v2/features/integrations/data/integration_credential_storage.dart';

/// An in-memory fake — `SecureIntegrationCredentialStorage` is backed
/// by native `flutter_secure_storage` code unavailable under
/// `flutter test`, mirroring every fake `SessionStorage` this codebase
/// already defines per-test-file (`features/auth`) rather than a real
/// platform-channel-backed implementation.
class FakeIntegrationCredentialStorage implements IntegrationCredentialStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> readValue(String storageKey) async => _values[storageKey];

  @override
  Future<void> writeValue(String storageKey, String value) async {
    _values[storageKey] = value;
  }

  @override
  Future<void> deleteValue(String storageKey) async {
    _values.remove(storageKey);
  }
}
