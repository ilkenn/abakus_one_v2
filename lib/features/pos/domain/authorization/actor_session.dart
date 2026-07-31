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
  });

  final String actorId;
  final Set<StaffRole> roles;
  final StaffRole activeRole;

  /// Builds a session from raw, untyped role-name strings — the shape a
  /// future backend session payload would actually arrive in (this app
  /// has no such backend yet — see `docs/decisions.md` ADR-022). Unknown
  /// role names are silently dropped, never thrown. Returns `null` (no
  /// session — deny by default) when [actorId] is blank, when no
  /// recognized role remains, or when [activeRoleName] doesn't resolve to
  /// one of the actor's own [roles] — "malformed or missing role data
  /// denies safely" is satisfied structurally by this factory, not by
  /// caller discipline.
  static ActorSession? tryFromRaw({
    required String actorId,
    required List<String> roleNames,
    String? activeRoleName,
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

    return ActorSession(actorId: actorId, roles: roles, activeRole: active);
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
    return ActorSession(actorId: actorId, roles: roles, activeRole: role);
  }
}
