import 'courier_audit_event_type.dart';

/// One line of the manager-facing "Operation Timeline" — Sprint 5C
/// Part 11. A display-friendly reshaping of an existing
/// `CourierOperationalAuditEntry`, with [courierDisplayName] resolved for
/// readability (`CourierOperationalAuditEntry.courierId` alone isn't
/// presentable). Carries no new information — every field traces back to
/// the audit entry it was built from.
class CourierOperationTimelineEntry {
  const CourierOperationTimelineEntry({
    required this.timestamp,
    required this.type,
    required this.description,
    required this.actorStaffId,
    this.courierId,
    this.courierDisplayName,
  });

  final DateTime timestamp;
  final CourierAuditEventType type;
  final String description;
  final String actorStaffId;
  final String? courierId;
  final String? courierDisplayName;
}
