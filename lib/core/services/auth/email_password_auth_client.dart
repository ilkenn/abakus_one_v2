import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../logging/log_level.dart';
import '../logging/logging_provider.dart';
import '../logging/logging_service.dart';
import 'identity_toolkit_rest_auth_client.dart';
import 'windows_rest_auth_session.dart';

/// Shared Firebase-Auth email/password wrapper — Sprint 9C
/// (`docs/decisions.md` ADR-026). Lives in `core/services/` (not a
/// feature) because both `features/admin` (`StaffAuthRepository`) and
/// `features/platform` (`PlatformAuthRepository`) need the exact same
/// low-level operation: this is generic Firebase Auth plumbing, not a
/// role/permission concept, so sharing it does not cross the
/// tenant/platform role-namespace separation those two features otherwise
/// keep strict (`StaffRole` vs `PlatformRole`, `ActorSession` vs
/// `PlatformActorSession` share zero types — this class isn't one of
/// them, deliberately).
///
/// Narrow and mockable for the same reason `FirebaseAuthClient`
/// (`features/auth/data/repositories/firebase_auth_client.dart`) is: the
/// real `firebase_auth` SDK is unavailable under `flutter test`.
abstract interface class EmailPasswordAuthClient {
  Future<EmailPasswordAuthResult> signIn({
    required String email,
    required String password,
  });

  /// Creates a brand-new Firebase Auth account — used only by the two
  /// "bootstrap the first admin/platform owner" use cases, which are
  /// legitimately self-service account creation (there is no existing
  /// admin to have created the account on this person's behalf).
  Future<EmailPasswordAuthResult> createAccount({
    required String email,
    required String password,
  });

  Future<void> signOut();
}

/// The narrow, vendor-free shape of a successful sign-in/account-creation.
class EmailPasswordAuthResult {
  final String uid;
  final String? email;

  const EmailPasswordAuthResult({required this.uid, this.email});
}

/// Thrown instead of leaking a raw `fb.FirebaseAuthException` past this
/// boundary. [code] mirrors `FirebaseAuthException.code` values, the same
/// vocabulary `ErrorMapper._mapFirebaseAuthError` already understands.
class EmailPasswordAuthClientException implements Exception {
  final String code;
  final String message;

  const EmailPasswordAuthClientException(this.code, this.message);

  @override
  String toString() => 'EmailPasswordAuthClientException($code): $message';
}

class DefaultEmailPasswordAuthClient implements EmailPasswordAuthClient {
  DefaultEmailPasswordAuthClient({fb.FirebaseAuth? auth})
      : _providedAuth = auth;

  // Resolved lazily, not in the constructor — mirrors
  // `DefaultFirebaseAuthClient`'s exact reasoning
  // (`features/auth/data/repositories/firebase_auth_client.dart`).
  final fb.FirebaseAuth? _providedAuth;
  fb.FirebaseAuth get _auth => _providedAuth ?? fb.FirebaseAuth.instance;

