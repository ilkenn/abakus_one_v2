import '../../data/tenant_integration_configuration_repository.dart';
import '../../domain/integration_provider_registry.dart';
import '../../domain/provider_health_entry.dart';

/// Builds the Provider Health read-model for one tenant — Phase 8
/// (`docs/decisions.md` ADR-025), "Provider Health Monitoring." A
/// **projection**, not a merged write-side store, mirroring
/// `BuildDeviceRegistryProjection`'s (Phase 6L) exact reasoning: neither
/// `IntegrationProviderRegistry` nor `TenantIntegrationConfigurationRepository`
/// is touched or rewritten here, only read and normalized into one
/// consistent row shape per provider.
class BuildProviderHealthProjection {
  const BuildProviderHealthProjection({
    required IntegrationProviderRegistry providerRegistry,
    required TenantIntegrationConfigurationRepository
        tenantIntegrationRepository,
  })  : _providerRegistry = providerRegistry,
        _tenantIntegrationRepository = tenantIntegrationRepository;

  final IntegrationProviderRegistry _providerRegistry;
  final TenantIntegrationConfigurationRepository _tenantIntegrationRepository;

  Future<List<ProviderHealthEntry>> call({
    required String organizationId,
  }) async {
    final entries = <ProviderHealthEntry>[];

    for (final adapter in _providerRegistry.all) {
      final tenantConfig =
          await _tenantIntegrationRepository.findByOrganizationAndProvider(
        organizationId,
        adapter.providerId,
      );
      final connectionStatus = await adapter.checkConnection();

      entries.add(ProviderHealthEntry(
        providerId: adapter.providerId,
        category: adapter.category,
        displayName: adapter.displayName,
        tenantEnabled: tenantConfig?.enabled ?? false,
        connectionStatus: connectionStatus,
      ));
    }

    return List.unmodifiable(entries);
  }
}
