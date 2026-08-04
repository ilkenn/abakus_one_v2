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
}
