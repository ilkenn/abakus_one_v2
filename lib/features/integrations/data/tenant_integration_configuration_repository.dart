import '../domain/tenant_integration_configuration.dart';

abstract interface class TenantIntegrationConfigurationRepository {
  Future<void> save(TenantIntegrationConfiguration configuration);
  Future<TenantIntegrationConfiguration?> findByOrganizationAndProvider(
    String organizationId,
    String providerId,
  );
  Future<List<TenantIntegrationConfiguration>> findByOrganizationId(
    String organizationId,
  );

  /// Every configuration across every tenant — Phase 8O (Platform
  /// Monitoring). Cross-tenant by design; only a platform-level actor
  /// should ever consult this, never a tenant-scoped one.
  Future<List<TenantIntegrationConfiguration>> findAll();
}

class InMemoryTenantIntegrationConfigurationRepository
    implements TenantIntegrationConfigurationRepository {
  final Map<String, TenantIntegrationConfiguration> _byId = {};

  @override
  Future<void> save(TenantIntegrationConfiguration configuration) async {
    _byId[configuration.id] = configuration;
  }

  @override
  Future<TenantIntegrationConfiguration?> findByOrganizationAndProvider(
    String organizationId,
    String providerId,
  ) async {
    for (final config in _byId.values) {
      if (config.organizationId == organizationId &&
          config.providerId == providerId) {
        return config;
      }
    }
    return null;
  }

  @override
  Future<List<TenantIntegrationConfiguration>> findByOrganizationId(
    String organizationId,
  ) async {
    return List.unmodifiable(
      _byId.values.where((c) => c.organizationId == organizationId),
    );
  }

  @override
  Future<List<TenantIntegrationConfiguration>> findAll() async {
    return List.unmodifiable(_byId.values);
  }
}
