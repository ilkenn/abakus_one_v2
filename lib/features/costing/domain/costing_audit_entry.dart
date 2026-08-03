import 'costing_audit_event_type.dart';

/// Kept as its own type — continues the "separate audit type per
/// bounded context" precedent (`docs/decisions.md` ADR-024). Never
/// contains a supplier's raw negotiated price text beyond the
/// structured [Money] already in the source record — see §7T/7S
/// (confidential cost data).
class CostingAuditEntry {
  const CostingAuditEntry({
    required this.id,
    required this.organizationId,
    required this.actorId,
    required this.type,
    required this.description,
    required this.targetEntityId,
    required this.timestamp,
  });

  final String id;
  final String organizationId;
  final String actorId;
  final CostingAuditEventType type;
  final String description;
  final String targetEntityId;
  final DateTime timestamp;
}
