import 'menu_label_audit_event_type.dart';

/// Kept as its own type — continues the "separate audit type per
/// bounded context" precedent (`docs/decisions.md` ADR-024).
class MenuLabelAuditEntry {
  const MenuLabelAuditEntry({
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
  final MenuLabelAuditEventType type;
  final String description;
  final String targetEntityId;
  final DateTime timestamp;
}
