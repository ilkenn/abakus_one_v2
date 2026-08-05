import '../../../core/services/auth/email_password_auth_client.dart';
import '../../pos/domain/authorization/actor_session.dart';
import '../domain/staff/staff_member.dart';
import '../domain/staff/staff_member_status.dart';
import 'staff_member_repository.dart';

/// Everything the app needs to issue/refresh/end a staff [ActorSession] —
/// mirrors `AuthRepository`'s exact seam shape (`features/auth`) so a
/// future real backend is a single new implementation plus a single
/// provider override. Phase 6B (`docs/decisions.md` ADR-023).
///
/// As of Sprint 9C (`docs/decisions.md` ADR-026), [signIn] takes a real
/// email/password credential — not a bare [StaffMember] id — closing the
/// "no-credential member picker" gap. Two implementations remain:
/// `FirebaseStaffAuthRepository` (real, gated by `firebaseReadyProvider` —
/// see `staffAuthRepositoryProvider`) and
/// [ProductionUnavailableStaffAuthRepository] (fails closed whenever
/// Firebase isn't ready). [DevelopmentStaffAuthRepository] remains only as
/// a test fixture (see its own doc comment).
abstract interface class StaffAuthRepository {
  /// Issues a new session for the account identified by [email]/[password],
  /// or `null` if the credential is invalid, no [StaffMember] is linked to
  /// it, or the linked member isn't [StaffMemberStatus.active] — "suspended
  /// actor cannot create a valid operational session." Deliberately never
  /// distinguishes these failure reasons to the caller (avoids leaking
  /// which email addresses have an account at all).
  Future<ActorSession?> signIn({
    required String email,
    required String password,
  });

  /// Re-reads the underlying [StaffMember] record fresh and rebuilds
  /// [current] from it, or returns `null` if it's no longer valid —
  /// "removed role takes effect immediately after session refresh" and
  /// the forced-revocation contract (a session issued before
  /// [StaffMember.sessionsRevokedAt] is treated as invalid) are both
  /// enforced here, not left to the caller.
  Future<ActorSession?> refreshSession(ActorSession current);

  Future<void> signOut();
}

/// Selected whenever Firebase isn't ready — fails closed on every
/// operation, exactly like `ProductionUnavailableAuthRepository`. "Do not
/// claim production backend validation if none exists."
class ProductionUnavailableStaffAuthRepository implements StaffAuthRepository {
  const ProductionUnavailableStaffAuthRepository();

  @override
  Future<ActorSession?> signIn({
    required String email,
    required String password,
  }) async =>
      null;

  @override
  Future<ActorSession?> refreshSession(ActorSession current) async => null;

  @override
  Future<void> signOut() async {}
}

/// Test-fixture-only stand-in (Sprint 9C — no longer wired into any
/// production provider; see `FirebaseStaffAuthRepository`). [email] is
/// treated as a bare [StaffMember.id] lookup key and [password] is
/// entirely ignored — there is no real credential check behind this
/// class, matching its pre-9C character exactly, just adapted to the
/// current [StaffAuthRepository] interface shape so existing tests keep
/// working without a real Firebase Auth Emulator.
class DevelopmentStaffAuthRepository implements StaffAuthRepository {
  DevelopmentStaffAuthRepository({
    required StaffMemberRepository staffMemberRepository,
    required Duration Function() sessionDuration,
  })  : _staffMemberRepository = staffMemberRepository,
        _sessionDuration = sessionDuration;

  final StaffMemberRepository _staffMemberRepository;
  final Duration Function() _sessionDuration;

  @override
  Future<ActorSession?> signIn({
    required String email,
    required String password,
  }) async {
    final member = await _staffMemberRepository.findById(email);
    if (member == null || !member.isActive || member.roles.isEmpty) {
      return null;
    }
    final now = DateTime.now();
    return ActorSession(
      actorId: member.id,
      roles: member.roles,
      activeRole: member.roles.first,
      branchAccess: member.branchAccess,
      restaurantAccess: member.restaurantAccess,
      organizationAccess: member.organizationAccess,
      issuedAt: now,
      expiresAt: now.add(_sessionDuration()),
    );
  }

