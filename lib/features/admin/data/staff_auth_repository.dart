import '../../../core/services/auth/email_password_auth_client.dart';
import '../../../core/services/auth/staff_claims_sync_client.dart';
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
  /// or `null` if the credential is invalid or resolves to no real
  /// authorization at all. **Faz R.3A.2**: for [FirebaseStaffAuthRepository]
  /// specifically, "real authorization" means the account's *Firebase ID
  /// token custom claims* (synced from `memberships` by
  /// `syncOwnStaffClaims`) resolve to at least one role for the current
  /// organization — not [StaffMember]/[StaffMemberStatus] (see that class's
  /// own doc comment for why). Deliberately never distinguishes failure
  /// reasons to the caller (avoids leaking which email addresses have an
  /// account at all).
  Future<ActorSession?> signIn({
    required String email,
    required String password,
  });

  /// Re-derives [current]'s authorization fresh and rebuilds it, or returns
  /// `null` if it's no longer valid — "removed role takes effect
  /// immediately after session refresh." For [FirebaseStaffAuthRepository],
  /// this re-syncs and re-parses the real custom claims (never
  /// [StaffMember] alone); a suspended/archived membership naturally
  /// resolves to zero roles on the next sync, which is what actually
  /// revokes access.
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
/// (`docs/decisions.md` ADR-026), realigned to claims-based authorization
/// in Faz R.3A.2. [signIn] authenticates against real Firebase Auth (the
/// local Auth Emulator in `AppEnvironment.development`, the real project in
/// staging/production — decided once at bootstrap, exactly like
/// `FirebaseAuthRepository` for customers), then requires the account's
/// **Firebase ID token custom claims** to resolve to at least one real
/// role for the current organization before issuing a session — a valid
/// Firebase credential alone is not enough. [StaffMember] linkage
/// (`findByAuthUid`) is consulted only for best-effort profile/scope
/// metadata, never as a second authorization gate — see the field-level
/// comment below for why.
class FirebaseStaffAuthRepository implements StaffAuthRepository {
  FirebaseStaffAuthRepository({
    required EmailPasswordAuthClient authClient,
    required StaffMemberRepository staffMemberRepository,
    required Duration Function() sessionDuration,
    required StaffClaimsSyncClient claimsSyncClient,
    required String Function() organizationId,
  })  : _authClient = authClient,
        _staffMemberRepository = staffMemberRepository,
        _sessionDuration = sessionDuration,
        _claimsSyncClient = claimsSyncClient,
        _organizationId = organizationId;

  final EmailPasswordAuthClient _authClient;
  final StaffMemberRepository _staffMemberRepository;
  final Duration Function() _sessionDuration;
  final StaffClaimsSyncClient _claimsSyncClient;
  final String Function() _organizationId;

  // Faz R.3A.2 — the backend's own real authorization
  // (`manageReservations`/`manageBranch`/etc.) is derived entirely from
  // `memberships` Firestore-backed custom claims (`syncOwnStaffClaims`),
  // never from `StaffMemberRepository` — so this repository now builds
  // `ActorSession.roles`/`organizationAccess` from those exact same
  // claims, not from `StaffMember`. This closes a real divergence:
  // `StaffMemberRepository` resolves to `ProductionUnavailableStaffMember
  // Repository` in release builds (always `null`), which previously meant
  // a real, backend-authorized staff member could obtain NO session at
  // all in a release build, regardless of their real claims.
  //
  // **Faz R.3C.2**: `ActorSession.branchAccess` now comes from the same
  // claims too (`claims.branchAccessFor(...)`), not from `StaffMember
  // .branchAccess` — `firestore.rules`' `orders` `read` rule now enforces
  // branch access server-side via the identical claim
  // (`hasBranchAccess`), so a client-side `ActorSession` built from a
  // *different*, non-authoritative source (`StaffMemberRepository`, which
  // is itself only best-effort/unavailable in release builds) could
  // silently diverge from what the backend actually allows — showing a
  // branch as accessible in the UI that every real read would then deny,
  // or vice versa. `StaffMemberRepository` is still consulted below, but
  // now strictly for profile/display metadata only (a friendlier
  // `actorId`, `restaurantAccess` — carried in neither today's claim
  // schema nor read by the backend's own `requireStaffPermission`) — its
  // absence or unavailability never denies a session, or narrows branch
  // scope, the real claims would otherwise grant.

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

    final claims = await _claimsSyncClient.syncAndRefresh();
    if (claims == null) return null; // no Firebase user actually signed in

    // Profile/display metadata only — see the class-level note above. A
    // failed/unavailable directory lookup must never deny or hang a sign-in
    // the real claims already authorize.
    StaffMember? member;
    try {
      member = await _staffMemberRepository.findByAuthUid(result.uid);
    } catch (_) {
      member = null;
    }

    final now = DateTime.now();
    return ActorSession.tryFromRaw(
      actorId: member?.id ?? result.uid,
      roleNames: claims.rolesFor(_organizationId()),
      branchAccessIds: claims.branchAccessFor(_organizationId()),
      restaurantAccessIds: (member?.restaurantAccess ?? const {}).toList(),
      organizationAccessIds: claims.organizationAccess,
      issuedAt: now,
      expiresAt: now.add(_sessionDuration()),
    );
  }

  @override
  Future<ActorSession?> refreshSession(ActorSession current) async {
    final claims = await _claimsSyncClient.syncAndRefresh();
    if (claims == null) return null;

    final roleNames = claims.rolesFor(_organizationId());
    final branchAccess = claims.branchAccessFor(_organizationId());

    // Profile/display metadata only — see the class-level note above. A
    // failed/unavailable directory lookup must never deny or hang what the
    // real claims already grant.
    StaffMember? member;
    try {
      member = await _staffMemberRepository.findById(current.actorId);
    } catch (_) {
      member = null;
    }
    if (member != null) {
      final revokedAt = member.sessionsRevokedAt;
      if (revokedAt != null &&
          current.issuedAt != null &&
          current.issuedAt!.isBefore(revokedAt)) {
        return null;
      }
    }

    final stillHasActiveRole = roleNames.contains(current.activeRole.name);
    final stillHasActiveBranch = current.activeBranchId != null &&
        branchAccess.contains(current.activeBranchId);

    return ActorSession.tryFromRaw(
      actorId: current.actorId,
      roleNames: roleNames,
      activeRoleName: stillHasActiveRole ? current.activeRole.name : null,
      branchAccessIds: branchAccess,
      restaurantAccessIds: (member?.restaurantAccess ?? const {}).toList(),
      organizationAccessIds: claims.organizationAccess,
      activeBranchId: stillHasActiveBranch ? current.activeBranchId : null,
      issuedAt: current.issuedAt,
      expiresAt: current.expiresAt,
    );
  }

  @override
  Future<void> signOut() => _authClient.signOut();
}
