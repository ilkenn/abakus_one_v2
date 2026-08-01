import 'actor_session.dart';
import 'authorization_result.dart';
import 'pos_authorization_policy.dart';
import 'pos_authorized_action.dart';
import 'role_permission_map.dart';
import 'staff_role.dart';

/// The context key a caller passing a branch-scoped action's target
/// branch id must use — see [RealPosAuthorizationPolicy]'s branch-scope
/// check (Phase 6P, `docs/decisions.md` ADR-023).
const String kBranchIdAuthorizationContextKey = 'branchId';

/// The first real, production-capable [PosAuthorizationPolicy]
/// implementation in this codebase — Sprint 5E, resolving the Phase 5
/// phase-gate blocker recorded in `docs/decisions.md` ADR-012/ADR-022.
///
/// **Deny by default, never allow-all**: with no active session, an
/// unrecognized actor, a revoked or expired session, a role lacking the
/// requested permission, or (Phase 6P) a target branch the actor has no
/// granted access to, this always denies — there is no code path in
/// this class that grants an action without a real, matching, valid
/// [ActorSession] whose roles actually cover it
/// (`RolePermissionMap.allows`). **Phase 6B** (`docs/decisions.md`
/// ADR-023) added the [ActorSession.revoked]/[ActorSession.isExpired]
/// checks — "forced session revocation" and "expired session denies" are
/// now enforced here, not left to callers.
///
/// [PosAuthorizationPolicy.authorize]'s existing signature (bare
/// `actorStaffId: String`) is deliberately unchanged — this class cross-
/// checks the caller-supplied `actorStaffId` against the real session's
/// own `actorId` (a mismatch is treated as "unknown actor," denied)
/// rather than trusting it blindly, without requiring every one of the
/// 100+ existing call sites to be migrated onto a new interface.
///
/// **Phase 6P branch scoping**: when the caller-supplied `context`
/// carries [kBranchIdAuthorizationContextKey], the actor must hold that
/// branch in [ActorSession.branchAccess] — "cross-branch access must
/// require explicit authorization" (`docs/decisions.md` ADR-023's Phase
/// 6D organization/tenant boundary). [StaffRole.admin] is exempt (an
/// org-wide oversight role by design, matching 6F's own "Admin:
/// permitted scope, Manager: branch scope" tiering) — every other role
/// is denied for a branch it wasn't explicitly granted, even if its
/// role otherwise permits the action. Callers that omit the context key
/// entirely (every non-branch-scoped action, and every call site that
/// pre-dates this check) are unaffected — this is additive, not a
/// blanket new requirement.
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
    if (session.revoked) {
      return const AuthorizationResult(
        granted: false,
        reason: 'Session revoked',
      );
    }
    if (session.isExpired) {
      return const AuthorizationResult(
        granted: false,
        reason: 'Session expired',
      );
    }
    if (!RolePermissionMap.allows(session.roles, action)) {
      return AuthorizationResult(
        granted: false,
        reason: 'None of this actor\'s roles permit "${action.name}"',
      );
    }
    final targetBranchId = context[kBranchIdAuthorizationContextKey];
    if (targetBranchId != null &&
        !session.roles.contains(StaffRole.admin) &&
        !session.hasBranchAccess(targetBranchId)) {
      return AuthorizationResult(
        granted: false,
        reason: 'Actor does not have access to branch "$targetBranchId"',
      );
    }
    return const AuthorizationResult(granted: true);
  }
}