  @override
  Future<ActorSession?> refreshSession(ActorSession current) async {
    final member = await _staffMemberRepository.findById(current.actorId);
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
    final activeBranchId = current.activeBranchId != null &&
            member.branchAccess.contains(current.activeBranchId)
        ? current.activeBranchId
        : null;
    return ActorSession(
      actorId: member.id,
      roles: member.roles,
      activeRole: activeRole,
      branchAccess: member.branchAccess,
      restaurantAccess: member.restaurantAccess,
      organizationAccess: member.organizationAccess,
      activeBranchId: activeBranchId,
      issuedAt: current.issuedAt,
      expiresAt: current.expiresAt,
    );
  }

  @override
  Future<void> signOut() async {
    // No persisted session to clear yet (`actorSessionProvider` is the
    // sole, in-memory source of truth) — the caller
    // (`StaffSessionController`) clears that provider directly.
  }
}

/// The real, Firebase-Auth-backed [StaffAuthRepository] — Sprint 9C
/// (`docs/decisions.md` ADR-026). [signIn] authenticates against real
/// Firebase Auth (the local Auth Emulator in `AppEnvironment.development`,
/// the real project in staging/production — decided once at bootstrap,
/// exactly like `FirebaseAuthRepository` for customers), then requires an
/// **exact [StaffMember.authUid] match** before issuing a session — a
/// valid Firebase credential alone is not enough; the signed-in account
/// must also be linked to an active staff record, closing the
/// "no-credential member picker" gap without ever enumerating the roster
/// to the caller.
class FirebaseStaffAuthRepository implements StaffAuthRepository {
  FirebaseStaffAuthRepository({
    required EmailPasswordAuthClient authClient,
    required StaffMemberRepository staffMemberRepository,
    required Duration Function() sessionDuration,
  })  : _authClient = authClient,
        _staffMemberRepository = staffMemberRepository,
        _sessionDuration = sessionDuration;

  final EmailPasswordAuthClient _authClient;
  final StaffMemberRepository _staffMemberRepository;
  final Duration Function() _sessionDuration;

  @override
  Future<ActorSession?> signIn({
    required String email,
    required String password,
  }) async {
    final EmailPasswordAuthResult result;
    try {
      result = await _authClient.signIn(email: email, password: password);
    } on EmailPasswordAuthClientException {
      return null;
    }

    final member = await _staffMemberRepository.findByAuthUid(result.uid);
    if (member == null || !member.isActive || member.roles.isEmpty) {
      return null;
    }
    final now = DateTime.now();
    return ActorSession(
      actorId: member.id,
      roles: member.roles,
      activeRole: member.roles.first,
      branchAccess: member.branchAccess,
      restaurantAccess: member.restaurantAccess,
      organizationAccess: member.organizationAccess,
      issuedAt: now,
      expiresAt: now.add(_sessionDuration()),
    );
  }

  @override
  Future<ActorSession?> refreshSession(ActorSession current) async {
    final member = await _staffMemberRepository.findById(current.actorId);
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
    final activeBranchId = current.activeBranchId != null &&
            member.branchAccess.contains(current.activeBranchId)
        ? current.activeBranchId
        : null;
    return ActorSession(
      actorId: member.id,
      roles: member.roles,
      activeRole: activeRole,
      branchAccess: member.branchAccess,
      restaurantAccess: member.restaurantAccess,
      organizationAccess: member.organizationAccess,
      activeBranchId: activeBranchId,
      issuedAt: current.issuedAt,
      expiresAt: current.expiresAt,
    );
  }

  @override
  Future<void> signOut() => _authClient.signOut();
}
