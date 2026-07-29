import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_delay_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const thresholds = KitchenDelayThresholds(
    warningThreshold: Duration(minutes: 10),
    criticalThreshold: Duration(minutes: 20),
  );

  group('KitchenDelayState.compute', () {
    test('is neither warning nor critical well under threshold', () {
      final state = KitchenDelayState.compute(
        workItemId: 'w1',
        queuedAt: DateTime(2026, 1, 1, 12, 0),
        now: DateTime(2026, 1, 1, 12, 5),
        thresholds: thresholds,
      );

      expect(state.isWarning, isFalse);
      expect(state.isCritical, isFalse);
      expect(state.isOverdue, isFalse);
      expect(state.totalDuration, const Duration(minutes: 5));
    });

    test('is warning once past the warning threshold but under critical', () {
      final state = KitchenDelayState.compute(
        workItemId: 'w1',
        queuedAt: DateTime(2026, 1, 1, 12, 0),
        now: DateTime(2026, 1, 1, 12, 15),
        thresholds: thresholds,
      );

      expect(state.isWarning, isTrue);
      expect(state.isCritical, isFalse);
    });

    test('is critical and overdue once past the critical threshold', () {
      final state = KitchenDelayState.compute(
        workItemId: 'w1',
        queuedAt: DateTime(2026, 1, 1, 12, 0),
        now: DateTime(2026, 1, 1, 12, 25),
        thresholds: thresholds,
      );

      expect(state.isWarning, isFalse);
      expect(state.isCritical, isTrue);
      expect(state.isOverdue, isTrue);
    });

    test('stops accumulating duration once readyAt is set', () {
      final state = KitchenDelayState.compute(
        workItemId: 'w1',
        queuedAt: DateTime(2026, 1, 1, 12, 0),
        preparingStartedAt: DateTime(2026, 1, 1, 12, 2),
        readyAt: DateTime(2026, 1, 1, 12, 8),
        now: DateTime(2026, 1, 1, 13, 0),
        thresholds: thresholds,
      );

      expect(state.totalDuration, const Duration(minutes: 8));
      expect(state.queuedDuration, const Duration(minutes: 2));
      expect(state.preparingDuration, const Duration(minutes: 6));
    });

    test('uses a channel-specific override threshold when configured', () {
      const withOverride = KitchenDelayThresholds(
        warningThreshold: Duration(minutes: 10),
        criticalThreshold: Duration(minutes: 20),
        channelOverrides: {
          'delivery': (
            warning: Duration(minutes: 5),
            critical: Duration(minutes: 10)
          ),
        },
      );

      final deliveryState = KitchenDelayState.compute(
        workItemId: 'w1',
        queuedAt: DateTime(2026, 1, 1, 12, 0),
        now: DateTime(2026, 1, 1, 12, 6),
        thresholds: withOverride,
        channelName: 'delivery',
      );
      expect(deliveryState.isWarning, isTrue);

      final dineInState = KitchenDelayState.compute(
        workItemId: 'w1',
        queuedAt: DateTime(2026, 1, 1, 12, 0),
        now: DateTime(2026, 1, 1, 12, 6),
        thresholds: withOverride,
        channelName: 'dineInStaff',
      );
      expect(dineInState.isWarning, isFalse);
    });
  });
}
