/// The kind of human-meaningful kitchen action a [KitchenAuditEntry]
/// records — deliberately narrower than `KitchenEventType` (no
/// connectivity/heartbeat events here; those are technical sync facts,
/// not operational actions requiring an audit trail).
enum KitchenAuditEventType {
  acknowledged,
  preparationStarted,
  markedReady,
  cancelled,
  markedUnavailable,
  recalled,
  resumed,
  reprinted,
  stationChanged,
  orderPreparationCompleted,
}

/// One immutable, append-only audit record of a kitchen operational
/// action — richer than every earlier audit-entry type in this codebase
/// (`ClosureAuditEntry`/`RestaurantOperationsAuditEntry`/`CashAuditEntry`/
/// `CourierSettlementAuditEntry`), since Phase 4K explicitly requires
/// device and correlation-id fields none of those needed. Structurally
/// append-only like all of them — no update/delete method exists on
/// `KitchenAuditEntryRepository`.
class KitchenAuditEntry {
  const KitchenAuditEntry({
    required this.id,
    required this.branchId,
    required this.orderId,
    this.kitchenTicketId,
    this.workItemId,
    this.deviceId,
    required this.type,
    required this.description,
    required this.actorStaffId,
    this.previousStateName,
    this.newStateName,
    this.reason,
    required this.timestamp,
    required this.correlationId,
  });

  /// Externally supplied — no id-generation mechanism lives on this class.
  final String id;

  final String branchId;
  final String orderId;
  final String? kitchenTicketId;
  final String? workItemId;
  final String? deviceId;

  final KitchenAuditEventType type;
  final String description;
  final String actorStaffId;

  final String? previousStateName;
  final String? newStateName;

  /// Required by the calling use case for actions where Phase 4K names a
  /// reason as mandatory (cancel, mark unavailable, recall) — left
  /// optional on this record itself since not every action requires one.
  final String? reason;

  final DateTime timestamp;

  /// The idempotency key of the `KitchenEvent`/use-case call that produced
  /// this entry — lets an operator trace one logical action across the
  /// event log and the audit trail without re-deriving it.
  final String correlationId;
}
