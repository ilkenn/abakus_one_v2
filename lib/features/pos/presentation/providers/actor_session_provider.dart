import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/authorization/actor_session.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/real_pos_authorization_policy.dart';

/// The currently active [ActorSession] — Sprint 5E. **Defaults to `null`
/// (no active actor)**, the same honest-by-default pattern every other
/// service seam in this codebase uses (`NoOpLoggingService`,
/// `UnavailableExchangeRateProvider`) — except here the safe default is
/// "deny everything," not merely "unavailable," because an auto-granting
/// default would be unsafe (`docs/decisions.md` ADR-012/ADR-022).
///
/// Populating this from a real staff/manager/admin/courier login is
/// **future, backend-gated work this sprint does not build** — this app
/// has no staff-side authentication of any kind yet (only customer
/// phone+OTP, `features/auth`). Until that exists, setting a session here
/// is a manual/test/demo action only, e.g.
/// `ref.read(actorSessionProvider.notifier).state = someSession`. Every
/// screen that depends on authorization continues to deny by default
/// until that's done explicitly — never implicitly, never on screen
/// visibility alone.
final actorSessionProvider = StateProvider<ActorSession?>((ref) => null);

/// The app's real [PosAuthorizationPolicy] — the first production-capable
/// implementation this codebase has had (`RealPosAuthorizationPolicy`).
/// Reads [actorSessionProvider] on every check, so a role switch or
/// sign-out takes effect on the very next authorization call, with no
/// stale cached grant.
final posAuthorizationPolicyProvider = Provider<PosAuthorizationPolicy>((ref) {
  return RealPosAuthorizationPolicy(
    currentSession: () => ref.read(actorSessionProvider),
  );
});
