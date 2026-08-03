import 'entitlement_audit_event_type.dart';

/// One immutable, append-only audit record of an entitlement mutation —
/// Phase 7 (`docs/decisions.md` ADR-024). Same shape and reasoning as
/// `AdminAuditEntry`/`CrmAuditEntry`: a deliberately separate type per
/// bounded context, not a shared/reused one — `features/entitlements`
/// does not import from `features/admin` (that dependency direction only
/// ever runs the other way, admin reaching into feature bounded
/// contexts, never the reverse).
class EntitlementAuditEntry {
  const EntitlementAuditEntry({
    required this.id,
    required this.actorId,
    required this.type,
    required this.description,
    required this.targetEntityId,
    this.previousStateName,
    this.newStateName,
    required this.timestamp,
  });

  final String id;
  final String actorId;
  final EntitlementAuditEventType type;
  final String description;
  final String targetEntityId;
  final String? previousStateName;
  final String? newStateName;
  final DateTime timestamp;
}
