import '../../../../core/utils/clock.dart';
import '../../data/courier_location_repository.dart';
import '../../domain/events/courier_event_type.dart';
import '../../domain/location/courier_location_snapshot.dart';
import '../identity/courier_location_snapshot_id_generator.dart';
import 'record_courier_event.dart';

/// Records one raw [CourierLocationSnapshot] reading — always accepted as
/// given; **this use case never judges accuracy or evidentiary weight**
/// ("do not treat low-accuracy GPS as definitive evidence" is
/// [GeofenceEvaluator]'s concern, not this one's). No authorization gate:
/// a device reporting its own courier's position is a routine, high-
/// frequency background action, not a privileged one (unlike the
/// courier-operations actions gated in `PosAuthorizedAction`).
///
/// **Sprint 5B**: [altitudeMeters]/[isMocked] are additive, optional
/// parameters carrying the real-GPS fields `GeolocatorCourierLocationProvider`
/// now captures — omitted callers behave exactly as before.
class RecordCourierLocationSnapshot {
  const RecordCourierLocationSnapshot({
    required Clock clock,
    required CourierLocationSnapshotIdGenerator idGenerator,
    required CourierLocationRepository repository,
    required RecordCourierEvent recordCourierEvent,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _repository = repository,
        _recordCourierEvent = recordCourierEvent;

  final Clock _clock;
  final CourierLocationSnapshotIdGenerator _idGenerator;
  final CourierLocationRepository _repository;
  final RecordCourierEvent _recordCourierEvent;

  Future<CourierLocationSnapshot> call({
    required String courierId,
    required String deviceId,
    required String branchId,
    String? shiftId,
    String? deliveryId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    double? headingDegrees,
    double? speedMetersPerSecond,
    double? altitudeMeters,
    bool isMocked = false,
    required DateTime capturedAt,
  }) async {
    final now = _clock.now();
    final snapshot = CourierLocationSnapshot(
      id: _idGenerator.nextSnapshotId(),
      courierId: courierId,
      deviceId: deviceId,
      shiftId: shiftId,
      deliveryId: deliveryId,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      headingDegrees: headingDegrees,
      speedMetersPerSecond: speedMetersPerSecond,
      altitudeMeters: altitudeMeters,
      isMocked: isMocked,
      capturedAt: capturedAt,
      receivedAt: now,
    );
    await _repository.append(snapshot);

    await _recordCourierEvent(
      branchId: branchId,
      courierId: courierId,
      deliveryId: deliveryId,
      shiftId: shiftId,
      type: CourierEventType.locationSnapshotRecorded,
      idempotencyKey: '${snapshot.id}-location',
      occurredAt: capturedAt,
      sourceDeviceId: deviceId,
    );

    return snapshot;
  }
}
