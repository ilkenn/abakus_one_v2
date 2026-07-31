import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/schedule_customer_notification_campaign.dart';
import 'package:abakus_one_v2/features/crm/data/crm_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/crm/data/customer_notification_campaign_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/audit/crm_audit_event_type.dart';
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
        auditRepository: InMemoryCrmAuditEntryRepository(),
      );

      final updated = await useCase(
        campaignId: 'campaign-1',
        scheduledFor: DateTime(2026, 2, 1),
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 15),
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
        auditRepository: InMemoryCrmAuditEntryRepository(),
      );

      expect(
        () => useCase(
          campaignId: 'campaign-1',
          scheduledFor: DateTime(2026, 2, 1),
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 15),
        ),
        throwsA(isA<InvalidNotificationCampaignTransitionViolation>()),
      );
    });

    test('an unknown campaign id throws UnknownCrmEntityViolation', () async {
      final useCase = ScheduleCustomerNotificationCampaign(
        authorizationPolicy: const AllowAllCrmPolicy(),
        repository: InMemoryCustomerNotificationCampaignRepository(),
        auditRepository: InMemoryCrmAuditEntryRepository(),
      );

      expect(
        () => useCase(
          campaignId: 'missing',
          scheduledFor: DateTime(2026, 2, 1),
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 15),
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
        auditRepository: InMemoryCrmAuditEntryRepository(),
      );

      expect(
        () => useCase(
          campaignId: 'campaign-1',
          scheduledFor: DateTime(2026, 2, 1),
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 15),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test('records a CrmAuditEntry for the schedule action', () async {
      final repository = InMemoryCustomerNotificationCampaignRepository();
      await repository.save(_draftCampaign());
      final auditRepository = InMemoryCrmAuditEntryRepository();
      final useCase = ScheduleCustomerNotificationCampaign(
        authorizationPolicy: const AllowAllCrmPolicy(),
        repository: repository,
        auditRepository: auditRepository,
      );

      await useCase(
        campaignId: 'campaign-1',
        scheduledFor: DateTime(2026, 2, 1),
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 15),
      );

      final entries = await auditRepository.findByTargetEntityId('campaign-1');
      expect(entries.single.type,
          CrmAuditEventType.customerNotificationCampaignScheduled);
    });
  });
}
