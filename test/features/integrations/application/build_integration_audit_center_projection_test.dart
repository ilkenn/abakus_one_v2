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
import 'package:flutter_test/flutter_test.dart';

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
        integrationAuditRepository: integrationRepo,
        marketplaceAuditRepository: marketplaceRepo,
        paymentHubAuditRepository: paymentHubRepo,
      );

      final entries = await useCase(organizationId: 'org-1');

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
        integrationAuditRepository: integrationRepo,
        marketplaceAuditRepository: InMemoryMarketplaceAuditEntryRepository(),
        paymentHubAuditRepository: InMemoryPaymentHubAuditEntryRepository(),
      );

      final entries = await useCase(organizationId: 'org-1');

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
        integrationAuditRepository: integrationRepo,
        marketplaceAuditRepository: marketplaceRepo,
        paymentHubAuditRepository: InMemoryPaymentHubAuditEntryRepository(),
      );

      final entries =
          await useCase(organizationId: 'org-1', domain: 'marketplace');

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
        integrationAuditRepository: integrationRepo,
        marketplaceAuditRepository: InMemoryMarketplaceAuditEntryRepository(),
        paymentHubAuditRepository: InMemoryPaymentHubAuditEntryRepository(),
      );

      final entries = await useCase(organizationId: 'org-1', limit: 2);

      expect(entries, hasLength(2));
      expect(entries.first.description, contains('4'));
    });
  });
}
