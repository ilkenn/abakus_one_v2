import '../../../core/services/auth/email_password_auth_client.dart';
import '../domain/authorization/platform_actor_session.dart';
import 'platform_member_repository.dart';

/// Everything the app needs to issue/refresh/end a [PlatformActorSession]
/// — Phase 8 (`docs/decisions.md` ADR-025), mirrors `StaffAuthRepository`'s
/// exact seam shape so a future real backend is a single new
/// implementation plus a single provider override.
///
/// As of Sprint 9C (`docs/decisions.md` ADR-026), [signIn] takes a real
/// email/password credential — not a bare [PlatformMember] id — closing
/// the "no-credential member picker" gap. Two implementations remain:
/// `FirebasePlatformAuthRepository` (real, gated by `firebaseReadyProvider`
/// — see `platformAuthRepositoryProvider`) and
/// [ProductionUnavailablePlatformAuthRepository] (fails closed whenever
/// Firebase isn't ready). [DevelopmentPlatformAuthRepository] remains only
/// as a test fixture (see its own doc comment).
abstract interface class PlatformAuthRepository {
  Future<PlatformActorSession?> signIn({
    required String email,
    required String password,
  });
  Future<PlatformActorSession?> refreshSession(PlatformActorSession current);
  Future<void> signOut();
}

/// Selected whenever Firebase isn't ready — fails closed on every
/// operation, exactly like `ProductionUnavailableStaffAuthRepository`.
class ProductionUnavailablePlatformAuthRepository
    implements PlatformAuthRepository {
  const ProductionUnavailablePlatformAuthRepository();

  @override
  Future<PlatformActorSession?> signIn({
    required String email,
    required String password,
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

/// Test-fixture-only stand-in (Sprint 9C — no longer wired into any
/// production provider; see `FirebasePlatformAuthRepository`). [email] is
/// treated as a bare [PlatformMember.id] lookup key and [password] is
/// entirely ignored — mirrors `DevelopmentStaffAuthRepository`'s exact
/// reasoning.
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
    required String email,
    required String password,
  }) async {
    final member = await _platformMemberRepository.findById(email);
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

/// The real, Firebase-Auth-backed [PlatformAuthRepository] — Sprint 9C
/// (`docs/decisions.md` ADR-026). Mirrors `FirebaseStaffAuthRepository`
/// exactly, one tier up: requires an exact [PlatformMember.authUid] match
/// before issuing a session — a valid Firebase credential alone is not
/// enough.
class FirebasePlatformAuthRepository implements PlatformAuthRepository {
  FirebasePlatformAuthRepository({
    required EmailPasswordAuthClient authClient,
    required PlatformMemberRepository platformMemberRepository,
    required Duration Function() sessionDuration,
  })  : _authClient = authClient,
        _platformMemberRepository = platformMemberRepository,
        _sessionDuration = sessionDuration;

  final EmailPasswordAuthClient _authClient;
  final PlatformMemberRepository _platformMemberRepository;
  final Duration Function() _sessionDuration;

  @override
  Future<PlatformActorSession?> signIn({
    required String email,
    required String password,
  }) async {
    final EmailPasswordAuthResult result;
    try {
      result = await _authClient.signIn(email: email, password: password);
    } on EmailPasswordAuthClientException {
      return null;
    }

    final member = await _platformMemberRepository.findByAuthUid(result.uid);
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
  Future<void> signOut() => _authClient.signOut();
}
