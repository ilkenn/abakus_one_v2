import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../pos/domain/authorization/staff_role.dart';
import '../../../pos/presentation/providers/actor_session_provider.dart';
import '../../data/staff_auth_repository.dart';
import 'admin_dependencies_provider.dart';

/// The one place `actorSessionProvider`'s state is ever written — every
/// screen-facing sign-in/out/switch action goes through here rather than
/// setting `actorSessionProvider.notifier.state` directly, so the
/// `StaffAuthRepository` seam (validity/expiration/revocation checks) is
/// never bypassed. Phase 6B (`docs/decisions.md` ADR-023).
class StaffSessionController {
  StaffSessionController(this._ref, this._authRepository);

  final Ref _ref;
  final StaffAuthRepository _authRepository;

  /// Returns `true` on success. `false` (session left unchanged, still
  /// `null`) if the credential is invalid or doesn't resolve to an active
  /// member with at least one role — "deny by default" extends to
  /// sign-in itself.
  Future<bool> signIn({required String email, required String password}) async {
    final session =
        await _authRepository.signIn(email: email, password: password);
    _ref.read(actorSessionProvider.notifier).state = session;
    return session != null;
  }

  Future<void> signOut() async {
    await _authRepository.signOut();
    _ref.read(actorSessionProvider.notifier).state = null;
  }

  /// Re-validates the current session against its underlying
  /// `StaffMember` record — "removed role takes effect immediately after
  /// session refresh." If the member is now suspended/archived, or the
  /// session was issued before a forced revocation, the session becomes
  /// `null` (the actor is signed out).
  Future<void> refresh() async {
    final current = _ref.read(actorSessionProvider);
    if (current == null) return;
    final refreshed = await _authRepository.refreshSession(current);
    _ref.read(actorSessionProvider.notifier).state = refreshed;
  }

  /// "Role switching." No-ops if there's no active session; throws
  /// (via `ActorSession.withActiveRole`) if the actor doesn't hold
  /// [role].
  void switchRole(StaffRole role) {
    final current = _ref.read(actorSessionProvider);
    if (current == null) return;
    _ref.read(actorSessionProvider.notifier).state =
        current.withActiveRole(role);
  }

  /// "Branch switching." No-ops if there's no active session; throws
  /// (via `ActorSession.withActiveBranch`) if the actor doesn't have
  /// access to [branchId].
  void switchBranch(String branchId) {
    final current = _ref.read(actorSessionProvider);
    if (current == null) return;
    _ref.read(actorSessionProvider.notifier).state =
        current.withActiveBranch(branchId);
  }
}

final staffSessionControllerProvider = Provider<StaffSessionController>((ref) {
  return StaffSessionController(ref, ref.watch(staffAuthRepositoryProvider));
});
