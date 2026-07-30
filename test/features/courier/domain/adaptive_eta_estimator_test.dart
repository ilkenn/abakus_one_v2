import 'package:abakus_one_v2/features/courier/domain/location/adaptive_eta_estimator.dart';
import 'package:abakus_one_v2/features/courier/domain/location/courier_location_snapshot.dart';
import 'package:abakus_one_v2/features/courier/domain/location/eta_historical_sample.dart';
import 'package:abakus_one_v2/features/courier/domain/location/geofence_zone_type.dart';
import 'package:abakus_one_v2/features/courier/domain/location/traffic_multiplier_provider.dart';
import 'package:flutter_test/flutter_test.dart';

CourierLocationSnapshot _snapshot({
  double latitude = 41.0,
  double longitude = 29.0,
  double accuracyMeters = 10,
}) {
  return CourierLocationSnapshot(
    id: 'loc-1',
    courierId: 'courier-1',
    deviceId: 'device-1',
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    capturedAt: DateTime(2026, 1, 1, 12),
    receivedAt: DateTime(2026, 1, 1, 12),
  );
}

void main() {
  group('AdaptiveEtaEstimator.estimate', () {
    test(
        'produces a positive distance/eta for a real target, tagged with '
        'the requested zoneType', () {
      const estimator =
          AdaptiveEtaEstimator(zoneType: GeofenceZoneType.restaurantArrival);
      final result = estimator.estimate(
        id: 'route-1',
        deliveryId: 'delivery-1',
        from: _snapshot(latitude: 41.0, longitude: 29.0),
        targetLatitude: 41.01,
        targetLongitude: 29.0,
        now: DateTime(2026, 1, 1, 3),
      );

      expect(result.distanceEstimateMeters, greaterThan(0));
      expect(result.etaMinutes, greaterThan(0));
      expect(result.zoneType, GeofenceZoneType.restaurantArrival);
    });

    test(
        'with no traffic provider and no history, the multiplier is 1.0 '
        'and confidence reflects the fixed-speed/accuracy-only case', () {
      const estimator = AdaptiveEtaEstimator();
      final result = estimator.estimate(
        id: 'route-1',
        deliveryId: 'delivery-1',
        from: _snapshot(accuracyMeters: 10),
        targetLatitude: 41.01,
        targetLongitude: 29.0,
        now: DateTime(2026, 1, 1, 3),
      );

      expect(result.trafficMultiplierApplied, 1.0);
      // base 0.4 + accuracy bonus 0.3 (10m is within the trusted threshold)
      expect(result.confidenceScore, closeTo(0.7, 0.001));
    });

    test('a rush-hour traffic provider widens the ETA and is recorded', () {
      const estimator = AdaptiveEtaEstimator(
        trafficMultiplierProvider: TimeOfDayTrafficMultiplierProvider(),
      );
      final offPeak = estimator.estimate(
        id: 'route-1',
        deliveryId: 'delivery-1',
        from: _snapshot(),
        targetLatitude: 41.01,
        targetLongitude: 29.0,
        now: DateTime(2026, 1, 1, 3),
      );
      final rushHour = estimator.estimate(
        id: 'route-2',
        deliveryId: 'delivery-1',
        from: _snapshot(),
        targetLatitude: 41.01,
        targetLongitude: 29.0,
        now: DateTime(2026, 1, 1, 8),
      );

      expect(offPeak.trafficMultiplierApplied, 1.0);
      expect(rushHour.trafficMultiplierApplied, 1.4);
      expect(rushHour.etaMinutes!, greaterThan(offPeak.etaMinutes!));
    });

    test(
        'enough historical samples raise confidence and change the ETA '
        'versus the fixed-speed fallback', () {
      const fixedSpeedEstimator = AdaptiveEtaEstimator();
      const historicalEstimator = AdaptiveEtaEstimator(
        // Much faster than the 6 m/s default fallback.
        historicalSamples: [
          EtaHistoricalSample(distanceMeters: 1000, actualDurationSeconds: 50),
          EtaHistoricalSample(distanceMeters: 1000, actualDurationSeconds: 50),
          EtaHistoricalSample(distanceMeters: 1000, actualDurationSeconds: 50),
          EtaHistoricalSample(distanceMeters: 1000, actualDurationSeconds: 50),
          EtaHistoricalSample(distanceMeters: 1000, actualDurationSeconds: 50),
        ],
      );

      final fixed = fixedSpeedEstimator.estimate(
        id: 'route-1',
        deliveryId: 'delivery-1',
        from: _snapshot(),
        targetLatitude: 41.01,
        targetLongitude: 29.0,
        now: DateTime(2026, 1, 1, 3),
      );
      final historical = historicalEstimator.estimate(
        id: 'route-2',
        deliveryId: 'delivery-1',
        from: _snapshot(),
        targetLatitude: 41.01,
        targetLongitude: 29.0,
        now: DateTime(2026, 1, 1, 3),
      );

      expect(historical.etaMinutes!, lessThan(fixed.etaMinutes!));
      // base 0.4 + historical bonus 0.3 + accuracy bonus 0.3
      expect(historical.confidenceScore, closeTo(1.0, 0.001));
      expect(fixed.confidenceScore, closeTo(0.7, 0.001));
    });

    test('a low-accuracy source reading loses the accuracy confidence bonus',
        () {
      const estimator = AdaptiveEtaEstimator();
      final result = estimator.estimate(
        id: 'route-1',
        deliveryId: 'delivery-1',
        from: _snapshot(accuracyMeters: 500),
        targetLatitude: 41.01,
        targetLongitude: 29.0,
        now: DateTime(2026, 1, 1, 3),
      );
      // base 0.4 only
      expect(result.confidenceScore, closeTo(0.4, 0.001));
    });
  });
}
