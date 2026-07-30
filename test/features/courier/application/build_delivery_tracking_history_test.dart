import 'package:abakus_one_v2/features/courier/application/use_cases/build_delivery_tracking_history.dart';
import 'package:abakus_one_v2/features/courier/data/courier_location_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/audit/courier_audit_event_type.dart';
import 'package:abakus_one_v2/features/courier/domain/audit/courier_operational_audit_entry.dart';
import 'package:abakus_one_v2/features/courier/domain/location/courier_location_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

CourierLocationSnapshot _snapshot({
  required String id,
  double latitude = 41.0,
  required DateTime capturedAt,
  String deliveryId = 'delivery-1',
}) {
  return CourierLocationSnapshot(
    id: id,
    courierId: 'courier-1',
    deviceId: 'device-1',
    deliveryId: deliveryId,
    latitude: latitude,
    longitude: 29.0,
    accuracyMeters: 10,
    capturedAt: capturedAt,
    receivedAt: capturedAt,
  );
}

CourierOperationalAuditEntry _checkpoint({
  required String id,
  required DateTime timestamp,
  required CourierAuditEventType type,
  String deliveryId = 'delivery-1',
}) {
  return CourierOperationalAuditEntry(
    id: id,
    branchId: 'branch-1',
    actorStaffId: 'courier-1',
    deliveryId: deliveryId,
    type: type,
    description: type.name,
    timestamp: timestamp,
    correlationId: id,
  );
}

void main() {
  group('BuildDeliveryTrackingHistory', () {
    test(
        'assembles sorted checkpoints, sorted locations, and derived '
        'segments for one delivery, scoped by deliveryId', () async {
      final locationRepository = InMemoryCourierLocationRepository();
      await locationRepository.append(_snapshot(
        id: 'loc-2',
        latitude: 41.001,
        capturedAt: DateTime(2026, 1, 1, 12, 5),
      ));
      await locationRepository.append(_snapshot(
        id: 'loc-1',
        latitude: 41.0,
        capturedAt: DateTime(2026, 1, 1, 12, 0),
      ));
      // A different delivery's reading must never leak in.
      await locationRepository.append(_snapshot(
        id: 'loc-other',
        capturedAt: DateTime(2026, 1, 1, 12, 2),
        deliveryId: 'delivery-2',
      ));

      final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      await auditRepository.appendEvent(_checkpoint(
        id: 'audit-2',
        timestamp: DateTime(2026, 1, 1, 12, 6),
        type: CourierAuditEventType.customerArrivalConfirmed,
      ));
      await auditRepository.appendEvent(_checkpoint(
        id: 'audit-1',
        timestamp: DateTime(2026, 1, 1, 12, 1),
        type: CourierAuditEventType.restaurantArrivalConfirmed,
      ));

      final history = await BuildDeliveryTrackingHistory(
        locationRepository: locationRepository,
        auditRepository: auditRepository,
      )(deliveryId: 'delivery-1');

      expect(history.locationHistory.map((s) => s.id).toList(),
          ['loc-1', 'loc-2']);
      expect(history.checkpoints.map((c) => c.id).toList(),
          ['audit-1', 'audit-2']);
      expect(history.segments, hasLength(1));
      expect(history.totalDistanceMeters, greaterThan(0));
    });

    test(
        'a delivery with no location history produces empty segments and '
        'zero totals', () async {
      final history = await BuildDeliveryTrackingHistory(
        locationRepository: InMemoryCourierLocationRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      )(deliveryId: 'delivery-1');

      expect(history.locationHistory, isEmpty);
      expect(history.segments, isEmpty);
      expect(history.totalDistanceMeters, 0);
      expect(history.totalTravelDuration, Duration.zero);
      expect(history.totalStopDuration, Duration.zero);
    });
  });
}
