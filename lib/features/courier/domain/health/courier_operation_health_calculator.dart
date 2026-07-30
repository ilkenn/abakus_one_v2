import 'courier_operation_health_level.dart';

/// Pure, stateless threshold evaluator for [CourierOperationHealthLevel]
/// — Sprint 5C Part 13. Mirrors `AdaptiveTrackingPolicy`/
/// `GeofenceEvaluator`'s shape: no I/O, every threshold a parameter with
/// a documented default, never hardcoded inline. Any single signal
/// crossing its critical threshold makes the whole branch critical; short
/// of that, any signal crossing its (lower) degraded threshold makes the
/// branch degraded.
abstract final class CourierOperationHealthCalculator {
  CourierOperationHealthCalculator._();

  static CourierOperationHealthLevel evaluate({
    required int delayedDeliveryCount,
    required int offlineCourierCount,
    required int gpsFailureCount,
    required int waitingDeliveryCount,
    required int operationalAlarmCount,
    int criticalDelayedDeliveryThreshold = 3,
    int criticalOfflineCourierThreshold = 2,
    int criticalGpsFailureThreshold = 2,
    int criticalWaitingDeliveryThreshold = 5,
    int criticalOperationalAlarmThreshold = 3,
    int degradedDelayedDeliveryThreshold = 1,
    int degradedOfflineCourierThreshold = 1,
    int degradedGpsFailureThreshold = 1,
    int degradedWaitingDeliveryThreshold = 2,
    int degradedOperationalAlarmThreshold = 1,
  }) {
    final isCritical =
        delayedDeliveryCount >= criticalDelayedDeliveryThreshold ||
            offlineCourierCount >= criticalOfflineCourierThreshold ||
            gpsFailureCount >= criticalGpsFailureThreshold ||
            waitingDeliveryCount >= criticalWaitingDeliveryThreshold ||
            operationalAlarmCount >= criticalOperationalAlarmThreshold;
    if (isCritical) return CourierOperationHealthLevel.critical;

    final isDegraded =
        delayedDeliveryCount >= degradedDelayedDeliveryThreshold ||
            offlineCourierCount >= degradedOfflineCourierThreshold ||
            gpsFailureCount >= degradedGpsFailureThreshold ||
            waitingDeliveryCount >= degradedWaitingDeliveryThreshold ||
            operationalAlarmCount >= degradedOperationalAlarmThreshold;
    if (isDegraded) return CourierOperationHealthLevel.degraded;

    return CourierOperationHealthLevel.healthy;
  }
}
