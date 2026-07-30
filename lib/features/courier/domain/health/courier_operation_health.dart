import 'courier_operation_health_level.dart';

/// The branch's computed operational health snapshot — Sprint 5C Part 13.
/// Never persisted itself, always rebuildable from the same underlying
/// `Delivery`/`CourierLiveWarning` signals `BuildCourierOperationHealth`
/// reads. Every count is carried alongside [level] so the manager screen
/// can explain *why* the indicator is showing what it's showing, not just
/// the color.
class CourierOperationHealth {
  const CourierOperationHealth({
    required this.branchId,
    required this.level,
    required this.delayedDeliveryCount,
    required this.offlineCourierCount,
    required this.gpsFailureCount,
    required this.waitingDeliveryCount,
    required this.operationalAlarmCount,
    required this.computedAt,
  });

  final String branchId;
  final CourierOperationHealthLevel level;

  /// Active deliveries older than the calculator's delay threshold.
  final int delayedDeliveryCount;

  /// From `CourierLiveWarningType.courierOffline`.
  final int offlineCourierCount;

  /// From `CourierLiveWarningType.gpsDisabled`.
  final int gpsFailureCount;

  /// Active deliveries still in `DeliveryStatus.readyForAssignment`.
  final int waitingDeliveryCount;

  /// From `CourierLiveWarningType.operationalRisk`/`.abnormalRoute`.
  final int operationalAlarmCount;

  final DateTime computedAt;
}
