import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../../bootstrap/app_environment.dart';
import '../../../bootstrap/firebase_functions_emulator_config.dart';
import '../functions/rest_callable_client.dart';
import '../logging/log_level.dart';
import '../logging/logging_provider.dart';
import '../logging/logging_service.dart';

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
  ///
  /// [allowCachedTokenFallback] (default `false`, strict): if the forced
  /// refresh itself throws (observed on Windows desktop against the Auth
  /// Emulator — `[firebase_auth/unknown-error]` out of
  /// `FirebaseAuthUserHostApi.getIdToken`, PC Yönetici İnceleme Modu,
  /// 2026-09-14) and this is `true`, falls back to the current CACHED
  /// token (`getIdTokenResult(false)`) instead of rethrowing. **Only ever
  /// pass `true` when the token was just minted moments ago by a real
  /// credential check** (a freshly-issued token already carries whatever
  /// claims exist server-side at that instant — `FirebaseStaffAuthRepository
  /// .signIn`'s own case) — never for a long-lived session's periodic
  /// [FirebaseStaffAuthRepository.refreshSession], whose entire security
  /// purpose is forcing a refresh to catch a role revoked *after* the
  /// session began; silently trusting a stale cached token there would
  /// defeat "a removed role takes effect immediately after session
  /// refresh" on whichever platform this failure occurs.
  ///
  /// [remintToken], when supplied, performs a full real re-authentication
  /// (e.g. `EmailPasswordAuthClient.signIn` again with the same
  /// credentials) — used on Windows instead of relying on
  /// `getIdTokenResult(true)`'s force flag at all, since that flag has been
  /// observed to leave a genuinely stale (pre-`syncOwnStaffClaims`) cached
  /// token in place with no error (PC Yönetici İnceleme Modu, 2026-09-21;
  /// distinct from the throw-on-force-refresh case [allowCachedTokenFallback]
  /// covers — confirmed via `[AUTH-TRACE]`: `seed_dev_staff.mjs` verified
  /// the account's real server-side claims were correct, yet Windows kept
  /// reporting empty ones). A plain sign-in always requests a brand-new
  /// token from the Auth server — this sidesteps the platform-specific
  /// refresh-flag bug entirely rather than working around its symptom.
  /// Only ever supplied by a caller that holds real credentials in scope
  /// (`FirebaseStaffAuthRepository.signIn`); [refreshSession] has none to
  /// re-authenticate with and must never be given one.
  Future<StaffAuthorizationClaims?> syncAndRefresh({
    bool allowCachedTokenFallback = false,
    Future<void> Function()? remintToken,
  });
}

class DefaultStaffClaimsSyncClient implements StaffClaimsSyncClient {
  DefaultStaffClaimsSyncClient({
    functions.FirebaseFunctions? functionsInstance,
    fb.FirebaseAuth? auth,
    RestCallableClient? restClient,
    LoggingService? logging,
  })  : _providedFunctions = functionsInstance,
        _providedAuth = auth,
        _restClient = restClient ?? RestCallableClient(),
        _logging = logging ?? defaultLoggingService();

  final functions.FirebaseFunctions? _providedFunctions;
  final fb.FirebaseAuth? _providedAuth;
  final RestCallableClient _restClient;
  final LoggingService _logging;

  /// Temporary diagnostic (PC Yönetici İnceleme Modu, 2026-09-21) — logs
  /// the token's raw, unparsed `claims` map before
  /// [parseStaffAuthorizationClaims] touches it, so a mismatch between
  /// what the Auth Emulator actually sent and what this client expects to
  /// find is directly visible, instead of inferred from the parsed (and
  /// therefore already-lossy) result alone. Routed through
  /// [LoggingService], never a raw `debugPrint`, for the same reason every
  /// other `[AUTH-TRACE]` line this session added is: `LogRedactor`
  /// sanitization still applies, and it's automatically silent in release
  /// builds. Remove once the claims-shape question this was added to
  /// answer is settled.
  void _logRawClaims(Map<String, dynamic>? rawClaims) {
    _logging.log(
      LogLevel.debug,
      '[AUTH-TRACE] RAW TOKEN CLAIMS: $rawClaims',
    );
  }

