import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/crm/application/identity/customer_visit_id_generator.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/record_customer_visit.dart';
import 'package:abakus_one_v2/features/crm/data/customer_repository.dart';
import 'package:abakus_one_v2/features/crm/data/customer_visit_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/crm_test_fixtures.dart';

void main() {
  group('RecordCustomerVisit', () {
    test('records a visit for an existing customer', () async {
      final customerRepository = InMemoryCustomerRepository();
      await customerRepository.save(buildTestCustomer());
      final visitRepository = InMemoryCustomerVisitRepository();
      final useCase = RecordCustomerVisit(
        idGenerator: SequentialCustomerVisitIdGenerator(),
        customerRepository: customerRepository,
        visitRepository: visitRepository,
      );

      final visit = await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
        occurredAt: DateTime(2026, 1, 1, 12),
      );

      expect(visit.customerId, 'customer-1');
      final history = await visitRepository.findByCustomerId('customer-1');
      expect(history, [visit]);
    });

    test('an unknown customer id throws UnknownCrmEntityViolation', () async {
      final useCase = RecordCustomerVisit(
        idGenerator: SequentialCustomerVisitIdGenerator(),
        customerRepository: InMemoryCustomerRepository(),
        visitRepository: InMemoryCustomerVisitRepository(),
      );

      expect(
        () => useCase(
          customerId: 'missing',
          branchId: 'branch-1',
          occurredAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownCrmEntityViolation>()),
      );
    });

    test('multiple visits accumulate in customer-visit-id order', () async {
      final customerRepository = InMemoryCustomerRepository();
      await customerRepository.save(buildTestCustomer());
      final visitRepository = InMemoryCustomerVisitRepository();
      final useCase = RecordCustomerVisit(
        idGenerator: SequentialCustomerVisitIdGenerator(),
        customerRepository: customerRepository,
        visitRepository: visitRepository,
      );

      await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
        occurredAt: DateTime(2026, 1, 1),
      );
      await useCase(
        customerId: 'customer-1',
        branchId: 'branch-1',
        occurredAt: DateTime(2026, 1, 2),
      );

      final history = await visitRepository.findByCustomerId('customer-1');
      expect(history, hasLength(2));
    });
  });
}
