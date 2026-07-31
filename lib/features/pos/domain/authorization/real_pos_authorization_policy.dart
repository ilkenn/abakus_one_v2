import 'actor_session.dart';
import 'authorization_result.dart';
import 'pos_authorization_policy.dart';
import 'pos_authorized_action.dart';
import 'role_permission_map.dart';

/// The first real, production-capable [PosAuthorizationPolicy]
/// implementation in this codebase — Sprint 5E, resolving the Phase 5
/// phase-gate blocker recorded in `docs/decisions.md` ADR-012/ADR-022.
///
/// **Deny by default, never allow-all**: with no active session, an
/// unrecognized actor, or a role lacking the requested permission, this
/// always denies — there is no code path in this class that grants an
/// action without a real, matching [ActorSession] whose roles actually
/// cover it (`RolePermissionMap.allows`). It is **not** wired as this
/// app's default `posAuthorizationPolicyProvider` override this sprint —
/// see `actor_session_provider.dart`'s own doc comment for why a real
/// policy still starts every session with no active actor, i.e. denying
/// everything, until a future login flow populates one.
///
/// [PosAuthorizationPolicy.authorize]'s existing signature (bare
/// `actorStaffId: String`) is deliberately unchanged — this class cross-
/// checks the caller-supplied `actorStaffId` against the real session's
/// own `actorId` (a mismatch is treated as "unknown actor," denied)
/// rather than trusting it blindly, without requiring every one of the
/// 100+ existing call sites to be migrated onto a new interface.
class RealPosAuthorizationPolicy implements PosAuthorizationPolicy {
  const RealPosAuthorizationPolicy({
    required ActorSession? Function() currentSession,
  }) : _currentSession = currentSession;

  final ActorSession? Function() _currentSession;

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async {
    final session = _currentSession();
    if (session == null) {
      return const AuthorizationResult(
        granted: false,
        reason: 'No active session',
      );
    }
    if (session.actorId != actorStaffId) {
      return const AuthorizationResult(
        granted: false,
        reason: 'Unknown actor',
      );
    }
    if (!RolePermissionMap.allows(session.roles, action)) {
      return AuthorizationResult(
        granted: false,
        reason: 'None of this actor\'s roles permit "${action.name}"',
      );
    }
    return const AuthorizationResult(granted: true);
  }
}
