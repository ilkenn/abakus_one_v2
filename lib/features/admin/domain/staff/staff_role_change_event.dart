import '../../../pos/domain/authorization/staff_role.dart';

/// Whether a [StaffRoleChangeEvent] granted or revoked [StaffRoleChangeEvent
/// .role].
enum StaffRoleChangeType { granted, revoked }

/// One immutable, append-only record of a role being granted to or
/// revoked from a [StaffMember] — "role changes are append-only" and "no
/// deletion of role history" (Phase 6C, `docs/decisions.md` ADR-023).
/// `StaffRoleChangeEventRepository` has no update/delete method at all,
/// matching every other audit-shaped repository in this codebase.
class StaffRoleChangeEvent {
  const StaffRoleChangeEvent({
    required this.id,
    required this.staffMemberId,
    required this.changeType,
    required this.role,
    required this.performedByStaffId,
    required this.occurredAt,
  });

  final String id;
  final String staffMemberId;
  final StaffRoleChangeType changeType;
  final StaffRole role;
  final String performedByStaffId;
  final DateTime occurredAt;
}
