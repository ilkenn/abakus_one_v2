import 'package:abakus_one_v2/features/courier/application/identity/geofence_transition_event_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/evaluate_courier_geofences.dart';
import 'package:abakus_one_v2/features/courier/data/courier_location_repository.dart';
import 'package:abakus_one_v2/features/courier/data/geofence_transition_event_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/location/courier_location_snapshot.dart';
import 'package:abakus_one_v2/features/courier/domain/location/geofence_transition_type.dart';
import 'package:abakus_one_v2/features/courier/domain/location/geofence_zone.dart';
import 'package:abakus_one_v2/features/courier/domain/location/geofence_zone_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

CourierLocationSnapshot _snapshot({
  required String id,
  required double latitude,
  required double longitude,
  double accuracyMeters = 10,
  required DateTime capturedAt,
}) {
  return CourierLocationSnapshot(
    id: id,
    courierId: 'courier-1',
    deviceId: 'device-1',
    deliveryId: 'delivery-1',
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    capturedAt: capturedAt,
    receivedAt: capturedAt,
  );
}

const _restaurantZone = GeofenceZone(
  zoneType: GeofenceZoneType.restaurantArrival,
  targetLatitude: 41.0,
  targetLongitude: 29.0,
  radiusMeters: 20,
);

void main() {
  group('EvaluateCourierGeofences', () {
    late CourierLocationRepository locationRepository;
    late GeofenceTransitionEventRepository transitionRepository;
    late EvaluateCourierGeofences useCase;

    setUp(() {
      locationRepository = InMemoryCourierLocationRepository();
      transitionRepository = InMemoryGeofenceTransitionEventRepository();
      useCase = EvaluateCourierGeofences(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        locationRepository: locationRepository,
        transitionRepository: transitionRepository,
        idGenerator: SequentialGeofenceTransitionEventIdGenerator(),
      );
    });

    test('the very first reading, already inside, confirms an entry', () async {
      final snapshot = _snapshot(
        id: 'loc-1',
        latitude: 41.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12),
      );

      final events = await useCase(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        snapshot: snapshot,
        zones: [_restaurantZone],
      );

      expect(events, hasLength(1));
      expect(events.single.transitionType, GeofenceTransitionType.entered);
      expect(events.single.zoneType, GeofenceZoneType.restaurantArrival);
      expect(
        await transitionRepository.findByDeliveryId('delivery-1'),
        hasLength(1),
      );
    });

    test('a reading outside the zone, with no history, produces no event',
        () async {
      final snapshot = _snapshot(
        id: 'loc-1',
        latitude: 42.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12),
      );

      final events = await useCase(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        snapshot: snapshot,
        zones: [_restaurantZone],
      );

      expect(events, isEmpty);
    });

    test('outside then inside confirms an entry against the prior reading',
        () async {
      final outside = _snapshot(
        id: 'loc-1',
        latitude: 42.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12),
      );
      await locationRepository.append(outside);

      final inside = _snapshot(
        id: 'loc-2',
        latitude: 41.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 1),
      );

      final events = await useCase(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        snapshot: inside,
        zones: [_restaurantZone],
      );

      expect(events, hasLength(1));
      expect(events.single.transitionType, GeofenceTransitionType.entered);
      expect(events.single.snapshotId, 'loc-2');
    });

    test('inside then outside confirms an exit', () async {
      final inside = _snapshot(
        id: 'loc-1',
        latitude: 41.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12),
      );
      await locationRepository.append(inside);

      final outside = _snapshot(
        id: 'loc-2',
        latitude: 42.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 1),
      );

      final events = await useCase(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        snapshot: outside,
        zones: [_restaurantZone],
      );

      expect(events, hasLength(1));
      expect(events.single.transitionType, GeofenceTransitionType.exited);
    });

    test('remaining inside across two readings produces no duplicate event',
        () async {
      final first = _snapshot(
        id: 'loc-1',
        latitude: 41.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12),
      );
      await locationRepository.append(first);
      await useCase(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        snapshot: first,
        zones: [_restaurantZone],
      );

      final second = _snapshot(
        id: 'loc-2',
        latitude: 41.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 1),
      );
      final events = await useCase(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        snapshot: second,
        zones: [_restaurantZone],
      );

      expect(events, isEmpty);
      expect(
        await transitionRepository.findByDeliveryId('delivery-1'),
        hasLength(1),
      );
    });

    test('a low-accuracy reading never confirms a transition', () async {
      final outside = _snapshot(
        id: 'loc-1',
        latitude: 42.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12),
      );
      await locationRepository.append(outside);

      final insideButNoisy = _snapshot(
        id: 'loc-2',
        latitude: 41.0,
        longitude: 29.0,
        accuracyMeters: 500,
        capturedAt: DateTime(2026, 1, 1, 12, 1),
      );

      final events = await useCase(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        snapshot: insideButNoisy,
        zones: [_restaurantZone],
      );

      expect(events, isEmpty);
    });

    test('an empty zone list produces no events', () async {
      final events = await useCase(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        snapshot: _snapshot(
          id: 'loc-1',
          latitude: 41.0,
          longitude: 29.0,
          capturedAt: DateTime(2026, 1, 1, 12),
        ),
        zones: const [],
      );
      expect(events, isEmpty);
    });
  });
}
