import 'dart:async';

import '../../../core/services/auth/email_password_auth_client.dart';
import '../../../core/services/auth/staff_claims_sync_client.dart';
import '../../../core/services/logging/log_level.dart';
import '../../../core/services/logging/logging_provider.dart';
import '../../../core/services/logging/logging_service.dart';
import '../../pos/domain/authorization/actor_session.dart';
import '../domain/staff/staff_member.dart';
import '../domain/staff/staff_member_status.dart';
import 'staff_member_repository.dart';

/// The upper bound every network-dependent step of [FirebaseStaffAuthRepository]
/// is wrapped in — chosen generous enough for a cold Cloud Functions
/// invocation, but finite: no step in this class may ever leave a caller
/// awaiting forever. Every step that hits this bound surfaces as a typed,
/// catchable [StaffAuthUnavailableException] instead — "an indefinite
/// loading state is forbidden" applies to every await in this file, not
/// just the ones a prior pass already caught.
const staffAuthNetworkTimeout = Duration(seconds: 20);

/// Thrown when a sign-in-critical step (credential verification, claims
/// sync) cannot complete within [staffAuthNetworkTimeout] — deliberately
/// distinct from `signIn` returning `null` (which means "the credential or
/// its authorization was genuinely checked and rejected"). A caller must
/// show this as a retryable connectivity error, never as "check your
/// email/password" — the credential was never actually evaluated.
class StaffAuthUnavailableException implements Exception {
  const StaffAuthUnavailableException(this.message);
  final String message;

