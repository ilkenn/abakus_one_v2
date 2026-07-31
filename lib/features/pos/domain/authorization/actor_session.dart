import 'staff_role.dart';

/// The currently active authenticated actor — Sprint 5E's real
/// authorization foundation. Replaces the bare `String actorStaffId`
/// [PosAuthorizationPolicy] callers already pass with something an actual
/// policy can verify against, without changing that interface (avoiding a
/// large migration across 100+ existing call sites — `docs/decisions.md`
/// ADR-022).
///
/// [roles] is the actor's full set of held roles — [RealPosAuthorizationPolicy]
/// authorizes against the **union** of every role's permissions, never
/// only [activeRole]. [activeRole] is a separate, narrower concept: which
/// role the actor is *currently operating as* for UI/context purposes
/// (e.g. which dashboard they're viewing) — see
/// `RolePermissionMap.allowsForActiveRole` for a check scoped to it
/// specifically. Nothing an actor is capable of
/// disappears just because their active role is currently something else;
/// [activeRole] never restricts [RealPosAuthorizationPolicy.authorize]
/// itself.
class ActorSession {
  const ActorSession({
    required this.actorId,
    required this.roles,
    required this.activeRole,
    this.branchAccess = const {},
    this.restaurantAccess = const {},
    this.activeBranchId,
    this.issuedAt,
    this.expiresAt,
    this.revoked = false,
  });

  final String actorId;
  final Set<StaffRole> roles;
  final StaffRole activeRole;

  /// **Phase 6B**: every branch id this actor is granted access to.
  /// Empty means "no branch access granted" — scope denial mirrors role
  /// denial: absence is a deny, never an implicit "every branch."
  final Set<String> branchAccess;

  /// Every restaurant id this actor is granted access to, same
  /// empty-means-none convention as [branchAccess].
  final Set<String> restaurantAccess;

  /// Which of [branchAccess] the actor is *currently operating in* —
  /// "branch switching," the same narrower/context-only relationship
  /// [activeRole] has to [roles]. `null` before a branch has been
  /// selected, or for a role (e.g. [StaffRole.courier] mid-delivery)
  /// that doesn't need one.
  final String? activeBranchId;

  /// When this session was created. `null` for sessions built without
  /// tracking issuance (e.g. most existing tests predating Phase 6B) —
  /// optional so no pre-existing `ActorSession(...)` call site anywhere
  /// in this codebase needed to change.
  final DateTime? issuedAt;

  /// When this session stops being valid. `null` means it never expires
  /// on its own (still subject to [revoked]).
  final DateTime? expiresAt;

  /// Set by [revoked]-aware [StaffAuthRepository] flows — "forced
  /// session revocation": an admin can invalidate a session before its
  /// natural [expiresAt], and the next session read reflects it (never a
  /// live push into an already-running client this codebase has no
  /// mechanism for).
  final bool revoked;

  /// `true` once [expiresAt] has passed. Always `false` when [expiresAt]
  /// is `null`.
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// `true` only when neither [revoked] nor [isExpired] — the single
  /// check every session-consuming call site should make before trusting
  /// a session at all, in addition to the role/permission checks
  /// [RealPosAuthorizationPolicy] already performs.
  bool get isValid => !revoked && !isExpired;

  /// Whether [branchId] is in [branchAccess] — "cross-branch access must
  /// require explicit authorization."
  bool hasBranchAccess(String branchId) => branchAccess.contains(branchId);

  /// Builds a session from raw, untyped role-name strings — the shape a
  /// future backend session payload would actually arrive in (this app
  /// has no such backend yet — see `docs/decisions.md` ADR-022). Unknown
  /// role names are silently dropped, never thrown. Returns `null` (no
  /// session — deny by default) when [actorId] is blank, when no
  /// recognized role remains, or when [activeRoleName] doesn't resolve to
  /// one of the actor's own [roles] — "malformed or missing role data
  /// denies safely" is satisfied structurally by this factory, not by
  /// caller discipline. **Phase 6B**: unrecognized branch/restaurant ids
  /// are kept as-is (they're opaque identifiers, not a closed enum like
  /// roles, so nothing to validate them against yet) — only
  /// `activeBranchId` is checked against the parsed [branchAccess],
  /// exactly mirroring how `activeRoleName` is checked against [roles].
  static ActorSession? tryFromRaw({
    required String actorId,
    required List<String> roleNames,
    String? activeRoleName,
    List<String> branchAccessIds = const [],
    List<String> restaurantAccessIds = const [],
    String? activeBranchId,
    DateTime? issuedAt,
    DateTime? expiresAt,
    bool revoked = false,
  }) {
    if (actorId.trim().isEmpty) return null;

    final roles = <StaffRole>{};
    for (final name in roleNames) {
      for (final role in StaffRole.values) {
        if (role.name == name) {
          roles.add(role);
          break;
        }
      }
    }
    if (roles.isEmpty) return null;

    StaffRole? active;
    if (activeRoleName != null) {
      for (final role in StaffRole.values) {
        if (role.name == activeRoleName) {
          active = role;
          break;
        }
      }
      if (active == null || !roles.contains(active)) return null;
    }
    active ??= roles.first;

    final branchAccess = branchAccessIds.toSet();
    if (activeBranchId != null && !branchAccess.contains(activeBranchId)) {
      return null;
    }

    return ActorSession(
      actorId: actorId,
      roles: roles,
      activeRole: active,
      branchAccess: branchAccess,
      restaurantAccess: restaurantAccessIds.toSet(),
      activeBranchId: activeBranchId,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      revoked: revoked,
    );
  }

  /// "Role switching" — returns a new session with [activeRole] changed.
  /// Throws [ArgumentError] if the actor doesn't actually hold [role]; an
  /// actor can only switch into a role they were granted, never invent
  /// one.
  ActorSession withActiveRole(StaffRole role) {
    if (!roles.contains(role)) {
      throw ArgumentError(
        'Cannot switch to role "$role" — actor "$actorId" does not hold it',
      );
    }
    return _copyWith(activeRole: role);
  }

  /// "Branch switching" — returns a new session with [activeBranchId]
  /// changed. Throws [ArgumentError] if [branchId] isn't in
  /// [branchAccess]; an actor can only switch into a branch they were
  /// granted, never invent one.
  ActorSession withActiveBranch(String branchId) {
    if (!branchAccess.contains(branchId)) {
      throw ArgumentError(
        'Cannot switch to branch "$branchId" — actor "$actorId" does not '
        'have access to it',
      );
    }
    return _copyWith(activeBranchId: branchId);
  }

  ActorSession _copyWith({StaffRole? activeRole, String? activeBranchId}) {
    return ActorSession(
      actorId: actorId,
      roles: roles,
      activeRole: activeRole ?? this.activeRole,
      branchAccess: branchAccess,
      restaurantAccess: restaurantAccess,
      activeBranchId: activeBranchId ?? this.activeBranchId,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      revoked: revoked,
    );
  }
}