  Future<Map<String, dynamic>?> _resolveClaims(
    fb.User user,
    fb.IdTokenResult tokenResult,
  ) async {
    if (tokenResult.claims != null) return tokenResult.claims;
    // **2026-09-21**: confirmed via the diagnostic above —
    // `IdTokenResult.claims` came back `null` on Windows for a token
    // whose custom claims were independently verified correct
    // server-side (`seed_dev_staff.mjs`'s own
    // `admin.auth().getUser(uid).customClaims` check). This points at
    // the Windows `firebase_auth` plugin failing to populate/deserialize
    // that field specifically, not at the token actually lacking claims.
    // Rather than trusting a *different* unverified value (an
    // email-based "assume admin" fallback, which would silently paper
    // over the real gap and not actually reflect what's on the token),
    // fall back to decoding the SAME real ID token's own payload
    // directly via [decodeJwtPayload].
    final rawToken = await user.getIdToken();
    return rawToken == null ? null : decodeJwtPayload(rawToken);
  }

  functions.FirebaseFunctions get _functions =>
      _providedFunctions ?? functions.FirebaseFunctions.instance;
  fb.FirebaseAuth get _auth => _providedAuth ?? fb.FirebaseAuth.instance;

  @override
  Future<StaffAuthorizationClaims?> syncAndRefresh({
    bool allowCachedTokenFallback = false,
    Future<void> Function()? remintToken,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    // The official `cloud_functions` plugin ships no native Windows desktop
    // implementation (confirmed: absent from `windows/flutter/
    // generated_plugin_registrant.cc`, unlike `firebase_auth`, which is
    // present there) — `httpsCallable(...).call()` on Windows throws
    // `[firebase_functions/unknown] Unable to establish connection on
    // channel...`. Root-caused via this session's own `[AUTH-TRACE]`
    // diagnostic logging (PC Yönetici İnceleme Modu, 2026-09-14).
    //
    // **2026-09-20**: previously skipped entirely on Windows, relying on
    // claims already synced by some other means (a dev seed script, or a
    // prior sign-in from a working platform) — this silently left a
    // Windows-only sign-in with genuinely empty claims whenever that
    // wasn't true, which is exactly what caused a real, reported
    // downstream failure (`requestDeviceRegistration`'s 403
    // "authorization is required for this organization" — a real staff
    // permission check correctly denying a token that legitimately never
    // got its claims). Now routed through `RestCallableClient` on Windows
    // instead of skipped — the same real callable, reached over plain
    // HTTP rather than the broken native plugin (same bridge already
    // proven working for `getPosBranchTableOverview`/trusted-device
    // callables). Every other platform takes the exact same
    // `cloud_functions` path as before, byte-for-byte.
    final useRest = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        FirebaseFunctionsEmulatorConfig.shouldUseEmulator(
            AppEnvironment.current);
    if (useRest) {
      await _restClient.call('syncOwnStaffClaims', const {});
    } else {
      await _functions
          .httpsCallable('syncOwnStaffClaims')
          .call<Map<String, dynamic>>();
    }

    if (useRest && remintToken != null) {
      // Sidesteps `getIdTokenResult(true)`'s force-refresh flag entirely on
      // Windows, rather than working around its symptom — see this
      // method's own [StaffClaimsSyncClient.syncAndRefresh] doc comment on
      // [remintToken] for why the flag itself is not trustworthy here (it
      // has been observed leaving a pre-sync token in place with no
      // error, not just throwing). A real sign-in unconditionally mints a
      // brand-new token from the Auth server, so the very next
      // (non-forced) read is guaranteed fresh — no platform-specific
      // refresh behavior involved at all.
      await remintToken();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) return null;
      final tokenResult = await refreshedUser.getIdTokenResult(false);
      final resolvedClaims = await _resolveClaims(refreshedUser, tokenResult);
      _logRawClaims(resolvedClaims);
      return parseStaffAuthorizationClaims(resolvedClaims);
    }

    fb.IdTokenResult tokenResult;
    try {
      tokenResult = await user.getIdTokenResult(true);
    } catch (e) {
      if (!allowCachedTokenFallback) rethrow;
      // Windows desktop's `firebase_auth` C++/Pigeon layer has been
      // observed throwing `[firebase_auth/unknown-error] An internal
      // error has occurred.` out of `FirebaseAuthUserHostApi.getIdToken`
      // specifically on a forced refresh against the Auth Emulator (PC
      // Yönetici İnceleme Modu, 2026-09-14) — caught reactively, not a
      // proactive platform check, so a genuine forced-refresh failure on
      // a platform where it normally works (web, Android, iOS) still
      // surfaces normally instead of being silently absorbed here. Safe
      // only because every caller passing `allowCachedTokenFallback: true`
      // does so right after minting this exact token — see this
      // parameter's own doc comment on [StaffClaimsSyncClient.syncAndRefresh].
      tokenResult = await user.getIdTokenResult(false);
    }
    final resolvedClaims = await _resolveClaims(user, tokenResult);
    _logRawClaims(resolvedClaims);
    return parseStaffAuthorizationClaims(resolvedClaims);
  }
}

