import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/delivery_proof_repository.dart';
import '../../data/delivery_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/delivery/delivery.dart';
import '../../domain/delivery/delivery_proof.dart';
import '../../domain/delivery/delivery_proof_type.dart';
import '../../domain/delivery/delivery_status.dart';
import '../../domain/events/courier_event_type.dart';
import '../../domain/location/geofence_evaluation_result.dart';
import '../../domain/location/geofence_zone_type.dart';
import '../identity/delivery_proof_id_generator.dart';
import 'record_courier_event.dart';

/// Completes a [Delivery] — "delivered." **Completed deliveries are
/// immutable**: [DeliveryStatus.delivered] is terminal
/// (`DeliveryStatusTransitions`), and this call is idempotent (a second
/// call for an already-delivered delivery returns it unchanged rather
/// than erroring or double-recording proof/events).
///
/// Requires: an active accepted assignment to the calling courier (throws
/// [DeliveryNotAssignedToCourierViolation] otherwise), the correct
/// lifecycle stage ([DeliveryStatus.arrivedAtCustomer]), a passing
/// geofence evaluation or an approved override, and a [proofType].
///
/// **Cash-on-delivery integrates with Sprint 3F's boundaries without
/// duplication**: this use case never touches `PaymentSession`/
/// `CourierCashCollection` itself — declaring collected cash is a
/// separate action (`DeclareCourierCashCollectionForDelivery`, which
/// calls Sprint 3F's existing `RecordCourierCashCollection` directly).
/// "Operational completion must not modify `PaymentSession` history" is
/// therefore true structurally, not by caller discipline.
class CompleteDelivery {
  const CompleteDelivery({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required DeliveryRepository repository,
    required DeliveryProofIdGenerator proofIdGenerator,
    required DeliveryProofRepository proofRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
    Future<void> Function({
      required OrderId orderId,
      required String performedByStaffId,
      required DateTime at,
    })? advanceToDelivered,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _proofIdGenerator = proofIdGenerator,
        _proofRepository = proofRepository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent,
        _advanceToDelivered = advanceToDelivered;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final DeliveryRepository _repository;
  final DeliveryProofIdGenerator _proofIdGenerator;
  final DeliveryProofRepository _proofRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;
  final Future<void> Function({
    required OrderId orderId,
    required String performedByStaffId,
    required DateTime at,
  })? _advanceToDelivered;

  Future<Delivery> call({
    required String deliveryId,
    required String courierId,
    required int expectedRevision,
    required String performedByStaffId,
    String? deviceId,
    required DeliveryProofType proofType,
    String? proofReferenceToken,
    String? proofNote,
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
    if (delivery.status == DeliveryStatus.delivered) return delivery;

    if (delivery.courierId != courierId) {
      throw DeliveryNotAssignedToCourierViolation(
        deliveryId: deliveryId,
        courierId: courierId,
      );
    }
    if (delivery.revision != expectedRevision) {
      throw StaleCourierRevisionViolation(
        entityId: deliveryId,
        expectedRevision: expectedRevision,
        actualRevision: delivery.revision,
      );
    }
    if (delivery.status != DeliveryStatus.arrivedAtCustomer) {
      throw InvalidDeliveryTransitionViolation(
        fromStatusName: delivery.status.name,
        toStatusName: DeliveryStatus.delivered.name,
      );
    }
    if (geofenceResult != null &&
        !geofenceResult.passesAutomatically &&
        geofenceOverrideId == null) {
      throw GeofenceRequiresOverrideViolation(
        deliveryId: deliveryId,
        zoneTypeName: GeofenceZoneType.deliveryCompletion.name,
      );
    }

    const action = PosAuthorizedAction.completeDelivery;
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
      status: DeliveryStatus.delivered,
      deliveredAt: now,
      revision: delivery.revision + 1,
    );
    await _repository.save(updated);

    final proof = DeliveryProof(
      id: _proofIdGenerator.nextProofId(),
      deliveryId: deliveryId,
      type: proofType,
      referenceToken: proofReferenceToken,
      note: proofNote,
      recordedByStaffId: performedByStaffId,
      recordedAt: now,
    );
    await _proofRepository.append(proof);

    final advance = _advanceToDelivered;
    if (advance != null) {
      await advance(
        orderId: delivery.orderId,
        performedByStaffId: performedByStaffId,
        at: now,
      );
    }

    final event = await _recordCourierEvent(
      branchId: delivery.branchId,
      courierId: delivery.courierId,
      deliveryId: delivery.id,
      type: CourierEventType.deliveryCompleted,
      idempotencyKey: '${delivery.id}-rev${updated.revision}',
      occurredAt: now,
      sourceDeviceId: deviceId,
      payload: {'proofId': proof.id},
    );

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${event.id}-audit',
      branchId: delivery.branchId,
      actorStaffId: performedByStaffId,
      courierId: delivery.courierId,
      deviceId: deviceId,
      orderId: delivery.orderId.value,
      deliveryId: delivery.id,
      type: CourierAuditEventType.deliveryCompleted,
      description: 'Delivery completed (proof: ${proofType.name})',
      previousStateName: DeliveryStatus.arrivedAtCustomer.name,
      newStateName: DeliveryStatus.delivered.name,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return updated;
  }
}
