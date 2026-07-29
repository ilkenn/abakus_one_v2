import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/delivery_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/delivery/delivery.dart';
import '../../domain/delivery/delivery_status.dart';
import '../../domain/events/courier_event_type.dart';
import '../../domain/location/geofence_evaluation_result.dart';
import '../../domain/location/geofence_zone_type.dart';
import 'courier_location_availability_guard.dart';
import 'record_courier_event.dart';

/// Transitions a [Delivery] through its routine, non-pickup/non-completion
/// steps (restaurant arrival, en-route start, customer arrival, plain
/// cancellation, return-to-restaurant) — one use case, mirrors
/// `TransitionKitchenWorkItem`. Pickup and completion have their own use
/// cases (`ConfirmPackagePickup`/`CompleteDelivery`) since they need
/// additional integration (`PackagePreparation`, proof, cash collection).
///
/// **Geofence-gated** for [DeliveryStatus.arrivedAtRestaurant]/
/// [DeliveryStatus.arrivedAtCustomer]: if [geofenceResult] is supplied and
/// `!passesAutomatically`, the transition is rejected with
/// [GeofenceRequiresOverrideViolation] unless [geofenceOverrideId] is also
/// supplied (recorded separately via `OverrideGeofence`, referenced here
/// only by id — never re-validated). Omitting [geofenceResult] entirely
/// skips the check (e.g. a manual/manager-driven correction where no
/// location reading applies).
///
/// **Sprint 5B**: [locationGuard], when supplied, requires location to be
/// available before a **forward-progress** transition
/// (`arrivedAtRestaurant`/`enRoute`/`arrivedAtCustomer`) — "a courier
/// cannot... progress a delivery... while location is unavailable."
/// Cancellation/return-to-restaurant transitions are never gated — a
/// courier without a working location must still be able to report those.
/// `null` (the default) skips the check.
class TransitionDelivery {
  const TransitionDelivery({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required DeliveryRepository repository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
    CourierLocationAvailabilityGuard? locationGuard,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent,
        _locationGuard = locationGuard;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final DeliveryRepository _repository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;
  final CourierLocationAvailabilityGuard? _locationGuard;

  static const _forwardProgressStatuses = {
    DeliveryStatus.arrivedAtRestaurant,
    DeliveryStatus.enRoute,
    DeliveryStatus.arrivedAtCustomer,
  };

  static PosAuthorizedAction _actionFor(DeliveryStatus to) {
    switch (to) {
      case DeliveryStatus.arrivedAtRestaurant:
        return PosAuthorizedAction.confirmRestaurantArrival;
      case DeliveryStatus.enRoute:
        return PosAuthorizedAction.startDelivery;
      case DeliveryStatus.arrivedAtCustomer:
        return PosAuthorizedAction.confirmCustomerArrival;
      default:
        return PosAuthorizedAction.cancelDeliveryAssignment;
    }
  }

  static CourierAuditEventType _auditTypeFor(DeliveryStatus to) {
    switch (to) {
      case DeliveryStatus.arrivedAtRestaurant:
        return CourierAuditEventType.restaurantArrivalConfirmed;
      case DeliveryStatus.enRoute:
        return CourierAuditEventType.deliveryStarted;
      case DeliveryStatus.arrivedAtCustomer:
        return CourierAuditEventType.customerArrivalConfirmed;
      default:
        return CourierAuditEventType.deliveryFailed;
    }
  }

  static CourierEventType _eventTypeFor(DeliveryStatus to) {
    switch (to) {
      case DeliveryStatus.arrivedAtRestaurant:
        return CourierEventType.restaurantArrivalConfirmed;
      case DeliveryStatus.enRoute:
        return CourierEventType.deliveryEnRoute;
      case DeliveryStatus.arrivedAtCustomer:
        return CourierEventType.customerArrivalConfirmed;
      default:
        return CourierEventType.deliveryFailed;
    }
  }

  Future<Delivery> call({
    required String deliveryId,
    required DeliveryStatus to,
    required int expectedRevision,
    required String performedByStaffId,
    String? deviceId,
    String? reason,
    GeofenceEvaluationResult? geofenceResult,
    String? geofenceOverrideId,
  }) async {
    final delivery = await _repository.findById(deliveryId);
    if (delivery == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'Delivery',
        id: deliveryId,
      );
    }
    if (delivery.revision != expectedRevision) {
      throw StaleCourierRevisionViolation(
        entityId: deliveryId,
        expectedRevision: expectedRevision,
        actualRevision: delivery.revision,
      );
    }
    if (!DeliveryStatusTransitions.canTransition(delivery.status, to)) {
      throw InvalidDeliveryTransitionViolation(
        fromStatusName: delivery.status.name,
        toStatusName: to.name,
      );
    }
    if (_forwardProgressStatuses.contains(to) && delivery.courierId != null) {
      await _locationGuard?.assertAvailable(
        courierId: delivery.courierId!,
        deliveryId: deliveryId,
      );
    }

    final zoneType = to == DeliveryStatus.arrivedAtRestaurant
        ? GeofenceZoneType.restaurantArrival
        : to == DeliveryStatus.arrivedAtCustomer
            ? GeofenceZoneType.customerArrival
            : null;
    if (zoneType != null &&
        geofenceResult != null &&
        !geofenceResult.passesAutomatically &&
        geofenceOverrideId == null) {
      throw GeofenceRequiresOverrideViolation(
        deliveryId: deliveryId,
        zoneTypeName: zoneType.name,
      );
    }

    final action = _actionFor(to);
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'deliveryId': deliveryId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final updated =
        delivery.copyWith(status: to, revision: delivery.revision + 1);
    await _repository.save(updated);

    final event = await _recordCourierEvent(
      branchId: delivery.branchId,
      courierId: delivery.courierId,
      deliveryId: delivery.id,
      type: _eventTypeFor(to),
      idempotencyKey: '${delivery.id}-rev${updated.revision}',
      occurredAt: now,
      sourceDeviceId: deviceId,
      payload: {
        if (geofenceOverrideId != null)
          'geofenceOverrideId': geofenceOverrideId,
      },
    );

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${event.id}-audit',
      branchId: delivery.branchId,
      actorStaffId: performedByStaffId,
      courierId: delivery.courierId,
      deviceId: deviceId,
      orderId: delivery.orderId.value,
      deliveryId: delivery.id,
      type: _auditTypeFor(to),
      description: '${delivery.status.name} -> ${to.name}',
      previousStateName: delivery.status.name,
      newStateName: to.name,
      reason: reason,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return updated;
  }
}
