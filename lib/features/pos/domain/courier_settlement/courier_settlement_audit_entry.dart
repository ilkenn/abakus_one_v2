import 'courier_settlement_audit_event_type.dart';

/// One immutable, append-only audit record of a courier-settlement event
/// — mirrors `CashAuditEntry`'s shape, scoped by both [courierId] (a
/// courier's full settlement history across many sessions) and
/// [settlementSessionId] (one specific session).
class CourierSettlementAuditEntry {
  const CourierSettlementAuditEntry({
    required this.id,
    required this.courierId,
    required this.settlementSessionId,
    required this.type,
    required this.description,
    required this.actorStaffId,
    required this.timestamp,
    this.previousValue,
    this.newValue,
  });

  /// Externally supplied — no id-generation mechanism lives on this class.
  final String id;

  final String courierId;
  final String settlementSessionId;
  final CourierSettlementAuditEventType type;
  final String description;

  /// The staff member or courier who performed the action — a courier's
  /// own id for collection/declaration events, a manager's `staffId` for
  /// approval/rejection/adjustment/closure events.
  final String actorStaffId;

  final DateTime timestamp;

  final String? previousValue;
  final String? newValue;
}
