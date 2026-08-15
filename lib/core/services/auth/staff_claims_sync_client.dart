import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:firebase_auth/firebase_auth.dart' as fb;

/// The parsed shape of the `organizationAccess`/`roles`/`branchAccess`
/// custom claims `syncOwnStaffClaims` writes (`functions/src/
/// staffMembership.ts`'s `resyncClaimsForUid`) — Faz R.3A.2, extended
/// Faz R.3C.2. Deliberately mirrors that callable's exact claim schema (a
/// flat `organizationAccess: string[]` plus `roles`/`branchAccess`, both
/// `Record<organizationId, string[]>`), not a client invention: today's
/// claims carry role names and explicit branch ids only — no separate
/// "permissions" list, no wildcard/"all branches" value, and no
/// `restaurantAccess` at all (that remains `StaffMemberRepository`-sourced
/// profile metadata, since the backend's own `requireStaffPermission`
/// never reads it either).
///
/// **Faz R.3C.2 — `branchAccess` is now the sole authorization-critical
/// source for branch-scoped operational data (e.g. Orders/KDS reads),
/// mirroring `firestore.rules`'s own `hasBranchAccess` exactly.**
/// [StaffMemberRepository]'s own `branchAccess` field is no longer
/// consulted for this — see `staff_auth_repository.dart`'s doc comment.
class StaffAuthorizationClaims {
  const StaffAuthorizationClaims({
    required this.organizationAccess,
    required this.rolesByOrganization,
    required this.branchAccessByOrganization,
  });

  /// No claims at all — the correct, safe parse of a token with no
  /// `organizationAccess`/`roles`/`branchAccess` custom claims yet (never
  /// signed in, never synced, or every membership inactive). Combined with
  /// [ActorSession.tryFromRaw]'s own "empty roles -> null session" rule,
  /// this fails closed structurally, not by caller discipline.
  static const empty = StaffAuthorizationClaims(
    organizationAccess: [],
    rolesByOrganization: {},
    branchAccessByOrganization: {},
  );

  final List<String> organizationAccess;
  final Map<String, List<String>> rolesByOrganization;
  final Map<String, List<String>> branchAccessByOrganization;

  /// The raw role-name strings held for [organizationId] — `const []` if
  /// the token carries no `roles` entry for it at all (never a null-shaped
  /// "trust everything" fallback).
  List<String> rolesFor(String organizationId) =>
      rolesByOrganization[organizationId] ?? const [];

  /// The explicit branch ids held for [organizationId] — `const []` if the
  /// token carries no `branchAccess` entry for it at all (missing or
  /// malformed always means zero branch access, never "every branch").
  List<String> branchAccessFor(String organizationId) =>
      branchAccessByOrganization[organizationId] ?? const [];
}

/// Faz R.3A — the client-side half of the staff claims-sync foundation.
/// After a real staff sign-in, the signed-in Firebase user's ID token
/// carries no `organizationAccess`/`roles` custom claims at all until
/// `syncOwnStaffClaims` (the Cloud Function) runs and the token is force-
/// refreshed — this is the one call site responsible for both steps, so
/// no `manageReservations`/`manageBranch`-gated screen anywhere in the
/// admin app needs to remember to do it itself.
///
/// **Faz R.3A.2**: now also the sole, canonical source
/// `FirebaseStaffAuthRepository` builds `ActorSession.roles`/
/// `organizationAccess` from — the backend's own `requireStaffPermission`
/// authorizes off exactly these token claims, never off
/// `StaffMemberRepository`, so the client must not either (see that
/// repository's own doc comment for the full "two authority sources"
/// rationale this closes).
///
/// Narrow and mockable for the same reason `EmailPasswordAuthClient` is:
/// the real `cloud_functions`/`firebase_auth` SDKs are unavailable under
/// `flutter test`.
abstract interface class StaffClaimsSyncClient {
  /// Calls `syncOwnStaffClaims`, force-refreshes the current user's ID
  /// token (`getIdTokenResult(true)`), and returns the freshly-refreshed
  /// token's parsed authorization claims — `null` only when no Firebase
  /// user is currently signed in (never a signal about permission; that's
  /// [StaffAuthorizationClaims.empty]'s job). Safe to call even when no
  /// user is signed in — callers don't need their own guard.
  Future<StaffAuthorizationClaims?> syncAndRefresh();
}

class DefaultStaffClaimsSyncClient implements StaffClaimsSyncClient {
  DefaultStaffClaimsSyncClient({
    functions.FirebaseFunctions? functionsInstance,
    fb.FirebaseAuth? auth,
  })  : _providedFunctions = functionsInstance,
        _providedAuth = auth;

  final functions.FirebaseFunctions? _providedFunctions;
  final fb.FirebaseAuth? _providedAuth;
  functions.FirebaseFunctions get _functions =>
      _providedFunctions ?? functions.FirebaseFunctions.instance;
  fb.FirebaseAuth get _auth => _providedAuth ?? fb.FirebaseAuth.instance;

  @override
  Future<StaffAuthorizationClaims?> syncAndRefresh() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    await _functions
        .httpsCallable('syncOwnStaffClaims')
        .call<Map<String, dynamic>>();
    final tokenResult = await user.getIdTokenResult(true);
    return parseStaffAuthorizationClaims(tokenResult.claims);
  }
}

/// Parses an ID token's raw `claims` map into [StaffAuthorizationClaims] —
/// a top-level function (not a private instance method) specifically so it
/// is unit-testable against arbitrary/malformed shapes without a real
/// `firebase_auth`/`cloud_functions` SDK. Malformed or missing claim shapes
/// degrade to [StaffAuthorizationClaims.empty] rather than throwing —
/// "missing or malformed claims denies safely," never crashes the
/// sign-in/refresh flow.
StaffAuthorizationClaims parseStaffAuthorizationClaims(
  Map<String, dynamic>? claims,
) {
  if (claims == null) return StaffAuthorizationClaims.empty;

  final rawOrganizationAccess = claims['organizationAccess'];
  final organizationAccess = rawOrganizationAccess is List
      ? rawOrganizationAccess.whereType<String>().toList()
      : const <String>[];

  return StaffAuthorizationClaims(
    organizationAccess: organizationAccess,
    rolesByOrganization: _parseByOrganization(claims['roles']),
    branchAccessByOrganization: _parseByOrganization(claims['branchAccess']),
  );
}

/// Parses a `Record<organizationId, string[]>`-shaped claim value (the
/// exact shape both `roles` and `branchAccess` share) — a malformed entry
/// (a non-string key, a non-list value) is dropped rather than throwing or
/// propagating a partially-wrong shape, matching this function's own
/// "missing/malformed denies safely" contract.
Map<String, List<String>> _parseByOrganization(dynamic raw) {
  final result = <String, List<String>>{};
  if (raw is! Map) return result;
  for (final entry in raw.entries) {
    final organizationId = entry.key;
    final value = entry.value;
    if (organizationId is! String || value is! List) continue;
    result[organizationId] = value.whereType<String>().toList();
  }
  return result;
}
