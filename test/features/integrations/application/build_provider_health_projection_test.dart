import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/integrations/application/use_cases/build_provider_health_projection.dart';
import 'package:abakus_one_v2/features/integrations/data/tenant_integration_configuration_repository.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_connection_status.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_adapter.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_category.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_registry.dart';
import 'package:abakus_one_v2/features/integrations/domain/tenant_integration_configuration.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/real_pos_authorization_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/integration_test_fixtures.dart';

class _ThrowingTenantIntegrationConfigurationRepository
    implements TenantIntegrationConfigurationRepository {
  @override
  Future<void> save(TenantIntegrationConfiguration configuration) {
    throw StateError('Repository must never be queried before authorization');
  }

  @override
  Future<TenantIntegrationConfiguration?> findByOrganizationAndProvider(
    String organizationId,
    String providerId,
  ) {
    throw StateError('Repository must never be queried before authorization');
  }

  @override
  Future<List<TenantIntegrationConfiguration>> findByOrganizationId(
    String organizationId,
  ) {
    throw StateError('Repository must never be queried before authorization');
  }

  @override
  Future<List<TenantIntegrationConfiguration>> findAll() {
    throw StateError('Repository must never be queried before authorization');
  }
}

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
        authorizationPolicy: const AllowAllIntegrationPolicy(),
        providerRegistry: registry,
        tenantIntegrationRepository:
            InMemoryTenantIntegrationConfigurationRepository(),
      );

      final entries = await useCase(
        organizationId: 'org-1',
        actorStaffId: 'owner-1',
      );

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
        authorizationPolicy: const AllowAllIntegrationPolicy(),
        providerRegistry: registry,
        tenantIntegrationRepository: tenantIntegrationRepository,
      );

      final entries = await useCase(
        organizationId: 'org-1',
        actorStaffId: 'owner-1',
      );

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
        authorizationPolicy: const AllowAllIntegrationPolicy(),
        providerRegistry: registry,
        tenantIntegrationRepository: tenantIntegrationRepository,
      );

      final entries = await useCase(
        organizationId: 'org-1',
        actorStaffId: 'owner-1',
      );

      expect(entries.single.tenantEnabled, isFalse);
    });

    group('independent authorization (Phase 8 closure sprint)', () {
      test('an authorized tenant owner succeeds', () async {
        const session = ActorSession(
          actorId: 'owner-1',
          roles: {StaffRole.tenantOwner},
          activeRole: StaffRole.tenantOwner,
          organizationAccess: {'org-1'},
        );
        final useCase = BuildProviderHealthProjection(
          authorizationPolicy:
              RealPosAuthorizationPolicy(currentSession: () => session),
          providerRegistry: IntegrationProviderRegistry(const []),
          tenantIntegrationRepository:
              InMemoryTenantIntegrationConfigurationRepository(),
        );

        final entries = await useCase(
          organizationId: 'org-1',
          actorStaffId: 'owner-1',
        );

        expect(entries, isEmpty);
      });

      test('an actor without manageTenantIntegrations permission fails',
          () async {
        const session = ActorSession(
          actorId: 'staff-1',
          roles: {StaffRole.staff},
          activeRole: StaffRole.staff,
          organizationAccess: {'org-1'},
        );
        final useCase = BuildProviderHealthProjection(
          authorizationPolicy:
              RealPosAuthorizationPolicy(currentSession: () => session),
          providerRegistry: IntegrationProviderRegistry(const []),
          tenantIntegrationRepository:
              _ThrowingTenantIntegrationConfigurationRepository(),
        );

        expect(
          () => useCase(organizationId: 'org-1', actorStaffId: 'staff-1'),
          throwsA(isA<AuthorizationDeniedViolation>()),
        );
      });

      test(
          'a tenantOwner without organizationAccess for the target '
          'organization fails — no role exemption', () async {
        const session = ActorSession(
          actorId: 'owner-1',
          roles: {StaffRole.tenantOwner},
          activeRole: StaffRole.tenantOwner,
          // Deliberately no organizationAccess.
        );
        final useCase = BuildProviderHealthProjection(
          authorizationPolicy:
              RealPosAuthorizationPolicy(currentSession: () => session),
          providerRegistry: IntegrationProviderRegistry(const []),
          tenantIntegrationRepository:
              _ThrowingTenantIntegrationConfigurationRepository(),
        );

        expect(
          () => useCase(organizationId: 'org-1', actorStaffId: 'owner-1'),
          throwsA(isA<AuthorizationDeniedViolation>()),
        );
      });

      test(
          'a tenantOwner granted a different organization is denied for '
          'this one — cross-organization request fails', () async {
        const session = ActorSession(
          actorId: 'owner-1',
          roles: {StaffRole.tenantOwner},
          activeRole: StaffRole.tenantOwner,
          organizationAccess: {'org-2'},
        );
        final useCase = BuildProviderHealthProjection(
          authorizationPolicy:
              RealPosAuthorizationPolicy(currentSession: () => session),
          providerRegistry: IntegrationProviderRegistry(const []),
          tenantIntegrationRepository:
              _ThrowingTenantIntegrationConfigurationRepository(),
        );

        expect(
          () => useCase(organizationId: 'org-1', actorStaffId: 'owner-1'),
          throwsA(isA<AuthorizationDeniedViolation>()),
        );
      });

      test(
          'the repository is never queried before authorization succeeds — '
          'a throwing repository surfaces AuthorizationDeniedViolation, '
          'never a repository error', () async {
        final useCase = BuildProviderHealthProjection(
          authorizationPolicy: const DenyAllIntegrationPolicy(),
          providerRegistry: IntegrationProviderRegistry(const []),
          tenantIntegrationRepository:
              _ThrowingTenantIntegrationConfigurationRepository(),
        );

        await expectLater(
          () => useCase(organizationId: 'org-1', actorStaffId: 'owner-1'),
          throwsA(isA<AuthorizationDeniedViolation>()),
        );
      });
    });
  });
}
