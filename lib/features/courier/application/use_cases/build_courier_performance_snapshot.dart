import '../../data/customer_contact_action_repository.dart';
import '../../data/delivery_assignment_repository.dart';
import '../../data/delivery_failure_repository.dart';
import '../../data/delivery_repository.dart';
import '../../data/geofence_override_repository.dart';
import '../../domain/delivery/delivery_status.dart';
import '../../domain/performance/courier_performance_builder.dart';
import '../../domain/performance/courier_performance_snapshot.dart';

/// Wires [CourierPerformanceBuilder] to real repositories for one courier
/// over `[periodStart, periodEnd]`. The builder itself stays pure — this
/// use case is only the I/O-fetching, period-filtering shell around it.
///
/// Deliberately produces no score, rank, or punishment — matches
/// [CourierPerformanceSnapshot]'s own documented exclusion.
class BuildCourierPerformanceSnapshot {
  const BuildCourierPerformanceSnapshot({
    required DeliveryRepository deliveryRepository,
    required DeliveryAssignmentRepository assignmentRepository,
    required DeliveryFailureRepository failureRepository,
    required GeofenceOverrideRepository geofenceOverrideRepository,
    required CustomerContactActionRepository contactActionRepository,
  })  : _deliveryRepository = deliveryRepository,
        _assignmentRepository = assignmentRepository,
        _failureRepository = failureRepository,
        _geofenceOverrideRepository = geofenceOverrideRepository,
        _contactActionRepository = contactActionRepository;

  final DeliveryRepository _deliveryRepository;
  final DeliveryAssignmentRepository _assignmentRepository;
  final DeliveryFailureRepository _failureRepository;
  final GeofenceOverrideRepository _geofenceOverrideRepository;
  final CustomerContactActionRepository _contactActionRepository;

  Future<CourierPerformanceSnapshot> call({
    required String courierId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final deliveries = (await _deliveryRepository.findByCourierId(courierId))
        .where((d) =>
            !d.createdAt.isBefore(periodStart) &&
            d.createdAt.isBefore(periodEnd))
        .toList();
    final deliveryIds = deliveries.map((d) => d.id).toSet();

    final assignments = await _assignmentRepository.findByCourierId(courierId);
    final periodAssignments =
        assignments.where((a) => deliveryIds.contains(a.deliveryId)).toList();

    final allFailures = await _failureRepository.findAll();
    final periodFailures =
        allFailures.where((f) => deliveryIds.contains(f.deliveryId)).toList();

    final successfulDeliveries =
        deliveries.where((d) => d.status == DeliveryStatus.delivered).length;

    var geofenceOverrideCount = 0;
    var customerContactAttempts = 0;
    var reassignmentCount = 0;
    for (final id in deliveryIds) {
      geofenceOverrideCount +=
          (await _geofenceOverrideRepository.findByDeliveryId(id)).length;
      customerContactAttempts +=
          (await _contactActionRepository.findByDeliveryId(id)).length;
      final fullHistory = await _assignmentRepository.findByDeliveryId(id);
      if (fullHistory.length > 1) reassignmentCount += fullHistory.length - 1;
    }

    return CourierPerformanceBuilder.build(
      courierId: courierId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      assignments: periodAssignments,
      failures: periodFailures,
      successfulDeliveries: successfulDeliveries,
      reassignmentCount: reassignmentCount,
      geofenceOverrideCount: geofenceOverrideCount,
      customerContactAttempts: customerContactAttempts,
      packagesDelivered: successfulDeliveries,
    );
  }
}
