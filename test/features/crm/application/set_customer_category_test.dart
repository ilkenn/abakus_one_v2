import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/set_customer_category.dart';
import 'package:abakus_one_v2/features/crm/data/crm_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/crm/data/customer_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/audit/crm_audit_event_type.dart';
import 'package:abakus_one_v2/features/crm/domain/segmentation/customer_category.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/crm_test_fixtures.dart';

void main() {
  group('SetCustomerCategory', () {
    test('sets a predefined category', () async {
      final repository = InMemoryCustomerRepository();
      await repository.save(buildTestCustomer());
      final useCase = SetCustomerCategory(
        repository: repository,
        auditRepository: InMemoryCrmAuditEntryRepository(),
      );

      final updated = await useCase(
        customerId: 'customer-1',
        category: CustomerCategory.student,
        performedAt: DateTime(2026, 1, 1),
      );

      expect(updated.category, CustomerCategory.student);
      expect(updated.revision, 2);
    });

    test('keeps the custom label only when the category is "other"', () async {
      final repository = InMemoryCustomerRepository();
      await repository.save(buildTestCustomer());
      final useCase = SetCustomerCategory(
        repository: repository,
        auditRepository: InMemoryCrmAuditEntryRepository(),
      );

      final asOther = await useCase(
        customerId: 'customer-1',
        category: CustomerCategory.other,
        customCategoryLabel: 'Emekli',
        performedAt: DateTime(2026, 1, 1),
      );
      expect(asOther.category, CustomerCategory.other);
      expect(asOther.customCategoryLabel, 'Emekli');

      final switchedAway = await useCase(
        customerId: 'customer-1',
        category: CustomerCategory.student,
        customCategoryLabel: 'Emekli',
        performedAt: DateTime(2026, 1, 2),
      );
      expect(switchedAway.category, CustomerCategory.student);
      expect(switchedAway.customCategoryLabel, isNull);
    });

    test('a null category clears the existing selection', () async {
      final repository = InMemoryCustomerRepository();
      await repository
          .save(buildTestCustomer(category: CustomerCategory.student));
      final useCase = SetCustomerCategory(
        repository: repository,
        auditRepository: InMemoryCrmAuditEntryRepository(),
      );

      final cleared = await useCase(
        customerId: 'customer-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(cleared.category, isNull);
    });

    test('an unknown customer id throws UnknownCrmEntityViolation', () async {
      final useCase = SetCustomerCategory(
        repository: InMemoryCustomerRepository(),
        auditRepository: InMemoryCrmAuditEntryRepository(),
      );

      expect(
        () => useCase(
          customerId: 'missing',
          category: CustomerCategory.student,
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownCrmEntityViolation>()),
      );
    });

    test(
        'records a CrmAuditEntry with the customer as its own actor '
        '(self-service, not an admin action)', () async {
      final repository = InMemoryCustomerRepository();
      await repository.save(buildTestCustomer());
      final auditRepository = InMemoryCrmAuditEntryRepository();
      final useCase = SetCustomerCategory(
        repository: repository,
        auditRepository: auditRepository,
      );

      await useCase(
        customerId: 'customer-1',
        category: CustomerCategory.student,
        performedAt: DateTime(2026, 1, 1),
      );

      final entries = await auditRepository.findByActorId('customer-1');
      expect(entries, hasLength(1));
      expect(entries.single.actorRole, 'customer');
      expect(entries.single.type, CrmAuditEventType.customerCategoryChanged);
      expect(entries.single.targetEntityId, 'customer-1');
    });
  });

  group('CustomerRepository.findByCategory', () {
    test('returns only customers matching the requested category', () async {
      final repository = InMemoryCustomerRepository();
      await repository.save(buildTestCustomer(
        id: 'customer-1',
        category: CustomerCategory.student,
      ));
      await repository.save(buildTestCustomer(
        id: 'customer-2',
        category: CustomerCategory.healthcare,
      ));
      await repository.save(buildTestCustomer(
        id: 'customer-3',
        category: CustomerCategory.student,
      ));
      await repository.save(buildTestCustomer(id: 'customer-4'));

      final students =
          await repository.findByCategory(CustomerCategory.student);

      expect(students.map((c) => c.id).toSet(), {'customer-1', 'customer-3'});
    });
  });
}
