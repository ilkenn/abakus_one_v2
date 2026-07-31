import 'package:abakus_one_v2/features/crm/data/customer_visit_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/visits/customer_visit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryCustomerVisitRepository — findByOrderId', () {
    test('returns null when no visit references the given orderId', () async {
      final repository = InMemoryCustomerVisitRepository();
      expect(await repository.findByOrderId('order-1'), isNull);
    });

    test('returns the visit that references the given orderId', () async {
      final repository = InMemoryCustomerVisitRepository();
      final visit = CustomerVisit(
        id: 'visit-1',
        customerId: 'customer-1',
        branchId: 'branch-1',
        orderId: 'order-1',
        occurredAt: DateTime(2026, 1, 1),
      );
      await repository.append(visit);

      expect(await repository.findByOrderId('order-1'), visit);
    });

    test('never matches a visit recorded with no order reference', () async {
      final repository = InMemoryCustomerVisitRepository();
      await repository.append(CustomerVisit(
        id: 'visit-1',
        customerId: 'customer-1',
        branchId: 'branch-1',
        occurredAt: DateTime(2026, 1, 1),
      ));

      expect(await repository.findByOrderId('order-1'), isNull);
    });
  });
}
