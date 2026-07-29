import 'courier_audit_event_type.dart';

/// One immutable, append-only audit record of a courier-operations
/// action — actor, actor role, courier, device, branch, order, delivery,
/// assignment, shift, previous/new state, reason, timestamp, a
/// [locationRef] (never raw coordinates — see below), and a
/// [correlationId] tying it back to the [CourierEvent] that produced it.
///
/// No "tenantId" field: no tenant concept exists anywhere in this
/// codebase (confirmed during Phase 5's pre-implementation analysis) —
/// [branchId] is the actual scoping boundary, matching every other audit
/// type in this codebase (`docs/decisions.md` ADR-017).
///
/// **[locationRef] is an opaque reference (e.g. a `CourierLocationSnapshot`
/// id), never raw latitude/longitude** — "never place unnecessary raw
/// personal or location data in general-purpose audit logs" is enforced by
/// this field's very shape, not by caller discipline.
class CourierOperationalAuditEntry {
  const CourierOperationalAuditEntry({
    required this.id,
    required this.branchId,
    required this.actorStaffId,
    this.actorRole,
    this.courierId,
    this.deviceId,
    this.orderId,
    this.deliveryId,
    this.assignmentId,
    this.shiftId,
    required this.type,
    required this.description,
    this.previousStateName,
    this.newStateName,
    this.reason,
    required this.timestamp,
    this.locationRef,
    required this.correlationId,
  });

  final String id;
  final String branchId;
  final String actorStaffId;
  final String? actorRole;
  final String? courierId;
  final String? deviceId;
  final String? orderId;
  final String? deliveryId;
  final String? assignmentId;
  final String? shiftId;

  final CourierAuditEventType type;
  final String description;
  final String? previousStateName;
  final String? newStateName;
  final String? reason;
  final DateTime timestamp;

  /// Opaque reference to a `CourierLocationSnapshot`, never raw
  /// coordinates.
  final String? locationRef;

  final String correlationId;
}
