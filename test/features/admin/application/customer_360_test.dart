import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/admin/application/identity/customer_admin_note_id_generator.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/add_customer_admin_note.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/set_customer_account_status.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/data/customer_admin_note_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/audit/admin_audit_event_type.dart';
import 'package:abakus_one_v2/features/crm/data/customer_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/segmentation/customer_account_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../crm/test_support/crm_test_fixtures.dart';
import '../test_support/admin_test_fixtures.dart';

void main() {
  group('SetCustomerAccountStatus', () {
    test('restricts and reinstates a customer account', () async {
      final repository = InMemoryCustomerRepository();
      await repository.save(buildTestCustomer());
      final auditRepository = InMemoryAdminAuditEntryRepository();
      final useCase = SetCustomerAccountStatus(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: auditRepository,
      );

      final restricted = await useCase(
        customerId: 'customer-1',
        newStatus: CustomerAccountStatus.restricted,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );
      expect(restricted.accountStatus, CustomerAccountStatus.restricted);

      final entries = await auditRepository.findByTargetEntityId('customer-1');
      expect(entries.single.type,
          AdminAuditEventType.customerAccountStatusChanged);
    });

    test('an unauthorized actor cannot restrict an account', () async {
      final repository = InMemoryCustomerRepository();
      await repository.save(buildTestCustomer());
      final useCase = SetCustomerAccountStatus(
        authorizationPolicy: const DenyAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          customerId: 'customer-1',
          newStatus: CustomerAccountStatus.restricted,
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });

  group('AddCustomerAdminNote', () {
    test('appends a note, optionally flagged', () async {
      final repository = InMemoryCustomerAdminNoteRepository();
      final useCase = AddCustomerAdminNote(
        authorizationPolicy: const AllowAllAdminPolicy(),
        idGenerator: SequentialCustomerAdminNoteIdGenerator(),
        repository: repository,
      );

      await useCase(
        customerId: 'customer-1',
        body: 'Şüpheli iade talebi',
        isFlag: true,
        performedByStaffId: 'staff-1',
        createdAt: DateTime(2026, 1, 1),
      );

      final notes = await repository.findByCustomerId('customer-1');
      expect(notes.single.isFlag, isTrue);
    });
  });
}
