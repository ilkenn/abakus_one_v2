import 'package:abakus_one_v2/features/courier/domain/health/courier_operation_health_calculator.dart';
import 'package:abakus_one_v2/features/courier/domain/health/courier_operation_health_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CourierOperationHealthCalculator', () {
    test('all-zero signals are healthy', () {
      final level = CourierOperationHealthCalculator.evaluate(
        delayedDeliveryCount: 0,
        offlineCourierCount: 0,
        gpsFailureCount: 0,
        waitingDeliveryCount: 0,
        operationalAlarmCount: 0,
      );

      expect(level, CourierOperationHealthLevel.healthy);
    });

    test('one offline courier crosses the degraded threshold', () {
      final level = CourierOperationHealthCalculator.evaluate(
        delayedDeliveryCount: 0,
        offlineCourierCount: 1,
        gpsFailureCount: 0,
        waitingDeliveryCount: 0,
        operationalAlarmCount: 0,
      );

      expect(level, CourierOperationHealthLevel.degraded);
    });

    test('two offline couriers cross the critical threshold', () {
      final level = CourierOperationHealthCalculator.evaluate(
        delayedDeliveryCount: 0,
        offlineCourierCount: 2,
        gpsFailureCount: 0,
        waitingDeliveryCount: 0,
        operationalAlarmCount: 0,
      );

      expect(level, CourierOperationHealthLevel.critical);
    });

    test(
        'any single signal crossing critical makes the whole branch '
        'critical, even with the others at zero', () {
      final level = CourierOperationHealthCalculator.evaluate(
        delayedDeliveryCount: 0,
        offlineCourierCount: 0,
        gpsFailureCount: 0,
        waitingDeliveryCount: 5,
        operationalAlarmCount: 0,
      );

      expect(level, CourierOperationHealthLevel.critical);
    });

    test('thresholds are configurable, not hardcoded', () {
      final level = CourierOperationHealthCalculator.evaluate(
        delayedDeliveryCount: 1,
        offlineCourierCount: 0,
        gpsFailureCount: 0,
        waitingDeliveryCount: 0,
        operationalAlarmCount: 0,
        degradedDelayedDeliveryThreshold: 5,
      );

      expect(level, CourierOperationHealthLevel.healthy);
    });
  });
}
