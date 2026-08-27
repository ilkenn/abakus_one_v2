import 'package:cloud_functions/cloud_functions.dart' as functions;
import 'package:firebase_auth/firebase_auth.dart' as fb;

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
abstract interface class PlatformClaimsSyncClient {
  /// Calls `syncOwnPlatformClaims`, force-refreshes the current user's ID
  /// token, and returns the refreshed token's `platformRole` claim (`null`
  /// if the caller has no Firebase user signed in, or no active platform
  /// membership was found to sync a role from).
  Future<String?> syncAndRefresh();
}

class DefaultPlatformClaimsSyncClient implements PlatformClaimsSyncClient {
  DefaultPlatformClaimsSyncClient({
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
  Future<String?> syncAndRefresh() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    await _functions
        .httpsCallable('syncOwnPlatformClaims')
        .call<Map<String, dynamic>>();
    final tokenResult = await user.getIdTokenResult(true);
    final role = tokenResult.claims?['platformRole'];
    return role is String ? role : null;
  }
}
