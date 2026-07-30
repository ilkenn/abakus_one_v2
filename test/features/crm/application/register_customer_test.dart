import 'package:abakus_one_v2/features/crm/application/identity/customer_id_generator.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/register_customer.dart';
import 'package:abakus_one_v2/features/crm/data/customer_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RegisterCustomer', () {
    test('registers a customer with no category and persists it', () async {
      final repository = InMemoryCustomerRepository();
      final useCase = RegisterCustomer(
        idGenerator: SequentialCustomerIdGenerator(),
        repository: repository,
      );

      final customer = await useCase(
        displayName: 'Ayşe Yılmaz',
        phoneNumber: '+905551234567',
        registeredAt: DateTime(2026, 1, 1, 10),
      );

      expect(customer.id, 'customer-1');
      expect(customer.category, isNull);
      expect(customer.revision, 1);
      expect(await repository.findById(customer.id), customer);
    });

    test('each registration gets a distinct sequential id', () async {
      final useCase = RegisterCustomer(
        idGenerator: SequentialCustomerIdGenerator(),
        repository: InMemoryCustomerRepository(),
      );

      final first = await useCase(
        displayName: 'A',
        phoneNumber: '+905550000001',
        registeredAt: DateTime(2026, 1, 1),
      );
      final second = await useCase(
        displayName: 'B',
        phoneNumber: '+905550000002',
        registeredAt: DateTime(2026, 1, 1),
      );

      expect(first.id, isNot(second.id));
    });
  });
}
