import 'package:abakus_one_v2/features/courier/domain/compensation/shift_earnings_window_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShiftEarningsWindowCalculator.determineStartAt', () {
    test(
        'early arrival never creates extra earnings — start is the '
        'scheduled time, not the earlier login', () {
      final start = ShiftEarningsWindowCalculator.determineStartAt(
        scheduledStart: DateTime(2026, 1, 1, 10, 0),
        actualLogin: DateTime(2026, 1, 1, 9, 40),
      );
      expect(start, DateTime(2026, 1, 1, 10, 0));
    });

    test(
        'late arrival reduces payable hours — start is the later login '
        'time', () {
      final start = ShiftEarningsWindowCalculator.determineStartAt(
        scheduledStart: DateTime(2026, 1, 1, 10, 0),
        actualLogin: DateTime(2026, 1, 1, 10, 18),
      );
      expect(start, DateTime(2026, 1, 1, 10, 18));
    });

    test('an on-time login yields the scheduled/login instant', () {
      final start = ShiftEarningsWindowCalculator.determineStartAt(
        scheduledStart: DateTime(2026, 1, 1, 10, 0),
        actualLogin: DateTime(2026, 1, 1, 10, 0),
      );
      expect(start, DateTime(2026, 1, 1, 10, 0));
    });
  });

  group('ShiftEarningsWindowCalculator.determineEndAt', () {
    test(
        'with no active delivery, earnings stop at the scheduled shift '
        'end', () {
      final end = ShiftEarningsWindowCalculator.determineEndAt(
        scheduledEnd: DateTime(2026, 1, 1, 18, 0),
      );
      expect(end, DateTime(2026, 1, 1, 18, 0));
    });

    test(
        'when delivering the final package, earnings stop at the first '
        'verified geofence arrival — not the scheduled end', () {
      final end = ShiftEarningsWindowCalculator.determineEndAt(
        scheduledEnd: DateTime(2026, 1, 1, 18, 0),
        finalDeliveryVerifiedArrivalAt: DateTime(2026, 1, 1, 18, 12),
      );
      expect(end, DateTime(2026, 1, 1, 18, 12));
    });
  });

  group('ShiftEarningsWindowCalculator.payableDuration', () {
    test('the usual case is end minus start', () {
      final duration = ShiftEarningsWindowCalculator.payableDuration(
        start: DateTime(2026, 1, 1, 10, 0),
        end: DateTime(2026, 1, 1, 18, 0),
      );
      expect(duration, const Duration(hours: 8));
    });

    test(
        'a computed end before the computed start pays zero, never a '
        'negative duration', () {
      final duration = ShiftEarningsWindowCalculator.payableDuration(
        start: DateTime(2026, 1, 1, 18, 0),
        end: DateTime(2026, 1, 1, 10, 0),
      );
      expect(duration, Duration.zero);
    });
  });
}
