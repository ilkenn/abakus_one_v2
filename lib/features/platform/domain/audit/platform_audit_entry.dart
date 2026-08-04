import 'platform_audit_event_type.dart';

/// One immutable, append-only audit record of a Platform Owner Hub
/// mutation — Phase 8 (`docs/decisions.md` ADR-025).
class PlatformAuditEntry {
  const PlatformAuditEntry({
    required this.id,
    required this.actorId,
    required this.type,
    required this.description,
    required this.targetEntityId,
    required this.timestamp,
  });

  final String id;
  final String actorId;
  final PlatformAuditEventType type;
  final String description;
  final String targetEntityId;
  final DateTime timestamp;
}