/// Decodes a JWT's payload segment (`header.payload.signature`) into a raw
/// map — a top-level function (not a private instance method), same reason
/// [parseStaffAuthorizationClaims] is: unit-testable against arbitrary
/// strings with zero `firebase_auth` SDK involvement. A JWT's payload is
/// plain base64url-encoded JSON; Firebase custom claims
/// (`admin.auth().setCustomUserClaims`) are merged directly into it at the
/// top level, so this needs nothing Firebase-specific to read them back —
/// used as a fallback when `IdTokenResult.claims` itself comes back `null`
/// (observed on Windows desktop against the Auth Emulator for a token
/// whose claims were independently verified correct server-side, PC
/// Yönetici İnceleme Modu, 2026-09-21) rather than trusting a different,
/// unverified value in its place. Returns `null` for anything that isn't a
/// well-formed 3-segment JWT with a JSON-object payload — never throws.
Map<String, dynamic>? decodeJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final normalized = base64Url.normalize(parts[1]);
    final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// Parses an ID token's raw `claims` map into [StaffAuthorizationClaims] —
/// a top-level function (not a private instance method) specifically so it
/// is unit-testable against arbitrary/malformed shapes without a real
/// `firebase_auth`/`cloud_functions` SDK. Malformed or missing claim shapes
/// degrade to [StaffAuthorizationClaims.empty] rather than throwing —
/// "missing or malformed claims denies safely," never crashes the
/// sign-in/refresh flow.
///
/// **Deliberately no dev/debug/platform fallback here that substitutes
/// fabricated claims (e.g. a hardcoded admin/tenantOwner role set) when
/// [claims] is empty or malformed.** That was tried directly in this
/// function during this session's Windows investigation and reverted: this
/// is a shared, unconditional parsing path every caller on every platform
/// and every build mode goes through, so such a fallback would silently
/// grant fabricated org/role/branch access to ANY signed-in user whose
/// claims are legitimately empty — including in a release build, for a
/// genuinely unauthorized account — not just the intended Windows dev-admin
/// case. It would also contradict [StaffAuthorizationClaims.empty]'s own
/// documented invariant ("fails closed structurally, not by caller
/// discipline") a few lines above. A Windows-specific claims gap belongs in
/// [DefaultStaffClaimsSyncClient] (see [decodeJwtPayload]/`remintToken`),
/// scoped and reasoned about there — never here.
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
