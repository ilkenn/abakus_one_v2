import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/kitchen_audit_entry_repository.dart';
import '../../data/kitchen_projection_repository.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/kds/kitchen_audit_entry.dart';
import '../../domain/kds/kitchen_event_type.dart';
import '../../domain/kds/kitchen_station.dart';
import '../../domain/kds/kitchen_work_item.dart';
import 'record_kitchen_event.dart';

/// Re-routes an existing [KitchenWorkItem] to a different [KitchenStation]
/// — Phase 4K's "change station" action, for manual correction of a
/// misrouted line (`KitchenRoutingResolver`'s own routing only runs once,
/// at enqueue time). Not valid once the item is terminal (cancelled/
/// unavailable) or already ready — a completed/closed-out item has
/// nothing left for a station reassignment to affect.
class ChangeKitchenWorkItemStation {
  const ChangeKitchenWorkItemStation({
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
    required KitchenStation newStation,
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
    if (item.station == newStation) return item;

    final authResult = await _authorizationPolicy.authorize(
      action: PosAuthorizedAction.changeKitchenStation,
      actorStaffId: performedByStaffId,
      context: {'workItemId': workItemId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(
        actionName: PosAuthorizedAction.changeKitchenStation.name,
      );
    }

    final now = _clock.now();
    final updated = KitchenWorkItem(
      id: item.id,
      branchId: item.branchId,
      station: newStation,
      orderId: item.orderId,
      kitchenTicketId: item.kitchenTicketId,
      kitchenTicketLineId: item.kitchenTicketLineId,
      quantity: item.quantity,
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
    );

    await _auditRepository.appendEvent(KitchenAuditEntry(
      id: '${event.id}-audit',
      branchId: item.branchId,
      orderId: item.orderId.value,
      kitchenTicketId: item.kitchenTicketId,
      workItemId: item.id,
      deviceId: deviceId,
      type: KitchenAuditEventType.stationChanged,
      description:
          '${item.kitchenTicketLineId}: ${item.station.name} -> ${newStation.name}',
      actorStaffId: performedByStaffId,
      previousStateName: item.station.name,
      newStateName: newStation.name,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return updated;
  }
}
