import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/integrations/application/use_cases/build_integration_audit_center_projection.dart';
import 'package:abakus_one_v2/features/integrations/data/integration_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/integrations/domain/audit/integration_audit_entry.dart';
import 'package:abakus_one_v2/features/integrations/domain/audit/integration_audit_event_type.dart';
import 'package:abakus_one_v2/features/marketplace/data/marketplace_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/marketplace/domain/audit/marketplace_audit_entry.dart';
import 'package:abakus_one_v2/features/marketplace/domain/audit/marketplace_audit_event_type.dart';
import 'package:abakus_one_v2/features/payment_hub/data/payment_hub_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/payment_hub/domain/audit/payment_hub_audit_entry.dart';
import 'package:abakus_one_v2/features/payment_hub/domain/audit/payment_hub_audit_event_type.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/actor_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/real_pos_authorization_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/staff_role.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/integration_test_fixtures.dart';

class _ThrowingIntegrationAuditEntryRepository
    implements IntegrationAuditEntryRepository {
  @override
  Future<void> appendEvent(IntegrationAuditEntry entry) =>
      throw StateError('Repository must never be queried before authorization');

  @override
  Future<List<IntegrationAuditEntry>> findByTargetEntityId(
          String targetEntityId) =>
      throw StateError('Repository must never be queried before authorization');

  @override
  Future<List<IntegrationAuditEntry>> findByOrganizationId(
          String organizationId) =>
      throw StateError('Repository must never be queried before authorization');
}

class _ThrowingMarketplaceAuditEntryRepository
    implements MarketplaceAuditEntryRepository {
  @override
  Future<void> appendEvent(MarketplaceAuditEntry entry) =>
      throw StateError('Repository must never be queried before authorization');

  @override
  Future<List<MarketplaceAuditEntry>> findByTargetEntityId(
          String targetEntityId) =>
      throw StateError('Repository must never be queried before authorization');

  @override
  Future<List<MarketplaceAuditEntry>> findByOrganizationId(
          String organizationId) =>
      throw StateError('Repository must never be queried before authorization');
}

class _ThrowingPaymentHubAuditEntryRepository
    implements PaymentHubAuditEntryRepository {
  @override
  Future<void> appendEvent(PaymentHubAuditEntry entry) =>
      throw StateError('Repository must never be queried before authorization');

  @override
  Future<List<PaymentHubAuditEntry>> findByTargetEntityId(
          String targetEntityId) =>
      throw StateError('Repository must never be queried before authorization');

  @override
  Future<List<PaymentHubAuditEntry>> findByOrganizationId(
          String organizationId) =>
      throw StateError('Repository must never be queried before authorization');
}

