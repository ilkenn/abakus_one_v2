import 'platform_actor_session.dart';
import 'platform_authorization_policy.dart';
import 'platform_authorization_result.dart';
import 'platform_authorized_action.dart';
import 'platform_role_permission_map.dart';

/// The first real, production-capable [PlatformAuthorizationPolicy]
/// implementation — Phase 8 (`docs/decisions.md` ADR-025).
///
/// **Deny by default, never allow-all**: with no active session, an
/// unrecognized actor, a revoked or expired session, or a role lacking
/// the requested permission, this always denies — mirrors
/// `RealPosAuthorizationPolicy`'s exact deny-by-default shape, applied
/// to the wholly separate platform stack.
class RealPlatformAuthorizationPolicy implements PlatformAuthorizationPolicy {
  const RealPlatformAuthorizationPolicy({
    required PlatformActorSession? Function() currentSession,
  }) : _currentSession = currentSession;

  final PlatformActorSession? Function() _currentSession;

  @override
  Future<PlatformAuthorizationResult> authorize({
    required PlatformAuthorizedAction action,
    required String actorId,
  }) async {
    final session = _currentSession();
    if (session == null) {
      return const PlatformAuthorizationResult(
        granted: false,
        reason: 'No active platform session',
      );
    }
    if (session.actorId != actorId) {
      return const PlatformAuthorizationResult(
        granted: false,
        reason: 'Unknown actor',
      );
    }
    if (session.revoked) {
      return const PlatformAuthorizationResult(
        granted: false,
        reason: 'Session revoked',
      );
    }
    if (session.isExpired) {
      return const PlatformAuthorizationResult(
        granted: false,
        reason: 'Session expired',
      );
    }
    if (!PlatformRolePermissionMap.allows(session.roles, action)) {
      return PlatformAuthorizationResult(
        granted: false,
        reason: 'None of this actor\'s platform roles permit "${action.name}"',
      );
    }
    return const PlatformAuthorizationResult(granted: true);
  }
}
