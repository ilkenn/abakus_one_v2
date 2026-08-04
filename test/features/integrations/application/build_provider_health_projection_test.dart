import 'package:abakus_one_v2/features/integrations/application/use_cases/build_provider_health_projection.dart';
import 'package:abakus_one_v2/features/integrations/data/tenant_integration_configuration_repository.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_connection_status.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_adapter.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_category.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_registry.dart';
import 'package:abakus_one_v2/features/integrations/domain/tenant_integration_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuildProviderHealthProjection', () {
    test(
        'returns one entry per registered provider, honestly '
        'notConfigured with no tenant enablement by default', () async {
      final registry = IntegrationProviderRegistry(const [
        UnconfiguredIntegrationProviderAdapter(
          category: IntegrationProviderCategory.marketplace,
          providerId: 'yemeksepeti',
          displayName: 'Yemeksepeti',
        ),
        UnconfiguredIntegrationProviderAdapter(
          category: IntegrationProviderCategory.payment,
          providerId: 'iyzico',
          displayName: 'iyzico',
        ),
      ]);
      final useCase = BuildProviderHealthProjection(
        providerRegistry: registry,
        tenantIntegrationRepository:
            InMemoryTenantIntegrationConfigurationRepository(),
      );

      final entries = await useCase(organizationId: 'org-1');

      expect(entries, hasLength(2));
      for (final entry in entries) {
        expect(entry.tenantEnabled, isFalse);
        expect(
            entry.connectionStatus, IntegrationConnectionStatus.notConfigured);
        expect(entry.lastCheckedAt, isNull);
      }
    });

    test('reflects a tenant-enabled provider as tenantEnabled: true', () async {
      final registry = IntegrationProviderRegistry(const [
        UnconfiguredIntegrationProviderAdapter(
          category: IntegrationProviderCategory.marketplace,
          providerId: 'yemeksepeti',
          displayName: 'Yemeksepeti',
        ),
      ]);
      final tenantIntegrationRepository =
          InMemoryTenantIntegrationConfigurationRepository();
      await tenantIntegrationRepository.save(TenantIntegrationConfiguration(
        id: 'config-1',
        organizationId: 'org-1',
        category: IntegrationProviderCategory.marketplace,
        providerId: 'yemeksepeti',
        enabled: true,
        configuredByStaffId: 'owner-1',
        configuredAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final useCase = BuildProviderHealthProjection(
        providerRegistry: registry,
        tenantIntegrationRepository: tenantIntegrationRepository,
      );

      final entries = await useCase(organizationId: 'org-1');

      expect(entries.single.tenantEnabled, isTrue);
    });

    test('never reflects a different organization\'s enablement', () async {
      final registry = IntegrationProviderRegistry(const [
        UnconfiguredIntegrationProviderAdapter(
          category: IntegrationProviderCategory.marketplace,
          providerId: 'yemeksepeti',
          displayName: 'Yemeksepeti',
        ),
      ]);
      final tenantIntegrationRepository =
          InMemoryTenantIntegrationConfigurationRepository();
      await tenantIntegrationRepository.save(TenantIntegrationConfiguration(
        id: 'config-1',
        organizationId: 'org-2',
        category: IntegrationProviderCategory.marketplace,
        providerId: 'yemeksepeti',
        enabled: true,
        configuredByStaffId: 'owner-1',
        configuredAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final useCase = BuildProviderHealthProjection(
        providerRegistry: registry,
        tenantIntegrationRepository: tenantIntegrationRepository,
      );

      final entries = await useCase(organizationId: 'org-1');

      expect(entries.single.tenantEnabled, isFalse);
    });
  });
}
