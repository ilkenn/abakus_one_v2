import 'platform_role.dart';

/// The currently active authenticated platform-level actor — Phase 8
/// (`docs/decisions.md` ADR-025). Mirrors `ActorSession`'s shape
/// deliberately (issuance/expiry/revocation, a role set plus an active
/// role) so the same mental model applies, but is a wholly separate
/// type with **no branch, restaurant, or organization access field of
/// any kind** — a platform actor is global by construction, not merely
/// "granted access to everything." There is structurally nothing here
/// to scope, unlike `ActorSession.branchAccess`/`restaurantAccess`/
/// `organizationAccess`.
class PlatformActorSession {
  const PlatformActorSession({
    required this.actorId,
    required this.roles,
    required this.activeRole,
    this.issuedAt,
    this.expiresAt,
    this.revoked = false,
  });

  final String actorId;
  final Set<PlatformRole> roles;
  final PlatformRole activeRole;
  final DateTime? issuedAt;
  final DateTime? expiresAt;
  final bool revoked;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isValid => !revoked && !isExpired;

  /// Builds a session from raw, untyped role-name strings — mirrors
  /// `ActorSession.tryFromRaw`'s "malformed or missing role data denies
  /// safely" contract exactly, for the same reason.
  static PlatformActorSession? tryFromRaw({
    required String actorId,
    required List<String> roleNames,
    String? activeRoleName,
    DateTime? issuedAt,
    DateTime? expiresAt,
    bool revoked = false,
  }) {
    if (actorId.trim().isEmpty) return null;

    final roles = <PlatformRole>{};
    for (final name in roleNames) {
      for (final role in PlatformRole.values) {
        if (role.name == name) {
          roles.add(role);
          break;
        }
      }
    }
    if (roles.isEmpty) return null;

    PlatformRole? active;
    if (activeRoleName != null) {
      for (final role in PlatformRole.values) {
        if (role.name == activeRoleName) {
          active = role;
          break;
        }
      }
      if (active == null || !roles.contains(active)) return null;
    }
    active ??= roles.first;

    return PlatformActorSession(
      actorId: actorId,
      roles: roles,
      activeRole: active,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      revoked: revoked,
    );
  }

  /// "Role switching" — mirrors `ActorSession.withActiveRole`.
  PlatformActorSession withActiveRole(PlatformRole role) {
    if (!roles.contains(role)) {
      throw ArgumentError(
        'Cannot switch to role "$role" — actor "$actorId" does not hold it',
      );
    }
    return PlatformActorSession(
      actorId: actorId,
      roles: roles,
      activeRole: role,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      revoked: revoked,
    );
  }
}
