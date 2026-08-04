import 'integration_audit_event_type.dart';

/// One immutable, append-only audit record of an Integration Hub
/// mutation — Phase 8 (`docs/decisions.md` ADR-025).
class IntegrationAuditEntry {
  const IntegrationAuditEntry({
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
  final IntegrationAuditEventType type;
  final String description;
  final String targetEntityId;
  final DateTime timestamp;
}
