import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/set_customer_category.dart';
import 'package:abakus_one_v2/features/crm/data/customer_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/segmentation/customer_category.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/crm_test_fixtures.dart';

void main() {
  group('SetCustomerCategory', () {
    test('sets a predefined category', () async {
      final repository = InMemoryCustomerRepository();
      await repository.save(buildTestCustomer());
      final useCase = SetCustomerCategory(repository: repository);

      final updated = await useCase(
        customerId: 'customer-1',
        category: CustomerCategory.student,
      );

      expect(updated.category, CustomerCategory.student);
      expect(updated.revision, 2);
    });

    test('keeps the custom label only when the category is "other"', () async {
      final repository = InMemoryCustomerRepository();
      await repository.save(buildTestCustomer());
      final useCase = SetCustomerCategory(repository: repository);

      final asOther = await useCase(
        customerId: 'customer-1',
        category: CustomerCategory.other,
        customCategoryLabel: 'Emekli',
      );
      expect(asOther.category, CustomerCategory.other);
      expect(asOther.customCategoryLabel, 'Emekli');

      final switchedAway = await useCase(
        customerId: 'customer-1',
        category: CustomerCategory.student,
        customCategoryLabel: 'Emekli',
      );
      expect(switchedAway.category, CustomerCategory.student);
      expect(switchedAway.customCategoryLabel, isNull);
    });

    test('a null category clears the existing selection', () async {
      final repository = InMemoryCustomerRepository();
      await repository
          .save(buildTestCustomer(category: CustomerCategory.student));
      final useCase = SetCustomerCategory(repository: repository);

      final cleared = await useCase(customerId: 'customer-1');

      expect(cleared.category, isNull);
    });

    test('an unknown customer id throws UnknownCrmEntityViolation', () async {
      final useCase =
          SetCustomerCategory(repository: InMemoryCustomerRepository());

      expect(
        () => useCase(
          customerId: 'missing',
          category: CustomerCategory.student,
        ),
        throwsA(isA<UnknownCrmEntityViolation>()),
      );
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
