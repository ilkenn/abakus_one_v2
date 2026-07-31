import '../../pos/domain/authorization/actor_session.dart';
import '../domain/staff/staff_member.dart';
import '../domain/staff/staff_member_status.dart';
import 'staff_member_repository.dart';

/// Everything the app needs to issue/refresh/end a staff [ActorSession] —
/// mirrors `AuthRepository`'s exact seam shape (`features/auth`) so a
/// future real backend is a single new implementation plus a single
/// provider override. Phase 6B (`docs/decisions.md` ADR-023).
///
/// Two implementations: [DevelopmentStaffAuthRepository] (debug/profile —
/// picks a known, seeded [StaffMember] with **no password/credential of
/// any kind**, an explicitly-labeled simulated stand-in, never a real
/// authentication mechanism) and [ProductionUnavailableStaffAuthRepository]
/// (release builds — fails closed, exactly like
/// `ProductionUnavailableAuthRepository`).
abstract interface class StaffAuthRepository {
  /// Issues a new session for [staffMemberId], or `null` if the member
  /// doesn't exist or isn't [StaffMemberStatus.active] — "suspended actor
  /// cannot create a valid operational session."
  Future<ActorSession?> signIn({required String staffMemberId});

  /// Re-reads the underlying [StaffMember] record fresh and rebuilds
  /// [current] from it, or returns `null` if it's no longer valid —
  /// "removed role takes effect immediately after session refresh" and
  /// the forced-revocation contract (a session issued before
  /// [StaffMember.sessionsRevokedAt] is treated as invalid) are both
  /// enforced here, not left to the caller.
  Future<ActorSession?> refreshSession(ActorSession current);

  Future<void> signOut();
}

/// Selected in release builds until a real backend-backed
/// [StaffAuthRepository] exists — fails closed on every operation,
/// exactly like `ProductionUnavailableAuthRepository`. "Do not claim
/// production backend validation if none exists."
class ProductionUnavailableStaffAuthRepository implements StaffAuthRepository {
  const ProductionUnavailableStaffAuthRepository();

  @override
  Future<ActorSession?> signIn({required String staffMemberId}) async => null;

  @override
  Future<ActorSession?> refreshSession(ActorSession current) async => null;

  @override
  Future<void> signOut() async {}
}

/// Debug/profile-only stand-in — "sign in" by selecting a known,
/// already-registered [StaffMember] id, with no password/PIN/credential
/// prompt of any kind. This is a deliberate choice, not a shortcut: the
/// brief explicitly forbids "an insecure local password system," and a
/// picker over already-trusted, admin-seeded records is honestly what it
/// is (a development convenience) rather than a fake credential check
/// that would look like real authentication but isn't.
class DevelopmentStaffAuthRepository implements StaffAuthRepository {
  DevelopmentStaffAuthRepository({
    required StaffMemberRepository staffMemberRepository,
    required Duration Function() sessionDuration,
  })  : _staffMemberRepository = staffMemberRepository,
        _sessionDuration = sessionDuration;

  final StaffMemberRepository _staffMemberRepository;
  final Duration Function() _sessionDuration;

  @override
  Future<ActorSession?> signIn({required String staffMemberId}) async {
    final member = await _staffMemberRepository.findById(staffMemberId);
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
