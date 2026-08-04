import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/admin/data/organization_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/organization/organization.dart';
import 'package:abakus_one_v2/features/integrations/data/tenant_integration_configuration_repository.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_category.dart';
import 'package:abakus_one_v2/features/integrations/domain/tenant_integration_configuration.dart';
import 'package:abakus_one_v2/features/platform/application/use_cases/build_platform_monitoring_snapshot.dart';
import 'package:abakus_one_v2/features/platform/data/platform_member_repository.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/platform_actor_session.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/platform_role.dart';
import 'package:abakus_one_v2/features/platform/domain/authorization/real_platform_authorization_policy.dart';
import 'package:abakus_one_v2/features/platform/domain/member/platform_member.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuildPlatformMonitoringSnapshot', () {
    test('aggregates real counts across every tenant', () async {
      final organizationRepository = InMemoryOrganizationRepository(seed: [
        Organization(
          id: 'org-1',
          name: 'Org 1',
          createdAt: DateTime(2026, 1, 1),
          revision: 1,
        ),
        Organization(
          id: 'org-2',
          name: 'Org 2',
          createdAt: DateTime(2026, 1, 1),
          revision: 1,
        ),
      ]);
      final platformMemberRepository = InMemoryPlatformMemberRepository();
      await platformMemberRepository.save(PlatformMember(
        id: 'platform-1',
        displayName: 'Owner',
        roles: const {PlatformRole.platformOwner},
        createdAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
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
      await tenantIntegrationRepository.save(TenantIntegrationConfiguration(
        id: 'config-2',
        organizationId: 'org-2',
        category: IntegrationProviderCategory.payment,
        providerId: 'iyzico',
        enabled: false,
        configuredByStaffId: 'owner-2',
        configuredAt: DateTime(2026, 1, 1),
        revision: 1,
      ));

      const session = PlatformActorSession(
        actorId: 'platform-1',
        roles: {PlatformRole.platformOwner},
        activeRole: PlatformRole.platformOwner,
      );
      final useCase = BuildPlatformMonitoringSnapshot(
        authorizationPolicy:
            RealPlatformAuthorizationPolicy(currentSession: () => session),
        organizationRepository: organizationRepository,
        platformMemberRepository: platformMemberRepository,
        tenantIntegrationRepository: tenantIntegrationRepository,
      );

      final snapshot = await useCase(actorId: 'platform-1');

      expect(snapshot.organizationCount, 2);
      expect(snapshot.platformMemberCount, 1);
      expect(snapshot.tenantIntegrationEnabledCount, 1);
      expect(snapshot.dormantServiceNotes, isNotEmpty);
    });

    test('an unauthorized actor is denied', () async {
      final useCase = BuildPlatformMonitoringSnapshot(
        authorizationPolicy:
            RealPlatformAuthorizationPolicy(currentSession: () => null),
        organizationRepository: InMemoryOrganizationRepository(),
        platformMemberRepository: InMemoryPlatformMemberRepository(),
        tenantIntegrationRepository:
            InMemoryTenantIntegrationConfigurationRepository(),
      );

      expect(
        () => useCase(actorId: 'platform-1'),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test(
        'a plain platformAdministrator (not owner) can still view '
        'monitoring — administrator-tier action', () async {
      const session = PlatformActorSession(
        actorId: 'admin-1',
        roles: {PlatformRole.platformAdministrator},
        activeRole: PlatformRole.platformAdministrator,
      );
      final useCase = BuildPlatformMonitoringSnapshot(
        authorizationPolicy:
            RealPlatformAuthorizationPolicy(currentSession: () => session),
        organizationRepository: InMemoryOrganizationRepository(),
        platformMemberRepository: InMemoryPlatformMemberRepository(),
        tenantIntegrationRepository:
            InMemoryTenantIntegrationConfigurationRepository(),
      );

      final snapshot = await useCase(actorId: 'admin-1');

      expect(snapshot.organizationCount, 0);
    });
  });
}
