import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_delivery_sequence_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/delivery_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/delivery/courier_delivery_sequence.dart';
import '../../domain/events/courier_event_type.dart';
import 'record_courier_event.dart';

/// A manager reorders which of a courier's active deliveries to work on
/// next — Sprint 5C Part 5's "delivery sequence control." **Manager-only**
/// — gated by [PosAuthorizedAction.reorderCourierDeliverySequence]; no
/// courier-facing use case ever writes to
/// `CourierDeliverySequenceRepository`, so "courier cannot modify
/// sequence" holds structurally.
///
/// [newOrder] must be exactly the courier's current active
/// (non-terminal) delivery ids, in any order — never more, fewer, or
/// duplicated, and never a completed/terminal delivery (which
/// `DeliveryRepository.findActiveByCourierId` already excludes) — "
/// completed deliveries cannot move." A mismatch throws
/// [InvalidDeliverySequenceViolation] before anything is written.
///
/// "Courier app updates immediately" is satisfied the same way every
/// other real-time courier-facing change in this app is — a
/// [CourierEventType.deliverySequenceReordered] event through the
/// existing same-process `CourierEventBus`/reconnect-sync contract
/// (`docs/decisions.md` ADR-017's documented same-process boundary),
/// never a claim of cross-device push this app's architecture cannot
/// honestly make.
class ReorderCourierDeliverySequence {
  const ReorderCourierDeliverySequence({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required DeliveryRepository deliveryRepository,
    required CourierDeliverySequenceRepository sequenceRepository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _deliveryRepository = deliveryRepository,
        _sequenceRepository = sequenceRepository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final DeliveryRepository _deliveryRepository;
  final CourierDeliverySequenceRepository _sequenceRepository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;

  Future<CourierDeliverySequence> call({
    required String courierId,
    required String branchId,
    required List<String> newOrder,
    required String performedByStaffId,
    String? reason,
  }) async {
    const action = PosAuthorizedAction.reorderCourierDeliverySequence;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'courierId': courierId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final activeDeliveries =
        await _deliveryRepository.findActiveByCourierId(courierId);
    final expectedIds = activeDeliveries.map((d) => d.id).toSet();
    final submittedIds = newOrder.toSet();
    if (expectedIds.length != newOrder.length ||
        !expectedIds.containsAll(submittedIds) ||
        !submittedIds.containsAll(expectedIds)) {
      throw InvalidDeliverySequenceViolation(
        courierId: courierId,
        expectedDeliveryIds: activeDeliveries.map((d) => d.id).toList(),
        submittedDeliveryIds: newOrder,
      );
    }

    final previous = await _sequenceRepository.findLatestByCourierId(courierId);
    final now = _clock.now();
    final updated = CourierDeliverySequence(
      courierId: courierId,
      branchId: branchId,
      orderedDeliveryIds: newOrder,
      updatedAt: now,
      updatedByStaffId: performedByStaffId,
      revision: (previous?.revision ?? 0) + 1,
    );
    await _sequenceRepository.save(updated);

    final event = await _recordCourierEvent(
      branchId: branchId,
      courierId: courierId,
      type: CourierEventType.deliverySequenceReordered,
      idempotencyKey: '$courierId-sequence-rev${updated.revision}',
      occurredAt: now,
      payload: {'order': newOrder.join(',')},
    );

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${event.id}-audit',
      branchId: branchId,
      actorStaffId: performedByStaffId,
      courierId: courierId,
      type: CourierAuditEventType.deliverySequenceReordered,
      description: 'Delivery sequence reordered: '
          '${previous?.orderedDeliveryIds.join(', ') ?? '(none)'} -> '
          '${newOrder.join(', ')}',
      reason: reason,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return updated;
  }
}
