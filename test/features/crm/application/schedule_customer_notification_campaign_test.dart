import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/schedule_customer_notification_campaign.dart';
import 'package:abakus_one_v2/features/crm/data/customer_notification_campaign_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/notifications/customer_notification_campaign.dart';
import 'package:abakus_one_v2/features/crm/domain/notifications/customer_notification_campaign_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/crm_test_fixtures.dart';

CustomerNotificationCampaign _draftCampaign() {
  return CustomerNotificationCampaign(
    id: 'campaign-1',
    title: 'Hoş Geldin',
    body: 'Bize tekrar uğrayın!',
    createdByStaffId: 'manager-1',
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

void main() {
  group('ScheduleCustomerNotificationCampaign', () {
    test('moves a draft campaign to scheduled and records scheduledFor',
        () async {
      final repository = InMemoryCustomerNotificationCampaignRepository();
      await repository.save(_draftCampaign());
      final useCase = ScheduleCustomerNotificationCampaign(
        authorizationPolicy: const AllowAllCrmPolicy(),
        repository: repository,
      );

      final updated = await useCase(
        campaignId: 'campaign-1',
        scheduledFor: DateTime(2026, 2, 1),
        performedByStaffId: 'manager-1',
      );

      expect(updated.status, CustomerNotificationCampaignStatus.scheduled);
      expect(updated.scheduledFor, DateTime(2026, 2, 1));
    });

    test('an already-scheduled campaign cannot be scheduled again', () async {
      final repository = InMemoryCustomerNotificationCampaignRepository();
      await repository.save(_draftCampaign().copyWith(
        status: CustomerNotificationCampaignStatus.scheduled,
        revision: 2,
      ));
      final useCase = ScheduleCustomerNotificationCampaign(
        authorizationPolicy: const AllowAllCrmPolicy(),
        repository: repository,
      );

      expect(
        () => useCase(
          campaignId: 'campaign-1',
          scheduledFor: DateTime(2026, 2, 1),
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<InvalidNotificationCampaignTransitionViolation>()),
      );
    });

    test('an unknown campaign id throws UnknownCrmEntityViolation', () async {
      final useCase = ScheduleCustomerNotificationCampaign(
        authorizationPolicy: const AllowAllCrmPolicy(),
        repository: InMemoryCustomerNotificationCampaignRepository(),
      );

      expect(
        () => useCase(
          campaignId: 'missing',
          scheduledFor: DateTime(2026, 2, 1),
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<UnknownCrmEntityViolation>()),
      );
    });

    test('an unauthorized actor cannot schedule a campaign', () async {
      final repository = InMemoryCustomerNotificationCampaignRepository();
      await repository.save(_draftCampaign());
      final useCase = ScheduleCustomerNotificationCampaign(
        authorizationPolicy: const DenyAllCrmPolicy(),
        repository: repository,
      );

      expect(
        () => useCase(
          campaignId: 'campaign-1',
          scheduledFor: DateTime(2026, 2, 1),
          performedByStaffId: 'staff-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
