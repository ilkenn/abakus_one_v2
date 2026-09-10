import 'package:abakus_one_v2/features/courier/domain/dispatch/courier_return_fifo.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier_status.dart';
import 'package:flutter_test/flutter_test.dart';

Courier _courier(
  String id, {
  CourierStatus dispatchStatus = CourierStatus.available,
  DateTime? returnedAt,
}) {
  return Courier(
    id: id,
    primaryBranchId: 'branch-1',
    displayName: 'Courier $id',
    phoneNumber: '+905551112233',
    registeredAt: DateTime(2026, 1, 1),
    dispatchStatus: dispatchStatus,
    returnedAt: returnedAt,
  );
}

void main() {
  group('CourierReturnFifo.sortAvailableByReturnTime', () {
    test('sorts available couriers oldest returnedAt first', () {
      final couriers = [
        _courier('c1', returnedAt: DateTime(2026, 1, 1, 12, 0)),
        _courier('c2', returnedAt: DateTime(2026, 1, 1, 10, 0)),
        _courier('c3', returnedAt: DateTime(2026, 1, 1, 11, 0)),
      ];

      final sorted = CourierReturnFifo.sortAvailableByReturnTime(couriers);

      expect(sorted.map((c) => c.id).toList(), ['c2', 'c3', 'c1']);
    });

    test('a courier with a null returnedAt sorts last, never recommended first', () {
      final couriers = [
        _courier('c1', returnedAt: null),
        _courier('c2', returnedAt: DateTime(2026, 1, 1, 10, 0)),
      ];

      final sorted = CourierReturnFifo.sortAvailableByReturnTime(couriers);

      expect(sorted.map((c) => c.id).toList(), ['c2', 'c1']);
    });

    test('excludes couriers that are not dispatchStatus.available', () {
      final couriers = [
        _courier('c1', dispatchStatus: CourierStatus.delivering, returnedAt: DateTime(2026, 1, 1)),
        _courier('c2', dispatchStatus: CourierStatus.offline, returnedAt: DateTime(2026, 1, 1)),
        _courier('c3', dispatchStatus: CourierStatus.available, returnedAt: DateTime(2026, 1, 1)),
      ];

      final sorted = CourierReturnFifo.sortAvailableByReturnTime(couriers);

      expect(sorted.map((c) => c.id).toList(), ['c3']);
    });

    test('empty input yields empty output', () {
      expect(CourierReturnFifo.sortAvailableByReturnTime(const []), isEmpty);
    });
  });
}
