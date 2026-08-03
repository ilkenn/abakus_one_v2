import 'setup_audit_event_type.dart';

class SetupAuditEntry {
  const SetupAuditEntry({
    required this.id,
    required this.branchId,
    required this.actorId,
    required this.type,
    required this.description,
    required this.targetEntityId,
    required this.timestamp,
  });

  final String id;

  /// `null` for events with no single branch (e.g. `SetupTemplate`
  /// creation, which is platform- or organization-scoped, not
  /// branch-scoped).
  final String? branchId;

  final String actorId;
  final SetupAuditEventType type;
  final String description;
  final String targetEntityId;
  final DateTime timestamp;
}
