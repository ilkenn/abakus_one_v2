import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/platform_auth_repository.dart';
import '../../domain/authorization/platform_role.dart';
import 'platform_actor_session_provider.dart';
import 'platform_dependencies_provider.dart';

/// The one place `platformActorSessionProvider`'s state is ever written
/// — mirrors `StaffSessionController` exactly. Phase 8
/// (`docs/decisions.md` ADR-025).
class PlatformSessionController {
  PlatformSessionController(this._ref, this._authRepository);

  final Ref _ref;
  final PlatformAuthRepository _authRepository;

  Future<bool> signIn(String platformMemberId) async {
    final session =
        await _authRepository.signIn(platformMemberId: platformMemberId);
    _ref.read(platformActorSessionProvider.notifier).state = session;
    return session != null;
  }

  Future<void> signOut() async {
    await _authRepository.signOut();
    _ref.read(platformActorSessionProvider.notifier).state = null;
  }

  Future<void> refresh() async {
    final current = _ref.read(platformActorSessionProvider);
    if (current == null) return;
    final refreshed = await _authRepository.refreshSession(current);
    _ref.read(platformActorSessionProvider.notifier).state = refreshed;
  }

  void switchRole(PlatformRole role) {
    final current = _ref.read(platformActorSessionProvider);
    if (current == null) return;
    _ref.read(platformActorSessionProvider.notifier).state =
        current.withActiveRole(role);
  }
}

final platformSessionControllerProvider =
    Provider<PlatformSessionController>((ref) {
  return PlatformSessionController(
      ref, ref.watch(platformAuthRepositoryProvider));
});
