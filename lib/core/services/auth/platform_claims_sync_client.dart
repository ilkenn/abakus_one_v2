import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../functions/rest_callable_client.dart';
import 'identity_toolkit_rest_auth_client.dart';
import 'staff_claims_sync_client.dart' show decodeJwtPayload;
import 'windows_rest_auth_session.dart';

/// AP-2 final wiring — mirrors `StaffClaimsSyncClient` exactly, one tier
/// up: after a real platform sign-in, the signed-in user's ID token
/// carries no `platformRole` custom claim at all until
/// `syncOwnPlatformClaims` (`functions/src/platformMembership.ts`) runs
/// and the token is force-refreshed. This is the one call site
/// responsible for both steps — without it, `platformMembers/{uid}`'s own
/// Firestore rule (`isPlatformMember() && request.auth.uid ==
/// platformMemberId`) can never pass for a freshly-signed-in platform
/// member, since `isPlatformMember()` reads the token claim, not the
/// Firestore doc directly (a structural chicken-and-egg
/// `syncOwnPlatformClaims` alone resolves, since it runs Admin-SDK-side).
///
/// [remintToken] (2026-10-30) — added for exactly the same reason
/// `StaffClaimsSyncClient.syncAndRefresh`'s own parameter of the same
/// name exists: on Windows, under the real REST Identity Toolkit bridge
/// (`RestEmailPasswordAuthClient`), there is no native `currentUser` to
/// force-refresh at all — a full real re-sign-in is the only way to mint
/// a brand-new token that already carries whatever `syncOwnPlatformClaims`
/// just wrote. Only ever supplied by a caller that holds real credentials
/// in scope (`FirebasePlatformAuthRepository.signIn`).
abstract interface class PlatformClaimsSyncClient {
  Future<String?> syncAndRefresh({Future<void> Function()? remintToken});
}

class DefaultPlatformClaimsSyncClient implements PlatformClaimsSyncClient {
  DefaultPlatformClaimsSyncClient({
    functions.FirebaseFunctions? functionsInstance,
    fb.FirebaseAuth? auth,
    RestCallableClient? restClient,
  })  : _providedFunctions = functionsInstance,
        _providedAuth = auth,
        _restClient = restClient ?? RestCallableClient();

  final functions.FirebaseFunctions? _providedFunctions;
  final fb.FirebaseAuth? _providedAuth;
  final RestCallableClient _restClient;
  functions.FirebaseFunctions get _functions =>
      _providedFunctions ?? functions.FirebaseFunctions.instance;
  fb.FirebaseAuth get _auth => _providedAuth ?? fb.FirebaseAuth.instance;

  @override
  Future<String?> syncAndRefresh({Future<void> Function()? remintToken}) async {
    final user = _auth.currentUser;
    final useRest = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final restSessionActive = useRest && WindowsRestAuthSession.isActive;
    if (user == null && !restSessionActive) return null;

    if (useRest) {
      await _restClient.call('syncOwnPlatformClaims', const {});
    } else {
      await _functions
          .httpsCallable('syncOwnPlatformClaims')
          .call<Map<String, dynamic>>();
    }

    if (useRest && user == null) {
      // Pure-REST session (no native user at all) — the Windows case
      // under `RestEmailPasswordAuthClient`. Decode `platformRole`
      // directly from the current/freshly-reminted REST token's own JWT
      // payload — there is no native `IdTokenResult` to read it from.
      if (remintToken != null) await remintToken();
      final restAuthClient = DefaultIdentityToolkitRestAuthClient();
      final token = remintToken != null
          ? await WindowsRestAuthSession.currentIdToken(client: restAuthClient)
          : await WindowsRestAuthSession.forceRefresh(client: restAuthClient);
      if (token == null) return null;
      final role = decodeJwtPayload(token)?['platformRole'];
      return role is String ? role : null;
    }

    final tokenResult = await user!.getIdTokenResult(true);
    final role = tokenResult.claims?['platformRole'];
    return role is String ? role : null;
  }
}
