import 'package:abakus_one_v2/features/crm/application/identity/customer_id_generator.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/register_customer.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/resolve_current_customer.dart';
import 'package:abakus_one_v2/features/crm/data/customer_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResolveCurrentCustomer', () {
    test(
        'registers a new customer, keyed by the canonical uid, the first '
        'time it is seen', () async {
      final repository = InMemoryCustomerRepository();
      final useCase = ResolveCurrentCustomer(
        repository: repository,
        registerCustomer: RegisterCustomer(
          idGenerator: SequentialCustomerIdGenerator(),
          repository: repository,
        ),
      );

      final customer = await useCase(
        uid: 'uid-1',
        phoneNumber: '+905551234567',
        displayName: '+905551234567',
        now: DateTime(2026, 1, 1),
      );

      expect(customer.id, 'uid-1');
      expect(customer.phoneNumber, '+905551234567');
      expect(await repository.findById('uid-1'), customer);
    });

    test(
        'resolves to the same customer id on every repeated call — '
        'idempotent, never a duplicate registration', () async {
      final repository = InMemoryCustomerRepository();
      final useCase = ResolveCurrentCustomer(
        repository: repository,
        registerCustomer: RegisterCustomer(
          idGenerator: SequentialCustomerIdGenerator(),
          repository: repository,
        ),
      );

      final first = await useCase(
        uid: 'uid-1',
        phoneNumber: '+905551234567',
        displayName: '+905551234567',
        now: DateTime(2026, 1, 1),
      );
      final second = await useCase(
        uid: 'uid-1',
        phoneNumber: '+905551234567',
        displayName: '+905551234567',
        now: DateTime(2026, 1, 2),
      );
      final third = await useCase(
        uid: 'uid-1',
        phoneNumber: '+905551234567',
        displayName: '+905551234567',
        now: DateTime(2026, 1, 3),
      );

      expect(second.id, first.id);
      expect(third.id, first.id);
      expect(first.id, 'uid-1');
      expect(await repository.findAll(), hasLength(1));
    });

    test('different uids resolve to different customers', () async {
      final repository = InMemoryCustomerRepository();
      final useCase = ResolveCurrentCustomer(
        repository: repository,
        registerCustomer: RegisterCustomer(
          idGenerator: SequentialCustomerIdGenerator(),
          repository: repository,
        ),
      );

      final a = await useCase(
        uid: 'uid-1',
        phoneNumber: '+905550000001',
        displayName: '+905550000001',
        now: DateTime(2026, 1, 1),
      );
      final b = await useCase(
        uid: 'uid-2',
        phoneNumber: '+905550000002',
        displayName: '+905550000002',
        now: DateTime(2026, 1, 1),
      );

      expect(a.id, isNot(b.id));
    });
  });
}
