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
import 'record_kitchen_event.dart';

/// Transitions one [KitchenWorkItem] to a new [KitchenLineStatus] — the
/// single use case behind acknowledge/start-preparation/cancel/mark-
/// unavailable/recall/resume (Phase 4B/4K), the same "one use case, not N
/// near-duplicates" consolidation `FireKitchenTicket` already established
/// for initial/delta/cancellation tickets (Sprint 3D).
///
/// Validates the transition via `KitchenLineStatusTransitions.canTransition`
/// (throws [InvalidKitchenLineTransitionViolation] otherwise) and
/// [expectedRevision] against the item's current [KitchenWorkItem.revision]
/// (throws [StaleKitchenRevisionViolation] otherwise) — the optimistic-
/// concurrency check that prevents two devices from both completing the
/// same line (Phase 4G).
///
/// Requires the [PosAuthorizedAction] matching [to] (every target status
/// maps to exactly one). Always records a [KitchenAuditEntry] and a
/// [KitchenEvent] — every operational action leaves both, per Phase 4K.
class TransitionKitchenWorkItem {
  const TransitionKitchenWorkItem({
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

  static PosAuthorizedAction _actionFor(KitchenLineStatus to) {
    switch (to) {
      case KitchenLineStatus.acknowledged:
        return PosAuthorizedAction.acknowledgeKitchenItem;
      case KitchenLineStatus.preparing:
        return PosAuthorizedAction.startKitchenPreparation;
      case KitchenLineStatus.ready:
        return PosAuthorizedAction.markKitchenItemReady;
      case KitchenLineStatus.cancelled:
        return PosAuthorizedAction.cancelKitchenLine;
      case KitchenLineStatus.unavailable:
        return PosAuthorizedAction.cancelKitchenLine;
      case KitchenLineStatus.recalled:
        return PosAuthorizedAction.recallKitchenLine;
      case KitchenLineStatus.queued:
        return PosAuthorizedAction.startKitchenPreparation;
      case KitchenLineStatus.wasted:
        // AP-5 Sprint 3 — same action family as cancelled/unavailable; in
        // practice this transition is always server-triggered
        // (`cancelOrderLineStock.ts`, on post-prep cancellation), never
        // invoked through this local use case, but the mapping must still
        // be total.
        return PosAuthorizedAction.cancelKitchenLine;
    }
  }

  static KitchenAuditEventType _auditTypeFor(KitchenLineStatus to) {
    switch (to) {
      case KitchenLineStatus.acknowledged:
        return KitchenAuditEventType.acknowledged;
      case KitchenLineStatus.preparing:
        return KitchenAuditEventType.preparationStarted;
      case KitchenLineStatus.ready:
        return KitchenAuditEventType.markedReady;
      case KitchenLineStatus.cancelled:
        return KitchenAuditEventType.cancelled;
      case KitchenLineStatus.unavailable:
        return KitchenAuditEventType.markedUnavailable;
      case KitchenLineStatus.recalled:
        return KitchenAuditEventType.recalled;
      case KitchenLineStatus.queued:
        return KitchenAuditEventType.resumed;
      case KitchenLineStatus.wasted:
        return KitchenAuditEventType.wasted;
    }
  }

  static KitchenEventType _eventTypeFor(KitchenLineStatus to) {
    switch (to) {
      case KitchenLineStatus.acknowledged:
        return KitchenEventType.workItemAcknowledged;
      case KitchenLineStatus.preparing:
        return KitchenEventType.workItemPreparingStarted;
      case KitchenLineStatus.ready:
        return KitchenEventType.workItemReady;
      case KitchenLineStatus.cancelled:
        return KitchenEventType.workItemCancelled;
      case KitchenLineStatus.unavailable:
        return KitchenEventType.workItemUnavailable;
      case KitchenLineStatus.recalled:
        return KitchenEventType.workItemRecalled;
      case KitchenLineStatus.queued:
        return KitchenEventType.workItemResumed;
      case KitchenLineStatus.wasted:
        return KitchenEventType.workItemWasted;
    }
  }

  Future<KitchenWorkItem> call({
    required String workItemId,
    required KitchenLineStatus to,
    required int expectedRevision,
    required String performedByStaffId,
    String? deviceId,
    String? reason,
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
    // `resumed` is modeled as a transition to `preparing` from `recalled`
    // — handled by the normal state-machine check below; `queued` is only
    // ever an initial-enqueue status and is never a valid transition
    // target here (guarded by `canTransition` returning false for it).
    if (!KitchenLineStatusTransitions.canTransition(item.status, to)) {
      throw InvalidKitchenLineTransitionViolation(
        fromStatusName: item.status.name,
        toStatusName: to.name,
      );
    }

    final isResume = item.status == KitchenLineStatus.recalled &&
        to == KitchenLineStatus.preparing;
    final action =
        isResume ? PosAuthorizedAction.startKitchenPreparation : _actionFor(to);

    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'workItemId': workItemId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final updated = item.copyWith(
      status: to,
      acknowledgedAt: to == KitchenLineStatus.acknowledged ? now : null,
      preparingStartedAt: to == KitchenLineStatus.preparing ? now : null,
      readyAt: to == KitchenLineStatus.ready ? now : null,
      cancelledAt: to == KitchenLineStatus.cancelled ? now : null,
      unavailableAt: to == KitchenLineStatus.unavailable ? now : null,
      recalledAt: to == KitchenLineStatus.recalled ? now : null,
      wastedAt: to == KitchenLineStatus.wasted ? now : null,
      revision: item.revision + 1,
    );
    await _projectionRepository.save(updated);

    final event = await _recordKitchenEvent(
      branchId: item.branchId,
      orderId: item.orderId,
      kitchenTicketId: item.kitchenTicketId,
      workItemId: item.id,
      type: isResume ? KitchenEventType.workItemResumed : _eventTypeFor(to),
      idempotencyKey: '${item.id}-rev${updated.revision}',
      occurredAt: now,
      sourceDeviceId: deviceId,
      payload: reason == null ? const {} : {'reason': reason},
    );

    await _auditRepository.appendEvent(KitchenAuditEntry(
      id: '${event.id}-audit',
      branchId: item.branchId,
      orderId: item.orderId.value,
      kitchenTicketId: item.kitchenTicketId,
      workItemId: item.id,
      deviceId: deviceId,
      type: isResume ? KitchenAuditEventType.resumed : _auditTypeFor(to),
      description:
          '${item.kitchenTicketLineId}: ${item.status.name} -> ${to.name}',
      actorStaffId: performedByStaffId,
      previousStateName: item.status.name,
      newStateName: to.name,
      reason: reason,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return updated;
  }
}
