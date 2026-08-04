import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/integrations/application/identity/tenant_integration_configuration_id_generator.dart';
import 'package:abakus_one_v2/features/integrations/application/use_cases/set_tenant_integration_enabled.dart';
import 'package:abakus_one_v2/features/integrations/data/integration_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/integrations/data/tenant_integration_configuration_repository.dart';
import 'package:abakus_one_v2/features/integrations/domain/audit/integration_audit_event_type.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_adapter.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_category.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/integration_test_fixtures.dart';

IntegrationProviderRegistry buildRegistry() {
  return IntegrationProviderRegistry(const [
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
}

void main() {
  group('SetTenantIntegrationEnabled', () {
    test('creates a new enabled configuration for a registered provider',
        () async {
      final repository = InMemoryTenantIntegrationConfigurationRepository();
      final auditRepository = InMemoryIntegrationAuditEntryRepository();
      final useCase = SetTenantIntegrationEnabled(
        authorizationPolicy: const AllowAllIntegrationPolicy(),
        providerRegistry: buildRegistry(),
        idGenerator: SequentialTenantIntegrationConfigurationIdGenerator(),
        repository: repository,
        auditRepository: auditRepository,
      );

      final config = await useCase(
        organizationId: 'org-1',
        providerId: 'yemeksepeti',
        enabled: true,
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(config.enabled, isTrue);
      expect(config.category, IntegrationProviderCategory.marketplace);
      expect(config.revision, 1);

      final entries = await auditRepository.findByTargetEntityId(config.id);
      expect(
        entries.single.type,
        IntegrationAuditEventType.tenantIntegrationEnabled,
      );
    });

    test(
        'toggling an existing configuration reuses its id and bumps '
        'revision', () async {
      final repository = InMemoryTenantIntegrationConfigurationRepository();
      final useCase = SetTenantIntegrationEnabled(
        authorizationPolicy: const AllowAllIntegrationPolicy(),
        providerRegistry: buildRegistry(),
        idGenerator: SequentialTenantIntegrationConfigurationIdGenerator(),
        repository: repository,
        auditRepository: InMemoryIntegrationAuditEntryRepository(),
      );

      final first = await useCase(
        organizationId: 'org-1',
        providerId: 'iyzico',
        enabled: true,
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 1),
      );
      final second = await useCase(
        organizationId: 'org-1',
        providerId: 'iyzico',
        enabled: false,
        performedByStaffId: 'owner-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(second.id, first.id);
      expect(second.revision, 2);
      expect(second.enabled, isFalse);
    });

    test('an unregistered providerId throws', () async {
      final useCase = SetTenantIntegrationEnabled(
        authorizationPolicy: const AllowAllIntegrationPolicy(),
        providerRegistry: buildRegistry(),
        idGenerator: SequentialTenantIntegrationConfigurationIdGenerator(),
        repository: InMemoryTenantIntegrationConfigurationRepository(),
        auditRepository: InMemoryIntegrationAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          providerId: 'unknown-provider',
          enabled: true,
          performedByStaffId: 'owner-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownIntegrationProviderViolation>()),
      );
    });

    test('an unauthorized actor is denied', () async {
      final useCase = SetTenantIntegrationEnabled(
        authorizationPolicy: const DenyAllIntegrationPolicy(),
        providerRegistry: buildRegistry(),
        idGenerator: SequentialTenantIntegrationConfigurationIdGenerator(),
        repository: InMemoryTenantIntegrationConfigurationRepository(),
        auditRepository: InMemoryIntegrationAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          providerId: 'yemeksepeti',
          enabled: true,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