void main() {
  group('BuildIntegrationAuditCenterProjection', () {
    test(
        'merges all 3 source trails, tagged by domain, sorted newest '
        'first', () async {
      final integrationRepo = InMemoryIntegrationAuditEntryRepository();
      await integrationRepo.appendEvent(IntegrationAuditEntry(
        id: 'int-1',
        organizationId: 'org-1',
        actorId: 'owner-1',
        type: IntegrationAuditEventType.tenantIntegrationEnabled,
        description: 'enabled',
        targetEntityId: 'config-1',
        timestamp: DateTime(2026, 1, 1),
      ));

      final marketplaceRepo = InMemoryMarketplaceAuditEntryRepository();
      await marketplaceRepo.appendEvent(MarketplaceAuditEntry(
        id: 'mkt-1',
        organizationId: 'org-1',
        actorId: 'owner-1',
        type: MarketplaceAuditEventType.accountCreated,
        description: 'account created',
        targetEntityId: 'account-1',
        timestamp: DateTime(2026, 1, 3),
      ));

      final paymentHubRepo = InMemoryPaymentHubAuditEntryRepository();
      await paymentHubRepo.appendEvent(PaymentHubAuditEntry(
        id: 'pay-1',
        organizationId: 'org-1',
        actorId: 'owner-1',
        type: PaymentHubAuditEventType.merchantAccountCreated,
        description: 'merchant account created',
        targetEntityId: 'merchant-1',
        timestamp: DateTime(2026, 1, 2),
      ));

      final useCase = BuildIntegrationAuditCenterProjection(
        authorizationPolicy: const AllowAllIntegrationPolicy(),
        integrationAuditRepository: integrationRepo,
        marketplaceAuditRepository: marketplaceRepo,
        paymentHubAuditRepository: paymentHubRepo,
      );

      final entries = await useCase(
        organizationId: 'org-1',
        actorStaffId: 'owner-1',
      );

      expect(entries, hasLength(3));
      expect(entries.map((e) => e.domain),
          ['marketplace', 'payment-hub', 'integration']);
    });

    test('never includes a different organization\'s entries', () async {
      final integrationRepo = InMemoryIntegrationAuditEntryRepository();
      await integrationRepo.appendEvent(IntegrationAuditEntry(
        id: 'int-1',
        organizationId: 'org-2',
        actorId: 'owner-1',
        type: IntegrationAuditEventType.tenantIntegrationEnabled,
        description: 'enabled',
        targetEntityId: 'config-1',
        timestamp: DateTime(2026, 1, 1),
      ));

      final useCase = BuildIntegrationAuditCenterProjection(
        authorizationPolicy: const AllowAllIntegrationPolicy(),
        integrationAuditRepository: integrationRepo,
        marketplaceAuditRepository: InMemoryMarketplaceAuditEntryRepository(),
        paymentHubAuditRepository: InMemoryPaymentHubAuditEntryRepository(),
      );

      final entries = await useCase(
        organizationId: 'org-1',
        actorStaffId: 'owner-1',
      );

      expect(entries, isEmpty);
    });

    test('domain filter narrows to just that source', () async {
      final integrationRepo = InMemoryIntegrationAuditEntryRepository();
      await integrationRepo.appendEvent(IntegrationAuditEntry(
        id: 'int-1',
        organizationId: 'org-1',
        actorId: 'owner-1',
        type: IntegrationAuditEventType.tenantIntegrationEnabled,
        description: 'enabled',
        targetEntityId: 'config-1',
        timestamp: DateTime(2026, 1, 1),
      ));
      final marketplaceRepo = InMemoryMarketplaceAuditEntryRepository();
      await marketplaceRepo.appendEvent(MarketplaceAuditEntry(
        id: 'mkt-1',
        organizationId: 'org-1',
        actorId: 'owner-1',
        type: MarketplaceAuditEventType.accountCreated,
        description: 'account created',
        targetEntityId: 'account-1',
        timestamp: DateTime(2026, 1, 2),
      ));

      final useCase = BuildIntegrationAuditCenterProjection(
        authorizationPolicy: const AllowAllIntegrationPolicy(),
        integrationAuditRepository: integrationRepo,
        marketplaceAuditRepository: marketplaceRepo,
        paymentHubAuditRepository: InMemoryPaymentHubAuditEntryRepository(),
      );

      final entries = await useCase(
        organizationId: 'org-1',
        actorStaffId: 'owner-1',
        domain: 'marketplace',
      );

      expect(entries, hasLength(1));
      expect(entries.single.domain, 'marketplace');
    });

    test('limit caps the returned entries after sorting', () async {
      final integrationRepo = InMemoryIntegrationAuditEntryRepository();
      for (var i = 0; i < 5; i++) {
        await integrationRepo.appendEvent(IntegrationAuditEntry(
          id: 'int-$i',
          organizationId: 'org-1',
          actorId: 'owner-1',
          type: IntegrationAuditEventType.tenantIntegrationEnabled,
          description: 'enabled $i',
          targetEntityId: 'config-$i',
          timestamp: DateTime(2026, 1, i + 1),
        ));
      }

      final useCase = BuildIntegrationAuditCenterProjection(
        authorizationPolicy: const AllowAllIntegrationPolicy(),
        integrationAuditRepository: integrationRepo,
        marketplaceAuditRepository: InMemoryMarketplaceAuditEntryRepository(),
        paymentHubAuditRepository: InMemoryPaymentHubAuditEntryRepository(),
      );

      final entries = await useCase(
        organizationId: 'org-1',
        actorStaffId: 'owner-1',
        limit: 2,
      );

      expect(entries, hasLength(2));
      expect(entries.first.description, contains('4'));
    });

    group('independent authorization (Phase 8 closure sprint)', () {
      test('an authorized tenant owner succeeds', () async {
        const session = ActorSession(
          actorId: 'owner-1',
          roles: {StaffRole.tenantOwner},
          activeRole: StaffRole.tenantOwner,
          organizationAccess: {'org-1'},
        );
        final useCase = BuildIntegrationAuditCenterProjection(
          authorizationPolicy:
              RealPosAuthorizationPolicy(currentSession: () => session),
          integrationAuditRepository: InMemoryIntegrationAuditEntryRepository(),
          marketplaceAuditRepository: InMemoryMarketplaceAuditEntryRepository(),
          paymentHubAuditRepository: InMemoryPaymentHubAuditEntryRepository(),
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
        final useCase = BuildIntegrationAuditCenterProjection(
          authorizationPolicy:
              RealPosAuthorizationPolicy(currentSession: () => session),
          integrationAuditRepository:
              _ThrowingIntegrationAuditEntryRepository(),
          marketplaceAuditRepository:
              _ThrowingMarketplaceAuditEntryRepository(),
          paymentHubAuditRepository: _ThrowingPaymentHubAuditEntryRepository(),
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
        final useCase = BuildIntegrationAuditCenterProjection(
          authorizationPolicy:
              RealPosAuthorizationPolicy(currentSession: () => session),
          integrationAuditRepository:
              _ThrowingIntegrationAuditEntryRepository(),
          marketplaceAuditRepository:
              _ThrowingMarketplaceAuditEntryRepository(),
          paymentHubAuditRepository: _ThrowingPaymentHubAuditEntryRepository(),
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
        final useCase = BuildIntegrationAuditCenterProjection(
          authorizationPolicy:
              RealPosAuthorizationPolicy(currentSession: () => session),
          integrationAuditRepository:
              _ThrowingIntegrationAuditEntryRepository(),
          marketplaceAuditRepository:
              _ThrowingMarketplaceAuditEntryRepository(),
          paymentHubAuditRepository: _ThrowingPaymentHubAuditEntryRepository(),
        );

        expect(
          () => useCase(organizationId: 'org-1', actorStaffId: 'owner-1'),
          throwsA(isA<AuthorizationDeniedViolation>()),
        );
      });

      test(
          'no repository is ever queried before authorization succeeds — '
          'throwing repositories surface AuthorizationDeniedViolation, '
          'never a repository error', () async {
        final useCase = BuildIntegrationAuditCenterProjection(
          authorizationPolicy: const DenyAllIntegrationPolicy(),
          integrationAuditRepository:
              _ThrowingIntegrationAuditEntryRepository(),
          marketplaceAuditRepository:
              _ThrowingMarketplaceAuditEntryRepository(),
          paymentHubAuditRepository: _ThrowingPaymentHubAuditEntryRepository(),
        );

        await expectLater(
          () => useCase(organizationId: 'org-1', actorStaffId: 'owner-1'),
          throwsA(isA<AuthorizationDeniedViolation>()),
        );
      });
    });
  });
}
