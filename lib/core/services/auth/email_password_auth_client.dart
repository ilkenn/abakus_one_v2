import 'package:firebase_auth/firebase_auth.dart' as fb;

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
