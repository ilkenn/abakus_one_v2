import 'platform_authorization_result.dart';
import 'platform_authorized_action.dart';

/// Gates every platform-level action — Phase 8 (`docs/decisions.md`
/// ADR-025). Mirrors `PosAuthorizationPolicy`'s own doc-commented
/// contract: **no auto-granting default implementation exists** — the
/// same reasoning `PosAuthorizationPolicy` gave for refusing a
/// `NoOp`-style "grant everything" stand-in applies with even higher
/// stakes here, since a platform actor can act across every tenant.
abstract interface class PlatformAuthorizationPolicy {
  Future<PlatformAuthorizationResult> authorize({
    required PlatformAuthorizedAction action,
    required String actorId,
  });
}
