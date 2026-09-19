import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../pos/domain/authorization/actor_session.dart';
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

  /// **Debug-only escape hatch — PC Yönetici İnceleme Modu, 2026-09-20.**
  /// Injects [session] directly, bypassing [StaffAuthRepository] entirely
  /// (no real credential check, no real claims derivation). Added
  /// specifically for Windows desktop's "Dev Admin ile Gir" shortcut,
  /// where `firebase_auth`'s Windows C++ SDK has been reported unable to
  /// complete a forced token refresh against the Auth Emulator. Kept as a
  /// method on this controller (never a raw `actorSessionProvider` write
  /// from a screen) so "the one place session state is ever written"
  /// stays true even for this shortcut — but it is still fundamentally a
  /// bypass: `firestore.rules`'s `hasRole`/`hasBranchAccess` evaluate the
  /// REAL signed-in user's ID token custom claims, never this fabricated
  /// local state, so a role/branch-gated Firestore read can still be
  /// denied after this call succeeds. Asserts in debug mode if ever
  /// reached in a release build — this must never ship reachable.
  void debugForceSession(ActorSession session) {
    assert(kDebugMode, 'debugForceSession must never be called outside kDebugMode.');
    _ref.read(actorSessionProvider.notifier).state = session;
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
