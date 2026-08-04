import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/authorization/platform_actor_session.dart';
import '../../domain/authorization/platform_authorization_policy.dart';
import '../../domain/authorization/real_platform_authorization_policy.dart';

/// The currently active [PlatformActorSession] — Phase 8
/// (`docs/decisions.md` ADR-025). Mirrors `actorSessionProvider`'s
/// deny-by-default shape exactly: defaults to `null` (no active
/// platform actor), and every authorization check denies until a real
/// sign-in populates this.
final platformActorSessionProvider =
    StateProvider<PlatformActorSession?>((ref) => null);

/// The app's real [PlatformAuthorizationPolicy] — reads
/// [platformActorSessionProvider] on every check, so a sign-out or role
/// switch takes effect on the very next authorization call.
final platformAuthorizationPolicyProvider =
    Provider<PlatformAuthorizationPolicy>((ref) {
  return RealPlatformAuthorizationPolicy(
    currentSession: () => ref.read(platformActorSessionProvider),
  );
});
