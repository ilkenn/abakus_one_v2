import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_assignment.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_assignment_status.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_failure.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_failure_reason.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_failure_responsibility.dart';
import 'package:abakus_one_v2/features/courier/domain/performance/courier_performance_builder.dart';
import 'package:flutter_test/flutter_test.dart';

DeliveryAssignment _assignment(DeliveryAssignmentStatus status) {
  return DeliveryAssignment(
    id: 'a-$status',
    deliveryId: 'delivery-1',
    courierId: 'courier-1',
    status: status,
    offeredAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

DeliveryFailure _failure(DeliveryFailureReason reason) {
  return DeliveryFailure(
    id: 'f-$reason',
    deliveryId: 'delivery-1',
    reasonCode: reason,
    courierNote: '',
    recordedByStaffId: 'staff-1',
    recordedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('CourierPerformanceBuilder', () {
    test('counts offered/accepted/rejected assignments correctly', () {
      final snapshot = CourierPerformanceBuilder.build(
        courierId: 'courier-1',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 2, 1),
        assignments: [
          _assignment(DeliveryAssignmentStatus.accepted),
          _assignment(DeliveryAssignmentStatus.rejected),
          _assignment(DeliveryAssignmentStatus.offered),
        ],
      );
      expect(snapshot.assignmentsOffered, 3);
      expect(snapshot.assignmentsAccepted, 1);
      expect(snapshot.assignmentsRejected, 1);
    });

    test('groups failures by responsibility, never conflating causes', () {
      final snapshot = CourierPerformanceBuilder.build(
        courierId: 'courier-1',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 2, 1),
        failures: [
          _failure(DeliveryFailureReason.customerRefused),
          _failure(DeliveryFailureReason.courierVehicleProblem),
          _failure(DeliveryFailureReason.courierOperationalProblem),
        ],
      );
      expect(
          snapshot
              .failedByResponsibility[DeliveryFailureResponsibility.customer],
          1);
      expect(
          snapshot
              .failedByResponsibility[DeliveryFailureResponsibility.courier],
          2);
    });

    test(
        'never produces a score, rank, or punishment field — the snapshot '
        'type itself has no such field', () {
      final snapshot = CourierPerformanceBuilder.build(
        courierId: 'courier-1',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 2, 1),
      );
      // Structural assertion: only the explicitly-named operational
      // metrics exist. Compile-time enforced by CourierPerformanceSnapshot
      // having no score/rank field at all; here we just confirm the
      // builder doesn't silently derive one from defaults.
      expect(snapshot.assignmentsOffered, 0);
      expect(snapshot.successfulDeliveries, 0);
    });
  });
}
