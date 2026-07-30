import '../../../../core/utils/clock.dart';
import '../../data/delivery_repository.dart';
import '../../domain/delivery/delivery_status.dart';
import '../../domain/health/courier_operation_health.dart';
import '../../domain/health/courier_operation_health_calculator.dart';
import '../../domain/warnings/courier_live_warning_type.dart';
import 'build_courier_live_warnings.dart';

/// Assembles the branch's [CourierOperationHealth] — Sprint 5C Part 13.
/// **Reuses [BuildCourierLiveWarnings] (Part 9) and
/// `DeliveryRepository.findActiveByBranchId` (already existing) as its
/// only inputs — introduces no new detection logic**, matching the
/// brief's own instruction to build the health indicator on top of the
/// warnings aggregator rather than reinventing detection.
class BuildCourierOperationHealth {
  const BuildCourierOperationHealth({
    required Clock clock,
    required DeliveryRepository deliveryRepository,
    required BuildCourierLiveWarnings buildCourierLiveWarnings,
    this.delayThreshold = const Duration(minutes: 45),
  })  : _clock = clock,
        _deliveryRepository = deliveryRepository,
        _buildCourierLiveWarnings = buildCourierLiveWarnings;

  final Clock _clock;
  final DeliveryRepository _deliveryRepository;
  final BuildCourierLiveWarnings _buildCourierLiveWarnings;

  /// An active delivery older than this (by `Delivery.createdAt`) counts
  /// as "delayed" — adjustable, never hardcoded inline in [call].
  final Duration delayThreshold;

  Future<CourierOperationHealth> call({required String branchId}) async {
    final now = _clock.now();
    final activeDeliveries =
        await _deliveryRepository.findActiveByBranchId(branchId);

    final delayedCount = activeDeliveries
        .where((d) => now.difference(d.createdAt) > delayThreshold)
        .length;
    final waitingCount = activeDeliveries
        .where((d) => d.status == DeliveryStatus.readyForAssignment)
        .length;

    final warnings = await _buildCourierLiveWarnings(branchId: branchId);
    final offlineCount = warnings
        .where((w) => w.type == CourierLiveWarningType.courierOffline)
        .length;
    final gpsFailureCount = warnings
        .where((w) => w.type == CourierLiveWarningType.gpsDisabled)
        .length;
    final alarmCount = warnings
        .where((w) =>
            w.type == CourierLiveWarningType.operationalRisk ||
            w.type == CourierLiveWarningType.abnormalRoute)
        .length;

    final level = CourierOperationHealthCalculator.evaluate(
      delayedDeliveryCount: delayedCount,
      offlineCourierCount: offlineCount,
      gpsFailureCount: gpsFailureCount,
      waitingDeliveryCount: waitingCount,
      operationalAlarmCount: alarmCount,
    );

    return CourierOperationHealth(
      branchId: branchId,
      level: level,
      delayedDeliveryCount: delayedCount,
      offlineCourierCount: offlineCount,
      gpsFailureCount: gpsFailureCount,
      waitingDeliveryCount: waitingCount,
      operationalAlarmCount: alarmCount,
      computedAt: now,
    );
  }
}
