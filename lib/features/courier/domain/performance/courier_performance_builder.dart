import '../delivery/delivery_assignment.dart';
import '../delivery/delivery_assignment_status.dart';
import '../delivery/delivery_failure.dart';
import 'courier_performance_snapshot.dart';

/// Builds a [CourierPerformanceSnapshot] from already-loaded, immutable
/// records — a pure function, no I/O, mirrors `ExpeditorProjectionBuilder`/
/// `KitchenOrderView.build`'s shape exactly.
abstract final class CourierPerformanceBuilder {
  CourierPerformanceBuilder._();

  static CourierPerformanceSnapshot build({
    required String courierId,
    required DateTime periodStart,
    required DateTime periodEnd,
    List<DeliveryAssignment> assignments = const [],
    List<DeliveryFailure> failures = const [],
    int successfulDeliveries = 0,
    int reassignmentCount = 0,
    int geofenceOverrideCount = 0,
    int customerContactAttempts = 0,
    Duration activeShiftDuration = Duration.zero,
    int packagesDelivered = 0,
  }) {
    final offered = assignments.length;
    final accepted = assignments
        .where((a) => a.status == DeliveryAssignmentStatus.accepted)
        .length;
    final rejected = assignments
        .where((a) => a.status == DeliveryAssignmentStatus.rejected)
        .length;

    final failedByResponsibility = <dynamic, int>{};
    for (final failure in failures) {
      failedByResponsibility[failure.responsibility] =
          (failedByResponsibility[failure.responsibility] ?? 0) + 1;
    }

    return CourierPerformanceSnapshot(
      courierId: courierId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      assignmentsOffered: offered,
      assignmentsAccepted: accepted,
      assignmentsRejected: rejected,
      successfulDeliveries: successfulDeliveries,
      failedByResponsibility: failedByResponsibility.cast(),
      reassignmentCount: reassignmentCount,
      geofenceOverrideCount: geofenceOverrideCount,
      customerContactAttempts: customerContactAttempts,
      activeShiftDuration: activeShiftDuration,
      packagesDelivered: packagesDelivered,
    );
  }
}
