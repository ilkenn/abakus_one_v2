import 'supplier_audit_event_type.dart';

/// Kept as its own type — continues the "separate audit type per
/// bounded context" precedent (`docs/decisions.md` ADR-024). Never
/// contains a supplier's raw negotiated price text beyond the
/// structured [Money] already in the source record — supplier
/// pricing is confidential (`PosAuthorizedAction.manageSupplierPricing`
/// is admin-only).
class SupplierAuditEntry {
  const SupplierAuditEntry({
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
  final SupplierAuditEventType type;
  final String description;
  final String targetEntityId;
  final DateTime timestamp;
}
