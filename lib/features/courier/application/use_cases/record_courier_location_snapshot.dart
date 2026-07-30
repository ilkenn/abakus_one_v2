import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
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
/// **Sprint 5B**: [altitudeMeters]/[isMocked]/[batteryLevelPercent] are
/// additive, optional parameters carrying the real-GPS/device-telemetry
/// fields `GeolocatorCourierLocationProvider`/`BatteryLevelProvider` now
/// capture — omitted callers behave exactly as before.
///
/// **Sprint 5B Part 11**: [authenticatedCourierId], when supplied, must
/// match [courierId] — "a courier may only publish their own location."
/// This app has no real backend/auth session yet (`CLAUDE.md` §9's
/// forward-looking security rules), so this is not a cryptographic
/// guarantee; it is the same explicit-actor-id trust boundary every other
/// use case in this app already relies on (`performedByStaffId` is always
/// passed by the caller, never independently verified either). `null`
/// (the default) skips the check, preserving every existing call site's
/// behavior unchanged.
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
    int? batteryLevelPercent,
    required DateTime capturedAt,
    String? authenticatedCourierId,
  }) async {
    if (authenticatedCourierId != null && authenticatedCourierId != courierId) {
      const action = PosAuthorizedAction.publishOwnLocationOnly;
      throw AuthorizationDeniedViolation(actionName: action.name);
    }
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
      batteryLevelPercent: batteryLevelPercent,
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
