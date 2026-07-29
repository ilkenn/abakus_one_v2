import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/kitchen_audit_entry_repository.dart';
import '../../data/kitchen_projection_repository.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/kds/kitchen_audit_entry.dart';
import '../../domain/kds/kitchen_event_type.dart';
import '../../domain/kds/kitchen_line_status.dart';
import '../../domain/kds/kitchen_work_item.dart';
import 'mark_kitchen_ticket_line_ready.dart';
import 'record_kitchen_event.dart';

/// Records progress toward a [KitchenWorkItem]'s [KitchenWorkItem.quantity]
/// — quantity-level completion (Phase 4B: e.g. 2 of 3 burgers ready).
/// Only valid while the item is [KitchenLineStatus.preparing].
///
/// Once `readyQuantity` reaches `quantity`, the item transitions to
/// [KitchenLineStatus.ready] in the **same** revision bump (not a separate
/// `TransitionKitchenWorkItem` call, which would require reasoning about
/// two consecutive stale-revision windows) — and, to keep Sprint 3D's
/// `KitchenTicket.completedLineIds`/`orderReadyAt` from becoming a second,
/// conflicting truth, this also calls the existing (unmodified)
/// `MarkKitchenTicketLineReady`.
///
/// Idempotent for a no-op delta (`readyQuantityDelta <= 0`, or a delta
/// that wouldn't change an already-fully-ready item) — no new revision,
/// no duplicate event.
class RecordKitchenWorkItemQuantityReady {
  const RecordKitchenWorkItemQuantityReady({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required KitchenProjectionRepository projectionRepository,
    required KitchenAuditEntryRepository auditRepository,
    required RecordKitchenEvent recordKitchenEvent,
    required MarkKitchenTicketLineReady markKitchenTicketLineReady,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _projectionRepository = projectionRepository,
        _auditRepository = auditRepository,
        _recordKitchenEvent = recordKitchenEvent,
        _markKitchenTicketLineReady = markKitchenTicketLineReady;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final KitchenProjectionRepository _projectionRepository;
  final KitchenAuditEntryRepository _auditRepository;
  final RecordKitchenEvent _recordKitchenEvent;
  final MarkKitchenTicketLineReady _markKitchenTicketLineReady;

  Future<KitchenWorkItem> call({
    required String workItemId,
    required int expectedRevision,
    required int readyQuantityDelta,
    required String performedByStaffId,
    String? deviceId,
  }) async {
    final item = await _projectionRepository.findById(workItemId);
    if (item == null) {
      throw UnknownKdsEntityViolation(
        entityName: 'KitchenWorkItem',
        id: workItemId,
      );
    }
    if (item.revision != expectedRevision) {
      throw StaleKitchenRevisionViolation(
        entityId: workItemId,
        expectedRevision: expectedRevision,
        actualRevision: item.revision,
      );
    }
    if (item.status != KitchenLineStatus.preparing) {
      throw InvalidKitchenLineTransitionViolation(
        fromStatusName: item.status.name,
        toStatusName: KitchenLineStatus.ready.name,
      );
    }

    final newReadyQuantity =
        (item.readyQuantity + readyQuantityDelta).clamp(0, item.quantity);
    if (newReadyQuantity == item.readyQuantity) return item;

    final authResult = await _authorizationPolicy.authorize(
      action: PosAuthorizedAction.markKitchenItemReady,
      actorStaffId: performedByStaffId,
      context: {'workItemId': workItemId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(
        actionName: PosAuthorizedAction.markKitchenItemReady.name,
      );
    }

    final isFullyReady = newReadyQuantity >= item.quantity;
    final now = _clock.now();
    final updated = item.copyWith(
      readyQuantity: newReadyQuantity,
      status: isFullyReady ? KitchenLineStatus.ready : item.status,
      readyAt: isFullyReady ? now : null,
      revision: item.revision + 1,
    );
    await _projectionRepository.save(updated);

    final event = await _recordKitchenEvent(
      branchId: item.branchId,
      orderId: item.orderId,
      kitchenTicketId: item.kitchenTicketId,
      workItemId: item.id,
      type: isFullyReady
          ? KitchenEventType.workItemReady
          : KitchenEventType.workItemQuantityReady,
      idempotencyKey: '${item.id}-rev${updated.revision}',
      occurredAt: now,
      sourceDeviceId: deviceId,
      payload: {'readyQuantity': '$newReadyQuantity'},
    );

    await _auditRepository.appendEvent(KitchenAuditEntry(
      id: '${event.id}-audit',
      branchId: item.branchId,
      orderId: item.orderId.value,
      kitchenTicketId: item.kitchenTicketId,
      workItemId: item.id,
      deviceId: deviceId,
      type: isFullyReady
          ? KitchenAuditEventType.markedReady
          : KitchenAuditEventType.quantityProgressRecorded,
      description:
          '${item.kitchenTicketLineId}: $newReadyQuantity/${item.quantity} ready',
      actorStaffId: performedByStaffId,
      previousStateName: '${item.readyQuantity}/${item.quantity}',
      newStateName: '$newReadyQuantity/${item.quantity}',
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    if (isFullyReady) {
      await _markKitchenTicketLineReady(
        ticketId: item.kitchenTicketId,
        lineId: item.kitchenTicketLineId,
      );
    }

    return updated;
  }
}
