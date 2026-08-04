import '../../../pos/domain/authorization/staff_role.dart';
import 'staff_member_status.dart';

/// A registered staff/manager/admin/courier account — the registry
/// `ActorSession` instances are minted from (`StaffAuthRepository`).
/// Phase 6B/6C (`docs/decisions.md` ADR-023).
///
/// Mutable registry entity (mirrors `Courier`, not
/// `CourierCompensationProfile`'s history-preserving versioning) — an
/// administrator edits a member's current shape in place, but every role
/// change is separately, permanently recorded via
/// [StaffRoleChangeEvent]/`StaffRoleChangeEventRepository` — "role
/// changes are append-only" holds at the event-log level even though the
/// registry record itself is mutable, exactly like `VisitRewardRule`
/// (mutable) plus `CustomerRewardGrant` (append-only) in `features/crm`.
class StaffMember {
  const StaffMember({
    required this.id,
    required this.displayName,
    this.roles = const {},
    this.branchAccess = const {},
    this.restaurantAccess = const {},
    this.organizationAccess = const {},
    this.status = StaffMemberStatus.active,
    this.sessionsRevokedAt,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String displayName;
  final Set<StaffRole> roles;
  final Set<String> branchAccess;
  final Set<String> restaurantAccess;

  /// **Phase 8**: every tenant `organizationId` this member is granted
  /// access to — mirrors [branchAccess]'s empty-means-none convention.
  /// See `ActorSession.organizationAccess`'s doc comment for why no
  /// role, including `StaffRole.admin`, is exempt from needing this.
  final Set<String> organizationAccess;
  final StaffMemberStatus status;

  /// Set by `RevokeStaffSession` — "forced session revocation contract."
  /// Any `ActorSession` issued before this timestamp is treated as
  /// invalid the next time `StaffAuthRepository.refreshSession` runs,
  /// even though nothing can reach into an already-running client and
  /// invalidate it live (this codebase has no such push mechanism).
  final DateTime? sessionsRevokedAt;

  final DateTime createdAt;
  final int revision;

  bool get isActive => status == StaffMemberStatus.active;

  StaffMember copyWith({
    String? displayName,
    Set<StaffRole>? roles,
    Set<String>? branchAccess,
    Set<String>? restaurantAccess,
    Set<String>? organizationAccess,
    StaffMemberStatus? status,
    DateTime? sessionsRevokedAt,
    bool clearSessionsRevokedAt = false,
    required int revision,
  }) {
    return StaffMember(
      id: id,
      displayName: displayName ?? this.displayName,
      roles: roles ?? this.roles,
      branchAccess: branchAccess ?? this.branchAccess,
      restaurantAccess: restaurantAccess ?? this.restaurantAccess,
      organizationAccess: organizationAccess ?? this.organizationAccess,
      status: status ?? this.status,
      sessionsRevokedAt: clearSessionsRevokedAt
          ? null
          : (sessionsRevokedAt ?? this.sessionsRevokedAt),
      createdAt: createdAt,
      revision: revision,
    );
  }
}
