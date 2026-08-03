import 'import_audit_event_type.dart';

/// One immutable, append-only audit record of a Smart Import lifecycle
/// event — Phase 7 (`docs/decisions.md` ADR-024). Deliberately never
/// carries the source file's raw bytes/content — "no sensitive source
/// documents in general audit logs" — only [description] (a short,
/// human summary) and [targetEntityId] (the `ImportJob.id`).
class ImportAuditEntry {
  const ImportAuditEntry({
    required this.id,
    required this.branchId,
    required this.actorId,
    required this.type,
    required this.description,
    required this.targetEntityId,
    required this.timestamp,
  });

  final String id;
  final String branchId;
  final String actorId;
  final ImportAuditEventType type;
  final String description;
  final String targetEntityId;
  final DateTime timestamp;
}
