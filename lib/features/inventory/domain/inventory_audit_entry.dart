import 'inventory_audit_event_type.dart';

class InventoryAuditEntry {
  const InventoryAuditEntry({
    required this.id,
    required this.branchId,
    required this.actorId,
    required this.type,
    required this.description,
    required this.targetEntityId,
    required this.timestamp,
  });

  final String id;

  /// `null` for organization-scoped events (e.g. `Ingredient` creation,
  /// which has no single branch).
  final String? branchId;

  final String actorId;
  final InventoryAuditEventType type;
  final String description;
  final String targetEntityId;
  final DateTime timestamp;
}
