import '../domain/authorization/platform_actor_session.dart';
import 'platform_member_repository.dart';

/// Everything the app needs to issue/refresh/end a [PlatformActorSession]
/// — Phase 8 (`docs/decisions.md` ADR-025), mirrors `StaffAuthRepository`'s
/// exact seam shape so a future real backend is a single new
/// implementation plus a single provider override.
///
/// Two implementations: [DevelopmentPlatformAuthRepository] (debug/
/// profile builds — picks a known, seeded [PlatformMember] with **no
/// password/credential of any kind**, an explicitly-labeled simulated
/// stand-in) and [ProductionUnavailablePlatformAuthRepository] (release
/// builds — fails closed).
abstract interface class PlatformAuthRepository {
  Future<PlatformActorSession?> signIn({required String platformMemberId});
  Future<PlatformActorSession?> refreshSession(PlatformActorSession current);
  Future<void> signOut();
}

/// Selected in release builds until a real backend-backed
/// [PlatformAuthRepository] exists — fails closed on every operation,
/// exactly like `ProductionUnavailableStaffAuthRepository`. "Release
/// builds must never expose this path" (the Phase 8 kickoff's own
/// requirement for Development Login) is satisfied structurally here,
/// not merely by convention — see `platformAuthRepositoryProvider` for
/// the `kReleaseMode` switch that selects this class.
class ProductionUnavailablePlatformAuthRepository
    implements PlatformAuthRepository {
  const ProductionUnavailablePlatformAuthRepository();

  @override
  Future<PlatformActorSession?> signIn({
    required String platformMemberId,
  }) async =>
      null;

  @override
  Future<PlatformActorSession?> refreshSession(
    PlatformActorSession current,
  ) async =>
      null;

  @override
  Future<void> signOut() async {}
}

/// Debug/profile-only stand-in — "sign in" by selecting a known,
/// already-registered [PlatformMember] id, with no password/PIN/
/// credential prompt of any kind. Mirrors
/// `DevelopmentStaffAuthRepository`'s exact reasoning: a picker over
/// already-trusted, bootstrapped records is honestly what it is (a
/// development convenience), never a fake credential check that would
/// look like real authentication but isn't. "Development login exists
/// solely until real OTP authentication becomes available."
class DevelopmentPlatformAuthRepository implements PlatformAuthRepository {
  DevelopmentPlatformAuthRepository({
    required PlatformMemberRepository platformMemberRepository,
    required Duration Function() sessionDuration,
  })  : _platformMemberRepository = platformMemberRepository,
        _sessionDuration = sessionDuration;

  final PlatformMemberRepository _platformMemberRepository;
  final Duration Function() _sessionDuration;

  @override
  Future<PlatformActorSession?> signIn({
    required String platformMemberId,
  }) async {
    final member = await _platformMemberRepository.findById(platformMemberId);
    if (member == null || !member.isActive || member.roles.isEmpty) {
      return null;
    }
    final now = DateTime.now();
    return PlatformActorSession(
      actorId: member.id,
      roles: member.roles,
      activeRole: member.roles.first,
      issuedAt: now,
      expiresAt: now.add(_sessionDuration()),
    );
  }

  @override
  Future<PlatformActorSession?> refreshSession(
    PlatformActorSession current,
  ) async {
    final member = await _platformMemberRepository.findById(current.actorId);
    if (member == null || !member.isActive || member.roles.isEmpty) {
      return null;
    }
    final revokedAt = member.sessionsRevokedAt;
    if (revokedAt != null &&
        current.issuedAt != null &&
        current.issuedAt!.isBefore(revokedAt)) {
      return null;
    }
    final activeRole = member.roles.contains(current.activeRole)
        ? current.activeRole
        : member.roles.first;
    return PlatformActorSession(
      actorId: member.id,
      roles: member.roles,
      activeRole: activeRole,
      issuedAt: current.issuedAt,
      expiresAt: current.expiresAt,
    );
  }

  @override
  Future<void> signOut() async {
    // No persisted session to clear yet (`platformActorSessionProvider`
    // is the sole, in-memory source of truth) — the caller
    // (`PlatformSessionController`) clears that provider directly.
  }
}
