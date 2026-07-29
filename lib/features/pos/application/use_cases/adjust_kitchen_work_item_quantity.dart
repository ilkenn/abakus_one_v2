import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/kitchen_audit_entry_repository.dart';
import '../../data/kitchen_projection_repository.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/kds/kitchen_audit_entry.dart';
import '../../domain/kds/kitchen_event_type.dart';
import '../../domain/kds/kitchen_work_item.dart';
import 'record_kitchen_event.dart';

/// Corrects an existing [KitchenWorkItem]'s quantity — a quantity increase
/// or decrease on an *already-queued* line (Phase 4E's "increased
/// quantity"/"reduced quantity" delta scenarios), operating directly on
/// the work item's own stable id rather than needing `OrderLine` identity
/// at all (the same sidestep `KitchenTicketLine.id` already uses — see
/// `docs/decisions.md` ADR-013).
///
/// **Never replaces history**: the original [KitchenWorkItem.quantity] is
/// preserved on the [KitchenAuditEntry] (`previousStateName`) rather than
/// silently overwritten with no trace. [newQuantity] may never drop below
/// [KitchenWorkItem.readyQuantity] (can't reduce below what's already been
/// completed) — throws [InvalidKitchenLineTransitionViolation] otherwise,
/// reusing that violation type rather than adding a narrowly-scoped new
/// one.
class AdjustKitchenWorkItemQuantity {
  const AdjustKitchenWorkItemQuantity({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required KitchenProjectionRepository projectionRepository,
    required KitchenAuditEntryRepository auditRepository,
    required RecordKitchenEvent recordKitchenEvent,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _projectionRepository = projectionRepository,
        _auditRepository = auditRepository,
        _recordKitchenEvent = recordKitchenEvent;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final KitchenProjectionRepository _projectionRepository;
  final KitchenAuditEntryRepository _auditRepository;
  final RecordKitchenEvent _recordKitchenEvent;

  Future<KitchenWorkItem> call({
    required String workItemId,
    required int expectedRevision,
    required int newQuantity,
    required String reason,
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
    if (item.isTerminal) {
      throw InvalidKitchenLineTransitionViolation(
        fromStatusName: item.status.name,
        toStatusName: item.status.name,
      );
    }
    if (newQuantity < item.readyQuantity) {
      throw InvalidKitchenLineTransitionViolation(
        fromStatusName: '${item.readyQuantity}/${item.quantity}',
        toStatusName: '$newQuantity',
      );
    }
    if (newQuantity == item.quantity) return item;

    final authResult = await _authorizationPolicy.authorize(
      action: PosAuthorizedAction.startKitchenPreparation,
      actorStaffId: performedByStaffId,
      context: {'workItemId': workItemId, 'reason': reason},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(
        actionName: PosAuthorizedAction.startKitchenPreparation.name,
      );
    }

    final now = _clock.now();
    final originalQuantity = item.quantity;
    final updated = KitchenWorkItem(
      id: item.id,
      branchId: item.branchId,
      station: item.station,
      orderId: item.orderId,
      kitchenTicketId: item.kitchenTicketId,
      kitchenTicketLineId: item.kitchenTicketLineId,
      quantity: newQuantity,
      readyQuantity: item.readyQuantity,
      status: item.status,
      queuedAt: item.queuedAt,
      acknowledgedAt: item.acknowledgedAt,
      preparingStartedAt: item.preparingStartedAt,
      readyAt: item.readyAt,
      cancelledAt: item.cancelledAt,
      unavailableAt: item.unavailableAt,
      recalledAt: item.recalledAt,
      revision: item.revision + 1,
      idempotencyKey: item.idempotencyKey,
      sourceEventId: item.sourceEventId,
    );
    await _projectionRepository.save(updated);

    final event = await _recordKitchenEvent(
      branchId: item.branchId,
      orderId: item.orderId,
      kitchenTicketId: item.kitchenTicketId,
      workItemId: item.id,
      type: KitchenEventType.ticketDeltaFired,
      idempotencyKey: '${item.id}-rev${updated.revision}',
      occurredAt: now,
      sourceDeviceId: deviceId,
      payload: {
        'previousQuantity': '$originalQuantity',
        'newQuantity': '$newQuantity',
        'reason': reason,
      },
    );

    await _auditRepository.appendEvent(KitchenAuditEntry(
      id: '${event.id}-audit',
      branchId: item.branchId,
      orderId: item.orderId.value,
      kitchenTicketId: item.kitchenTicketId,
      workItemId: item.id,
      deviceId: deviceId,
      type: KitchenAuditEventType.quantityAdjusted,
      description:
          '${item.kitchenTicketLineId}: quantity $originalQuantity -> $newQuantity',
      actorStaffId: performedByStaffId,
      previousStateName: '$originalQuantity',
      newStateName: '$newQuantity',
      reason: reason,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return updated;
  }
}
