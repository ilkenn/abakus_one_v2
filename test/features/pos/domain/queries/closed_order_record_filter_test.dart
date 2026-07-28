import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/domain/models/order_closure.dart';
import 'package:abakus_one_v2/features/pos/domain/models/order_closure_lifecycle_status.dart';
import 'package:abakus_one_v2/features/pos/domain/queries/closed_order_record_filter.dart';
import 'package:flutter_test/flutter_test.dart';

OrderClosure _closure({
  String closureId = 'c1',
  DateTime? closedAt,
  String? closedByStaffId,
  OrderClosureLifecycleStatus status = OrderClosureLifecycleStatus.closed,
}) {
  return OrderClosure(
    closureId: closureId,
    orderId: OrderId('order-1'),
    closedAt: closedAt,
    closedByStaffId: closedByStaffId,
    lifecycleStatus: status,
    revision: 1,
  );
}

void main() {
  group('ClosedOrderRecordFilter', () {
    test('with no criteria, matches everything', () {
      const filter = ClosedOrderRecordFilter();
      expect(filter.matches(_closure()), isTrue);
    });

    test('filters by closedFrom/closedTo range', () {
      final filter = ClosedOrderRecordFilter(
        closedFrom: DateTime(2026, 7, 1),
        closedTo: DateTime(2026, 7, 31),
      );

      expect(filter.matches(_closure(closedAt: DateTime(2026, 7, 15))), isTrue);
      expect(filter.matches(_closure(closedAt: DateTime(2026, 8, 1))), isFalse);
      expect(filter.matches(_closure(closedAt: null)), isFalse);
    });

    test('filters by closedByStaffId', () {
      const filter = ClosedOrderRecordFilter(closedByStaffId: 'staff-1');

      expect(filter.matches(_closure(closedByStaffId: 'staff-1')), isTrue);
      expect(filter.matches(_closure(closedByStaffId: 'staff-2')), isFalse);
    });

    test('filters by lifecycleStatus', () {
      const filter = ClosedOrderRecordFilter(
        lifecycleStatus: OrderClosureLifecycleStatus.reopened,
      );

      expect(
        filter.matches(_closure(status: OrderClosureLifecycleStatus.reopened)),
        isTrue,
      );
      expect(
        filter.matches(_closure(status: OrderClosureLifecycleStatus.closed)),
        isFalse,
      );
    });

    test('apply filters a list, preserving order', () {
      const filter = ClosedOrderRecordFilter(closedByStaffId: 'staff-1');
      final records = [
        _closure(closureId: 'c1', closedByStaffId: 'staff-1'),
        _closure(closureId: 'c2', closedByStaffId: 'staff-2'),
        _closure(closureId: 'c3', closedByStaffId: 'staff-1'),
      ];

      final result = filter.apply(records);

      expect(result.map((c) => c.closureId), ['c1', 'c3']);
    });
  });
}
