import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/admin/domain/reservations/admin_reservation_summary.dart';
import 'package:abakus_one_v2/features/reservation/domain/models/reservation_status.dart';

AdminReservationSummary _base({
  DateTime? confirmedTime,
  String? confirmedAreaId,
  String? assignedTableId,
  String? preorderOrderId,
}) {
  return AdminReservationSummary(
    id: 'reservation-1',
    status: ReservationStatus.pendingRestaurantApproval,
    partySize: 2,
    requestedTime: DateTime.utc(2026, 8, 20, 18, 0),
    requestedAreaId: 'area-garden',
    contactFirstName: 'Ada',
    contactLastName: 'Yılmaz',
    confirmedTime: confirmedTime,
    confirmedAreaId: confirmedAreaId,
    assignedTableId: assignedTableId,
    preorderOrderId: preorderOrderId,
  );
}

void main() {
  test('contactFullName joins first and last name with a single space', () {
    expect(_base().contactFullName, 'Ada Yılmaz');
  });

  test('effectiveAreaId falls back to requestedAreaId before confirmation', () {
    expect(_base().effectiveAreaId, 'area-garden');
  });

  test('effectiveAreaId prefers confirmedAreaId once set', () {
    expect(
        _base(confirmedAreaId: 'area-indoor').effectiveAreaId, 'area-indoor');
  });

  test('effectiveTime falls back to requestedTime before confirmation', () {
    expect(_base().effectiveTime, DateTime.utc(2026, 8, 20, 18, 0));
  });

  test('effectiveTime prefers confirmedTime once set', () {
    final confirmed = DateTime.utc(2026, 8, 20, 19, 30);
    expect(_base(confirmedTime: confirmed).effectiveTime, confirmed);
  });

  test('hasAssignedTable is false with no table, true once one is set', () {
    expect(_base().hasAssignedTable, isFalse);
    expect(_base(assignedTableId: 'table-1').hasAssignedTable, isTrue);
  });

  test('hasPreorder is false with no preorder, true once one is set', () {
    expect(_base().hasPreorder, isFalse);
    expect(_base(preorderOrderId: 'order-1').hasPreorder, isTrue);
  });
}
