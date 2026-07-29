import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../../core/errors/business_rule_violation.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/delivery_repository.dart';
import '../../data/geofence_override_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/events/courier_event_type.dart';
import '../../domain/location/geofence_override.dart';
import '../../domain/location/geofence_zone_type.dart';
import '../identity/geofence_override_id_generator.dart';
import 'record_courier_event.dart';

/// Records a manager-authorized [GeofenceOverride] — "geofence overrides
/// require manager authorization and reason," and once recorded, is
/// **immutable** (no update/delete method on
/// [GeofenceOverrideRepository]). The returned [GeofenceOverride.id] is
/// what a caller then passes as `geofenceOverrideId` into
/// `TransitionDelivery`/`CompleteDelivery`/`ConfirmPackagePickup` to
/// bypass a failed [GeofenceEvaluationResult].
class OverrideGeofence {
  const OverrideGeofence({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required GeofenceOverrideIdGenerator idGenerator,
    required DeliveryRepository deliveryRepository,
    required GeofenceOverrideRepository overrideRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _deliveryRepository = deliveryRepository,
        _overrideRepository = overrideRepository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final GeofenceOverrideIdGenerator _idGenerator;
  final DeliveryRepository _deliveryRepository;
  final GeofenceOverrideRepository _overrideRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;

  Future<GeofenceOverride> call({
    required String deliveryId,
    required GeofenceZoneType zoneType,
    required String reason,
    required String approvedByStaffId,
    String? deviceId,
  }) async {
    if (reason.trim().isEmpty) {
      throw const ManualOverrideReasonRequiredViolation();
    }

    final delivery = await _deliveryRepository.findById(deliveryId);
    if (delivery == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'Delivery',
        id: deliveryId,
      );
    }

    const action = PosAuthorizedAction.overrideGeofence;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: approvedByStaffId,
      context: {'deliveryId': deliveryId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final override = GeofenceOverride(
      id: _idGenerator.nextOverrideId(),
      deliveryId: deliveryId,
      zoneType: zoneType,
      reason: reason,
      approvedByStaffId: approvedByStaffId,
      approvedAt: now,
    );
    await _overrideRepository.append(override);

    final event = await _recordCourierEvent(
      branchId: delivery.branchId,
      courierId: delivery.courierId,
      deliveryId: delivery.id,
      type: CourierEventType.geofenceOverridden,
      idempotencyKey: '${override.id}-geofence',
      occurredAt: now,
      sourceDeviceId: deviceId,
      payload: {'zoneType': zoneType.name},
    );

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${event.id}-audit',
      branchId: delivery.branchId,
      actorStaffId: approvedByStaffId,
      courierId: delivery.courierId,
      deviceId: deviceId,
      orderId: delivery.orderId.value,
      deliveryId: delivery.id,
      type: CourierAuditEventType.geofenceOverridden,
      description: 'Geofence override for ${zoneType.name}: $reason',
      reason: reason,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return override;
  }
}
