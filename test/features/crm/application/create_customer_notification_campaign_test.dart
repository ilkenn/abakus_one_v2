import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/crm/application/identity/customer_notification_campaign_id_generator.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/create_customer_notification_campaign.dart';
import 'package:abakus_one_v2/features/crm/data/crm_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/crm/data/customer_notification_campaign_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/notifications/customer_notification_campaign_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/crm_test_fixtures.dart';

void main() {
  group('CreateCustomerNotificationCampaign', () {
    test('creates a draft campaign', () async {
      final repository = InMemoryCustomerNotificationCampaignRepository();
      final useCase = CreateCustomerNotificationCampaign(
        authorizationPolicy: const AllowAllCrmPolicy(),
        idGenerator: SequentialCustomerNotificationCampaignIdGenerator(),
        repository: repository,
        auditRepository: InMemoryCrmAuditEntryRepository(),
      );

      final campaign = await useCase(
        title: 'Hoş Geldin',
        body: 'Bize tekrar uğrayın!',
        performedByStaffId: 'manager-1',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(campaign.status, CustomerNotificationCampaignStatus.draft);
      expect(await repository.findById(campaign.id), campaign);
    });

    test('an unauthorized actor cannot create a campaign', () async {
      final useCase = CreateCustomerNotificationCampaign(
        authorizationPolicy: const DenyAllCrmPolicy(),
        idGenerator: SequentialCustomerNotificationCampaignIdGenerator(),
        repository: InMemoryCustomerNotificationCampaignRepository(),
        auditRepository: InMemoryCrmAuditEntryRepository(),
      );

      expect(
        () => useCase(
          title: 'Hoş Geldin',
          body: 'Bize tekrar uğrayın!',
          performedByStaffId: 'staff-1',
          createdAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
