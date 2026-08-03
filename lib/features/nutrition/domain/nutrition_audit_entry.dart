import 'nutrition_audit_event_type.dart';

/// Kept as its own type, not `RecipeAuditEntry`/`InventoryAuditEntry`
/// — continues the "separate audit type per bounded context"
/// precedent (`docs/decisions.md` ADR-024).
class NutritionAuditEntry {
  const NutritionAuditEntry({
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
  final NutritionAuditEventType type;
  final String description;
  final String targetEntityId;
  final DateTime timestamp;
}
