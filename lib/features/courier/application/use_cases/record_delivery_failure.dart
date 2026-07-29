import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/delivery_failure_repository.dart';
import '../../data/delivery_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/delivery/delivery_failure.dart';
import '../../domain/delivery/delivery_failure_reason.dart';
import '../../domain/delivery/delivery_status.dart';
import '../../domain/events/courier_event_type.dart';
import '../identity/delivery_failure_id_generator.dart';
import 'record_courier_event.dart';

/// Records a failed pickup/delivery attempt — **only predefined
/// [DeliveryFailureReason]s are ever accepted**; no unrestricted
/// courier-written accusation field exists. [courierNote] is operational
/// and length-limited (280 characters — enforced here, matching
/// `CourierFeedback.note`'s same limit).
///
/// [DeliveryFailure.responsibility] is derived from [reasonCode] and
/// frozen (`DeliveryFailureResponsibilityMapper`) — never independently
/// settable. Only a customer-attributable failure may ever emit a
/// customer-risk signal ([DeliveryFailure.mayEmitCustomerRiskSignal]) —
/// this use case only *reports* that boolean; **no fraud/risk engine
/// exists in this phase** to act on it.
class RecordDeliveryFailure {
  const RecordDeliveryFailure({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required DeliveryFailureIdGenerator idGenerator,
    required DeliveryRepository deliveryRepository,
    required DeliveryFailureRepository failureRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _deliveryRepository = deliveryRepository,
        _failureRepository = failureRepository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final DeliveryFailureIdGenerator _idGenerator;
  final DeliveryRepository _deliveryRepository;
  final DeliveryFailureRepository _failureRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;

  static const _maxNoteLength = 280;

  Future<DeliveryFailure> call({
    required String deliveryId,
    required DeliveryFailureReason reasonCode,
    String courierNote = '',
    required String performedByStaffId,
    String? deviceId,
  }) async {
    final delivery = await _deliveryRepository.findById(deliveryId);
    if (delivery == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'Delivery',
        id: deliveryId,
      );
    }

    final isPickupStage = delivery.status == DeliveryStatus.arrivedAtRestaurant;
    final targetStatus = isPickupStage
        ? DeliveryStatus.pickupFailed
        : DeliveryStatus.deliveryFailed;

    if (!DeliveryStatusTransitions.canTransition(
        delivery.status, targetStatus)) {
      throw InvalidDeliveryTransitionViolation(
        fromStatusName: delivery.status.name,
        toStatusName: targetStatus.name,
      );
    }

    const action = PosAuthorizedAction.recordFailedDelivery;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'deliveryId': deliveryId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final truncatedNote = courierNote.length > _maxNoteLength
        ? courierNote.substring(0, _maxNoteLength)
        : courierNote;

    final failure = DeliveryFailure(
      id: _idGenerator.nextFailureId(),
      deliveryId: deliveryId,
      reasonCode: reasonCode,
      courierNote: truncatedNote,
      recordedByStaffId: performedByStaffId,
      recordedAt: now,
    );
    await _failureRepository.append(failure);

    final updatedDelivery = delivery.copyWith(
      status: targetStatus,
      revision: delivery.revision + 1,
    );
    await _deliveryRepository.save(updatedDelivery);

    final event = await _recordCourierEvent(
      branchId: delivery.branchId,
      courierId: delivery.courierId,
      deliveryId: delivery.id,
      type: isPickupStage
          ? CourierEventType.pickupFailed
          : CourierEventType.deliveryFailed,
      idempotencyKey: '${delivery.id}-rev${updatedDelivery.revision}',
      occurredAt: now,
      sourceDeviceId: deviceId,
      payload: {
        'reasonCode': reasonCode.name,
        'responsibility': failure.responsibility.name,
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
      type: CourierAuditEventType.deliveryFailed,
      description:
          'Failure recorded: ${reasonCode.name} (${failure.responsibility.name})',
      previousStateName: delivery.status.name,
      newStateName: targetStatus.name,
      reason: truncatedNote.isEmpty ? null : truncatedNote,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return failure;
  }
}
