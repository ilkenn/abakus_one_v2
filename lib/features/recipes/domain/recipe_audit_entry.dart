import 'recipe_audit_event_type.dart';

/// Kept as its own type, not `InventoryAuditEntry` — Phase 7 continues
/// the "separate audit type per bounded context" precedent
/// (`CrmAuditEntry`, `InventoryAuditEntry`, ... —
/// `docs/decisions.md` ADR-024).
class RecipeAuditEntry {
  const RecipeAuditEntry({
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
  final RecipeAuditEventType type;
  final String description;
  final String targetEntityId;
  final DateTime timestamp;
}
