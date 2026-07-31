import 'admin_audit_event_type.dart';

/// One immutable, append-only audit record of an Admin Platform mutation
/// — Phase 6 (`docs/decisions.md` ADR-023). Same shape and reasoning as
/// `CrmAuditEntry`/`CourierOperationalAuditEntry`: a deliberately
/// separate type per bounded context, not a shared/reused one — the
/// unified read-only view over all of them lives in the Audit Center
/// (`BuildAuditCenterProjection`), not in a shared write-side type.
class AdminAuditEntry {
  const AdminAuditEntry({
    required this.id,
    this.branchId,
    required this.actorId,
    this.actorRole,
    required this.type,
    required this.description,
    required this.targetEntityId,
    this.previousStateName,
    this.newStateName,
    required this.timestamp,
  });

  final String id;
  final String? branchId;
  final String actorId;
  final String? actorRole;
  final AdminAuditEventType type;
  final String description;
  final String targetEntityId;
  final String? previousStateName;
  final String? newStateName;
  final DateTime timestamp;
}