  @override
  Future<EmailPasswordAuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const EmailPasswordAuthClientException(
          'user-not-found',
          'Sign-in did not return a user.',
        );
      }
      return EmailPasswordAuthResult(uid: user.uid, email: user.email);
    } on fb.FirebaseAuthException catch (error) {
      throw EmailPasswordAuthClientException(
          error.code, error.message ?? error.code);
    }
  }

  @override
  Future<EmailPasswordAuthResult> createAccount({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const EmailPasswordAuthClientException(
          'user-not-found',
          'Account creation did not return a user.',
        );
      }
      return EmailPasswordAuthResult(uid: user.uid, email: user.email);
    } on fb.FirebaseAuthException catch (error) {
      throw EmailPasswordAuthClientException(
          error.code, error.message ?? error.code);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

/// 2026-10-30 — the Windows fix for the native plugin's
/// `signInWithEmailAndPassword` hanging (see `IdentityToolkitRestAuthClient`'s
/// own doc comment for the full root-cause/limitation writeup). Real
/// credential verification against the real Identity Toolkit REST API,
/// never a fabricated session — a wrong password is rejected by Google's
/// own servers exactly as natively, and every successful result updates
/// [WindowsRestAuthSession], which `RestCallableClient`/
/// `DefaultStaffClaimsSyncClient` both read as their fallback token source.
///
/// **Also fires the real native sign-in in the background** (unawaited,
/// best-effort, every error swallowed and logged at debug level only) —
/// purely so `FirebaseAuth.instance.currentUser` gets a chance to populate
/// itself the moment the native transport issue doesn't reproduce (it may
/// be intermittent, not permanent), unlocking the handful of Admin/POS
/// repositories that read Firestore directly through the native plugin.
/// Never awaited, never allowed to affect this class's own result in any
/// way — the whole point is that the fast REST path never waits on it.
class RestEmailPasswordAuthClient implements EmailPasswordAuthClient {
  RestEmailPasswordAuthClient({
    IdentityToolkitRestAuthClient? restClient,
    fb.FirebaseAuth? nativeAuth,
    LoggingService? logging,
    bool attemptNativeSignInInBackground = true,
  })  : _restClient = restClient ?? DefaultIdentityToolkitRestAuthClient(),
        _nativeAuth = nativeAuth,
        _logging = logging ?? defaultLoggingService(),
        _attemptNativeSignInInBackground = attemptNativeSignInInBackground;

  final IdentityToolkitRestAuthClient _restClient;
  final fb.FirebaseAuth? _nativeAuth;
  final LoggingService _logging;
  final bool _attemptNativeSignInInBackground;

  fb.FirebaseAuth get _nativeAuthOrDefault =>
      _nativeAuth ?? fb.FirebaseAuth.instance;

  void _fireBackgroundNativeSignIn(String email, String password) {
    if (!_attemptNativeSignInInBackground) return;
    // Deliberately not awaited by the caller — see this class's own doc
    // comment. `unawaited`-style fire-and-forget without the `unawaited`
    // helper (no new dependency for one call site); the `.catchError`
    // guarantees nothing escapes as an unhandled-Future-error either way.
    _nativeAuthOrDefault
        .signInWithEmailAndPassword(email: email, password: password)
        .then((_) {
      _logging.log(
        LogLevel.debug,
        '[AUTH-TRACE] background native sign-in: succeeded — direct '
        'Firestore reads should now work too',
      );
    }).catchError((Object error) {
      _logging.log(
        LogLevel.debug,
        '[AUTH-TRACE] background native sign-in: failed/still broken '
        '(expected on Windows today) — ignored, REST session unaffected',
        error: error,
      );
    });
  }

  @override
  Future<EmailPasswordAuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final tokens = await _restClient.signInWithPassword(
        email: email,
        password: password,
      );
      WindowsRestAuthSession.set(tokens);
      _fireBackgroundNativeSignIn(email, password);
      return EmailPasswordAuthResult(uid: tokens.localId, email: email);
    } on IdentityToolkitAuthException catch (error) {
      throw EmailPasswordAuthClientException(error.code, error.message);
    }
  }

  @override
  Future<EmailPasswordAuthResult> createAccount({
    required String email,
    required String password,
  }) async {
    try {
      final tokens = await _restClient.createAccount(
        email: email,
        password: password,
      );
      WindowsRestAuthSession.set(tokens);
      return EmailPasswordAuthResult(uid: tokens.localId, email: email);
    } on IdentityToolkitAuthException catch (error) {
      throw EmailPasswordAuthClientException(error.code, error.message);
    }
  }

  @override
  Future<void> signOut() async {
    WindowsRestAuthSession.clear();
    // Best-effort — if the background native sign-in in `signIn` ever
    // happened to succeed, this clears that session too; if it never did,
    // this is a harmless no-op.
    try {
      await _nativeAuthOrDefault.signOut();
    } catch (_) {
      // Ignored — signing out of a session that was never established
      // natively is not an error from this class's own contract.
    }
  }
}
