import 'package:abakus_one_v2/features/courier/domain/location/courier_location_snapshot.dart';
import 'package:abakus_one_v2/features/courier/domain/location/geofence_zone.dart';
import 'package:abakus_one_v2/features/courier/domain/location/geofence_zone_type.dart';
import 'package:abakus_one_v2/features/courier/domain/location/multi_geofence_evaluator.dart';
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
  group('MultiGeofenceEvaluator', () {
    test('evaluates every zone independently in a single pass', () {
      final result = MultiGeofenceEvaluator.evaluate(
        snapshot: _snapshot(latitude: 41.0, longitude: 29.0),
        zones: [
          const GeofenceZone(
            zoneType: GeofenceZoneType.restaurantArrival,
            targetLatitude: 41.0,
            targetLongitude: 29.0,
            radiusMeters: 20,
          ),
          const GeofenceZone(
            zoneType: GeofenceZoneType.customerArrival,
            targetLatitude: 41.1,
            targetLongitude: 29.1,
            radiusMeters: 20,
          ),
        ],
      );

      expect(result, hasLength(2));
      expect(result[0].zone.zoneType, GeofenceZoneType.restaurantArrival);
      expect(result[0].result.isWithin, isTrue);
      expect(result[1].zone.zoneType, GeofenceZoneType.customerArrival);
      expect(result[1].result.isWithin, isFalse);
    });

    test('an empty zone list produces an empty result', () {
      expect(
        MultiGeofenceEvaluator.evaluate(snapshot: _snapshot(), zones: const []),
        isEmpty,
      );
    });

    test('respects each zone\'s own dynamic radius independently', () {
      final result = MultiGeofenceEvaluator.evaluate(
        snapshot: _snapshot(latitude: 41.001, longitude: 29.0),
        zones: [
          const GeofenceZone(
            zoneType: GeofenceZoneType.restaurantArrival,
            targetLatitude: 41.0,
            targetLongitude: 29.0,
            radiusMeters: 20,
          ),
          const GeofenceZone(
            zoneType: GeofenceZoneType.packagePickup,
            targetLatitude: 41.0,
            targetLongitude: 29.0,
            radiusMeters: 500,
          ),
        ],
      );

      expect(result[0].result.isWithin, isFalse);
      expect(result[1].result.isWithin, isTrue);
    });
  });
}