  @override
  String toString() => 'StaffAuthUnavailableException: $message';
}

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
    Duration networkTimeout = staffAuthNetworkTimeout,
    LoggingService? logging,
  })  : _authClient = authClient,
        _staffMemberRepository = staffMemberRepository,
        _sessionDuration = sessionDuration,
        _claimsSyncClient = claimsSyncClient,
        _organizationId = organizationId,
        _networkTimeout = networkTimeout,
        _logging = logging ?? defaultLoggingService();

  final EmailPasswordAuthClient _authClient;
  final StaffMemberRepository _staffMemberRepository;
  final Duration _networkTimeout;
  final Duration Function() _sessionDuration;
  final StaffClaimsSyncClient _claimsSyncClient;
  final String Function() _organizationId;

  /// **Temporary diagnostic tracing** (PC Yönetici İnceleme Modu — Chrome
  /// latency report, 2026-09-11): logs a start/end timestamp pair around
  /// each network-dependent step of [signIn] under the `[AUTH-TRACE]` tag,
  /// so a real, measured per-step duration is visible in the console
  /// instead of inferred. Routed through [LoggingService] (never a raw
  /// `print`/`debugPrint`) specifically so [LogRedactor] still sanitizes
  /// anything step-identifying that gets interpolated — the trace messages
  /// themselves never carry the email/password/token values. `debug`-level
  /// and silent in release builds ([defaultLoggingService]'s own
  /// [kReleaseMode] gate) — remove once the latency question this was
  /// added to answer is settled.
  final LoggingService _logging;

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
    final signInWatch = Stopwatch()..start();
    _logging.log(LogLevel.debug, '[AUTH-TRACE] signIn: start');
    try {
      result = await _authClient
          .signIn(email: email, password: password)
          .timeout(_networkTimeout);
      _logging.log(LogLevel.debug,
          '[AUTH-TRACE] signIn: end (${signInWatch.elapsedMilliseconds}ms)');
    } on EmailPasswordAuthClientException catch (e, st) {
      _logging.log(
        LogLevel.error,
        '[AUTH-TRACE] signIn: rejected (${signInWatch.elapsedMilliseconds}ms)',
        error: e,
        stackTrace: st,
      );
      return null;
    } on TimeoutException catch (e, st) {
      _logging.log(
        LogLevel.error,
        '[AUTH-TRACE] signIn: timeout (${signInWatch.elapsedMilliseconds}ms)',
        error: e,
        stackTrace: st,
      );
      throw const StaffAuthUnavailableException(
        'Giriş isteği zaman aşımına uğradı — bağlantınızı kontrol edip '
        'tekrar deneyin.',
      );
    }

    final StaffAuthorizationClaims? claims;
    final syncWatch = Stopwatch()..start();
    _logging.log(LogLevel.debug, '[AUTH-TRACE] syncAndRefresh: start');
    try {
      // `allowCachedTokenFallback: true` is safe here specifically: this
      // token was just minted moments ago by the real credential check
      // above, so it already carries whatever claims exist server-side at
      // this instant — see the parameter's own doc comment on
      // `StaffClaimsSyncClient.syncAndRefresh` for why `refreshSession`
      // below must NOT pass this.
      claims = await _claimsSyncClient
          .syncAndRefresh(allowCachedTokenFallback: true)
          .timeout(_networkTimeout);
      _logging.log(LogLevel.debug,
          '[AUTH-TRACE] syncAndRefresh: end (${syncWatch.elapsedMilliseconds}ms)');
    } on TimeoutException catch (e, st) {
      _logging.log(
        LogLevel.error,
        '[AUTH-TRACE] syncAndRefresh: timeout (${syncWatch.elapsedMilliseconds}ms)',
        error: e,
        stackTrace: st,
      );
      throw const StaffAuthUnavailableException(
        'Yetki bilgileri alınamadı (zaman aşımı) — tekrar deneyin.',
      );
    }
    if (claims == null) {
      _logging.log(LogLevel.debug,
          '[AUTH-TRACE] syncAndRefresh: no Firebase user actually signed in');
      return null;
    }
    // Role-name/org-id strings only — never a token, email, or password —
    // so this is safe to print. Pinpoints whether an "invalid credential"
    // result traces back to genuinely empty claims for this organization
    // (e.g. an Auth-emulator/Firestore-emulator data mismatch across
    // restarts leaving no matching `memberships` doc for this uid) versus
    // something else further down `signIn`.
    _logging.log(
      LogLevel.debug,
      '[AUTH-TRACE] syncAndRefresh: claims for org=${_organizationId()} -> '
      'organizationAccess=${claims.organizationAccess}, '
      'roles=${claims.rolesFor(_organizationId())}',
    );

    // Profile/display metadata only — see the class-level note above. A
    // failed/unavailable/slow directory lookup must never deny or hang a
    // sign-in the real claims already authorize — bounded by the same
    // timeout so a hanging query degrades to "no metadata" rather than an
    // indefinite wait.
    StaffMember? member;
    final lookupWatch = Stopwatch()..start();
    _logging.log(LogLevel.debug, '[AUTH-TRACE] staff-member lookup: start');
    try {
      member = await _staffMemberRepository
          .findByAuthUid(result.uid)
          .timeout(_networkTimeout);
      _logging.log(LogLevel.debug,
          '[AUTH-TRACE] staff-member lookup: end (${lookupWatch.elapsedMilliseconds}ms)');
    } catch (e, st) {
      _logging.log(
        LogLevel.error,
        '[AUTH-TRACE] staff-member lookup: failed, ignored — metadata-only '
        '(${lookupWatch.elapsedMilliseconds}ms)',
        error: e,
        stackTrace: st,
      );
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
    final StaffAuthorizationClaims? claims;
    try {
      // Deliberately NOT `allowCachedTokenFallback: true` — this call's
      // entire purpose is detecting a role revoked since [current] was
      // issued ("removed role takes effect immediately after session
      // refresh," this class's own doc comment above). Silently trusting
      // a stale cached token here on a forced-refresh failure would defeat
      // that guarantee; see `StaffClaimsSyncClient.syncAndRefresh`'s own
      // doc comment for why only a just-minted token (`signIn`, above) may
      // opt into that fallback.
      claims =
          await _claimsSyncClient.syncAndRefresh().timeout(_networkTimeout);
    } on TimeoutException {
      throw const StaffAuthUnavailableException(
        'Oturum yenilenemedi (zaman aşımı) — tekrar deneyin.',
      );
    }
    if (claims == null) return null;

    final roleNames = claims.rolesFor(_organizationId());
    final branchAccess = claims.branchAccessFor(_organizationId());

    // Profile/display metadata only — see the class-level note above. A
    // failed/unavailable/slow directory lookup must never deny or hang what
    // the real claims already grant.
    StaffMember? member;
    try {
      member = await _staffMemberRepository
          .findById(current.actorId)
          .timeout(_networkTimeout);
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
