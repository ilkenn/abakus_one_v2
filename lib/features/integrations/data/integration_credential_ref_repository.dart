import '../domain/integration_credential_ref.dart';
import '../domain/integration_credential_kind.dart';

abstract interface class IntegrationCredentialRefRepository {
  Future<void> save(IntegrationCredentialRef ref);
  Future<IntegrationCredentialRef?> findByOrganizationProviderAndKind(
    String organizationId,
    String providerId,
    IntegrationCredentialKind kind,
  );
  Future<List<IntegrationCredentialRef>> findByOrganizationId(
    String organizationId,
  );
}

class InMemoryIntegrationCredentialRefRepository
    implements IntegrationCredentialRefRepository {
  final Map<String, IntegrationCredentialRef> _byId = {};

  @override
  Future<void> save(IntegrationCredentialRef ref) async {
    _byId[ref.id] = ref;
  }

  @override
  Future<IntegrationCredentialRef?> findByOrganizationProviderAndKind(
    String organizationId,
    String providerId,
    IntegrationCredentialKind kind,
  ) async {
    for (final ref in _byId.values) {
      if (ref.organizationId == organizationId &&
          ref.providerId == providerId &&
          ref.kind == kind) {
        return ref;
      }
    }
    return null;
  }

  @override
  Future<List<IntegrationCredentialRef>> findByOrganizationId(
    String organizationId,
  ) async {
    return List.unmodifiable(
      _byId.values.where((r) => r.organizationId == organizationId),
    );
  }
}
