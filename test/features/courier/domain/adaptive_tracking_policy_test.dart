import 'package:abakus_one_v2/features/courier/domain/location/adaptive_tracking_policy.dart';
import 'package:abakus_one_v2/features/courier/domain/location/location_tracking_accuracy.dart';
import 'package:abakus_one_v2/features/courier/domain/location/movement_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdaptiveTrackingPolicy.classify', () {
    const policy = AdaptiveTrackingPolicy();

    test('below the walking threshold classifies as stationary', () {
      expect(
        policy.classify(speedMetersPerSecond: 0.1),
        MovementState.stationary,
      );
    });

    test('between the walking and vehicle thresholds classifies as walking',
        () {
      expect(
        policy.classify(speedMetersPerSecond: 1.5),
        MovementState.walking,
      );
    });

    test('at or above the vehicle threshold classifies as vehicle', () {
      expect(
        policy.classify(speedMetersPerSecond: 5.0),
        MovementState.vehicle,
      );
    });

    test(
        'within the approaching-target radius always wins, even at vehicle '
        'speed', () {
      expect(
        policy.classify(
          speedMetersPerSecond: 10.0,
          distanceToActiveTargetMeters: 50,
        ),
        MovementState.approachingTarget,
      );
    });

    test('outside the approaching-target radius falls back to speed', () {
      expect(
        policy.classify(
          speedMetersPerSecond: 0.0,
          distanceToActiveTargetMeters: 5000,
        ),
        MovementState.stationary,
      );
    });

    test('a null target distance never triggers approachingTarget', () {
      expect(
        policy.classify(
          speedMetersPerSecond: 0.0,
          distanceToActiveTargetMeters: null,
        ),
        MovementState.stationary,
      );
    });
  });

  group('AdaptiveTrackingPolicy.intervalFor', () {
    test('matches the documented default policy for every state', () {
      const policy = AdaptiveTrackingPolicy();
      expect(policy.intervalFor(MovementState.stationary),
          const Duration(seconds: 30));
      expect(policy.intervalFor(MovementState.walking),
          const Duration(seconds: 10));
      expect(policy.intervalFor(MovementState.vehicle),
          const Duration(seconds: 5));
      expect(policy.intervalFor(MovementState.approachingTarget),
          const Duration(seconds: 2));
    });

    test('every interval is adjustable via the constructor, never hardcoded',
        () {
      const policy = AdaptiveTrackingPolicy(
        stationaryInterval: Duration(minutes: 1),
        walkingInterval: Duration(seconds: 20),
        vehicleInterval: Duration(seconds: 8),
        approachingTargetInterval: Duration(seconds: 1),
      );
      expect(policy.intervalFor(MovementState.stationary),
          const Duration(minutes: 1));
      expect(policy.intervalFor(MovementState.walking),
          const Duration(seconds: 20));
      expect(policy.intervalFor(MovementState.vehicle),
          const Duration(seconds: 8));
      expect(policy.intervalFor(MovementState.approachingTarget),
          const Duration(seconds: 1));
    });
  });

  group('AdaptiveTrackingPolicy.accuracyFor', () {
    const policy = AdaptiveTrackingPolicy();

    test('stationary requests the lowest accuracy tier', () {
      expect(policy.accuracyFor(MovementState.stationary),
          LocationTrackingAccuracy.low);
    });

    test('walking and vehicle request balanced accuracy', () {
      expect(policy.accuracyFor(MovementState.walking),
          LocationTrackingAccuracy.balanced);
      expect(policy.accuracyFor(MovementState.vehicle),
          LocationTrackingAccuracy.balanced);
    });

    test('approaching target always requests the highest accuracy', () {
      expect(policy.accuracyFor(MovementState.approachingTarget),
          LocationTrackingAccuracy.high);
    });
  });

  group('AdaptiveTrackingPolicy thresholds', () {
    test('speed threshold boundaries are adjustable and respected', () {
      const policy = AdaptiveTrackingPolicy(
        walkingSpeedThresholdMetersPerSecond: 1.0,
        vehicleSpeedThresholdMetersPerSecond: 4.0,
      );
      expect(policy.classify(speedMetersPerSecond: 0.99),
          MovementState.stationary);
      expect(policy.classify(speedMetersPerSecond: 1.0), MovementState.walking);
      expect(
          policy.classify(speedMetersPerSecond: 3.99), MovementState.walking);
      expect(policy.classify(speedMetersPerSecond: 4.0), MovementState.vehicle);
    });

    test('the approaching-target radius is adjustable and respected', () {
      const policy = AdaptiveTrackingPolicy(approachingTargetRadiusMeters: 10);
      expect(
        policy.classify(
          speedMetersPerSecond: 0,
          distanceToActiveTargetMeters: 10,
        ),
        MovementState.approachingTarget,
      );
      expect(
        policy.classify(
          speedMetersPerSecond: 0,
          distanceToActiveTargetMeters: 10.01,
        ),
        MovementState.stationary,
      );
    });
  });
}
