import 'cash_audit_event_type.dart';

/// One immutable, append-only audit record of a cash-management event —
/// mirrors `ClosureAuditEntry`/`RestaurantOperationsAuditEntry`'s shape,
/// drawer-scoped rather than order- or branch-scoped (a drawer's audit
/// trail spans every session it has ever had, which is what a manager
/// reviewing drawer history actually wants).
class CashAuditEntry {
  const CashAuditEntry({
    required this.id,
    required this.drawerId,
    required this.sessionId,
    required this.type,
    required this.description,
    required this.actorStaffId,
    required this.timestamp,
    this.previousValue,
    this.newValue,
  });

  /// Externally supplied — no id-generation mechanism lives on this class.
  final String id;

  final String drawerId;
  final String sessionId;
  final CashAuditEventType type;
  final String description;
  final String actorStaffId;
  final DateTime timestamp;

  final String? previousValue;
  final String? newValue;
}
