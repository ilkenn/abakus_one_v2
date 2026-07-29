import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/delivery_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/delivery/delivery.dart';
import '../../domain/delivery/delivery_status.dart';
import '../../domain/events/courier_event_type.dart';
import 'courier_location_availability_guard.dart';
import 'record_courier_event.dart';

/// Confirms courier pickup of a delivery's package — Phase 5F's
/// package-pickup integration. **Idempotent**: if the delivery is already
/// [DeliveryStatus.pickedUp], returns it unchanged rather than erroring or
/// re-advancing `PackagePreparation` a second time.
///
/// **Kitchen-ready is not automatically package-ready, and package-ready
/// is not automatically picked up** — this use case is the explicit
/// courier action that closes that final gap. [isPackageReadyForPickup]
/// is an injected closure (never a direct `PackagePreparationRepository`
/// dependency — mirrors `CompleteKitchenOrderPreparation`'s (Phase 4)
/// exact closure-injection pattern for the same `pos`→`orders` boundary
/// reason) checking the current `PackagePreparationStatus`; a `false`
/// result throws [PackageNotReadyForPickupViolation] — "courier cannot
/// pick up an unprepared package."
///
/// [advanceToCourierCollected] bridges `PackagePreparation` from
/// `waitingForCourier`/`packed` to `courierCollected` — also an injected
/// closure, called only on a genuine (non-idempotent-repeat) success.
///
/// **Sprint 5B**: [locationGuard], when supplied, requires location to be
/// available before a genuine (non-idempotent-repeat) pickup is confirmed
/// — "a courier cannot... start pickup... while location is unavailable."
/// `null` (the default) skips the check.
class ConfirmPackagePickup {
  const ConfirmPackagePickup({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required DeliveryRepository repository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
    required Future<bool> Function({required OrderId orderId})
        isPackageReadyForPickup,
    required Future<void> Function({
      required OrderId orderId,
      required String performedByStaffId,
      required DateTime at,
    }) advanceToCourierCollected,
    CourierLocationAvailabilityGuard? locationGuard,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent,
        _isPackageReadyForPickup = isPackageReadyForPickup,
        _advanceToCourierCollected = advanceToCourierCollected,
        _locationGuard = locationGuard;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final DeliveryRepository _repository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;
  final Future<bool> Function({required OrderId orderId})
      _isPackageReadyForPickup;
  final Future<void> Function({
    required OrderId orderId,
    required String performedByStaffId,
    required DateTime at,
  }) _advanceToCourierCollected;
  final CourierLocationAvailabilityGuard? _locationGuard;

  Future<Delivery> call({
    required String deliveryId,
    required String performedByStaffId,
    String? deviceId,
    String pickupNotes = '',
  }) async {
    final delivery = await _repository.findById(deliveryId);
    if (delivery == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'Delivery',
        id: deliveryId,
      );
    }
    if (delivery.status == DeliveryStatus.pickedUp) return delivery;

    if (delivery.courierId != null) {
      await _locationGuard?.assertAvailable(
        courierId: delivery.courierId!,
        deliveryId: deliveryId,
      );
    }

    if (delivery.status != DeliveryStatus.arrivedAtRestaurant) {
      throw InvalidDeliveryTransitionViolation(
        fromStatusName: delivery.status.name,
        toStatusName: DeliveryStatus.pickedUp.name,
      );
    }

    final isReady = await _isPackageReadyForPickup(orderId: delivery.orderId);
    if (!isReady) {
      throw PackageNotReadyForPickupViolation(
        deliveryId: deliveryId,
        packageStatusName: 'not ready',
      );
    }

    const action = PosAuthorizedAction.confirmPackagePickup;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'deliveryId': deliveryId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final updated = delivery.copyWith(
      status: DeliveryStatus.pickedUp,
      revision: delivery.revision + 1,
    );
    await _repository.save(updated);

    await _advanceToCourierCollected(
      orderId: delivery.orderId,
      performedByStaffId: performedByStaffId,
      at: now,
    );

    final event = await _recordCourierEvent(
      branchId: delivery.branchId,
      courierId: delivery.courierId,
      deliveryId: delivery.id,
      type: CourierEventType.packagePickedUp,
      idempotencyKey: '${delivery.id}-rev${updated.revision}',
      occurredAt: now,
      sourceDeviceId: deviceId,
      payload: {if (pickupNotes.isNotEmpty) 'pickupNotes': pickupNotes},
    );

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${event.id}-audit',
      branchId: delivery.branchId,
      actorStaffId: performedByStaffId,
      courierId: delivery.courierId,
      deviceId: deviceId,
      orderId: delivery.orderId.value,
      deliveryId: delivery.id,
      type: CourierAuditEventType.packagePickedUp,
      description:
          'Package picked up${pickupNotes.isEmpty ? '' : ': $pickupNotes'}',
      previousStateName: DeliveryStatus.arrivedAtRestaurant.name,
      newStateName: DeliveryStatus.pickedUp.name,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return updated;
  }
}
