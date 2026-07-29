import 'package:abakus_one_v2/features/courier/domain/location/courier_location_snapshot.dart';
import 'package:abakus_one_v2/features/courier/domain/location/geofence_evaluator.dart';
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
  group('GeofenceEvaluator', () {
    test('a reading at the exact target point is within the default radius',
        () {
      final result = GeofenceEvaluator.evaluate(
        snapshot: _snapshot(latitude: 41.0, longitude: 29.0),
        targetLatitude: 41.0,
        targetLongitude: 29.0,
      );
      expect(result.isWithin, isTrue);
      expect(result.distanceMeters, closeTo(0, 0.001));
      expect(result.passesAutomatically, isTrue);
    });

    test('a reading far outside the radius fails isWithin', () {
      final result = GeofenceEvaluator.evaluate(
        snapshot: _snapshot(latitude: 41.1, longitude: 29.1),
        targetLatitude: 41.0,
        targetLongitude: 29.0,
      );
      expect(result.isWithin, isFalse);
      expect(result.passesAutomatically, isFalse);
    });

    test(
        'low-accuracy GPS is never treated as definitive evidence — '
        'passesAutomatically is false even when isWithin is true', () {
      final result = GeofenceEvaluator.evaluate(
        snapshot: _snapshot(accuracyMeters: 100),
        targetLatitude: 41.0,
        targetLongitude: 29.0,
      );
      expect(result.isWithin, isTrue);
      expect(result.isAccuracySufficient, isFalse);
      expect(result.passesAutomatically, isFalse);
    });

    test('a custom radius is respected', () {
      final result = GeofenceEvaluator.evaluate(
        snapshot: _snapshot(latitude: 41.0005, longitude: 29.0),
        targetLatitude: 41.0,
        targetLongitude: 29.0,
        radiusMeters: 1000,
      );
      expect(result.isWithin, isTrue);
    });
  });
}
