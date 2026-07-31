import 'package:abakus_one_v2/features/crm/application/use_cases/resolve_notification_campaign_audience.dart';
import 'package:abakus_one_v2/features/crm/data/customer_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/notifications/customer_notification_campaign.dart';
import 'package:abakus_one_v2/features/crm/domain/segmentation/customer_category.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/crm_test_fixtures.dart';

CustomerNotificationCampaign _campaign({
  CustomerCategory? targetCategory,
  List<String> targetCustomerIds = const [],
}) {
  return CustomerNotificationCampaign(
    id: 'campaign-1',
    title: 'Hoş Geldin',
    body: 'Bize tekrar uğrayın!',
    targetCategory: targetCategory,
    targetCustomerIds: targetCustomerIds,
    createdByStaffId: 'manager-1',
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

void main() {
  group('ResolveNotificationCampaignAudience', () {
    test('an explicit id list wins over category targeting', () async {
      final repository = InMemoryCustomerRepository();
      await repository.save(buildTestCustomer(
        id: 'customer-1',
        category: CustomerCategory.student,
      ));
      await repository.save(buildTestCustomer(
        id: 'customer-2',
        category: CustomerCategory.healthcare,
      ));
      final useCase = ResolveNotificationCampaignAudience(
        customerRepository: repository,
      );

      final audience = await useCase(_campaign(
        targetCategory: CustomerCategory.student,
        targetCustomerIds: ['customer-2'],
      ));

      expect(audience.map((c) => c.id), ['customer-2']);
    });

    test('falls back to category targeting when no explicit ids are set',
        () async {
      final repository = InMemoryCustomerRepository();
      await repository.save(buildTestCustomer(
        id: 'customer-1',
        category: CustomerCategory.student,
      ));
      await repository.save(buildTestCustomer(
        id: 'customer-2',
        category: CustomerCategory.healthcare,
      ));
      final useCase = ResolveNotificationCampaignAudience(
        customerRepository: repository,
      );

      final audience =
          await useCase(_campaign(targetCategory: CustomerCategory.student));

      expect(audience.map((c) => c.id), ['customer-1']);
    });

    test('with no targeting at all, the audience is every customer', () async {
      final repository = InMemoryCustomerRepository();
      await repository.save(buildTestCustomer(id: 'customer-1'));
      await repository.save(buildTestCustomer(id: 'customer-2'));
      final useCase = ResolveNotificationCampaignAudience(
        customerRepository: repository,
      );

      final audience = await useCase(_campaign());

      expect(audience.map((c) => c.id).toSet(), {'customer-1', 'customer-2'});
    });

    test('an explicit id that no longer resolves to a customer is skipped',
        () async {
      final repository = InMemoryCustomerRepository();
      await repository.save(buildTestCustomer(id: 'customer-1'));
      final useCase = ResolveNotificationCampaignAudience(
        customerRepository: repository,
      );

      final audience = await useCase(
        _campaign(targetCustomerIds: ['customer-1', 'missing']),
      );

      expect(audience.map((c) => c.id), ['customer-1']);
    });
  });
}
