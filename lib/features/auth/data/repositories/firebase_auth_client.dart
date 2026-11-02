import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;

/// The narrow slice of Firebase Auth's phone-verification flow
/// [FirebaseAuthRepository] actually needs, behind an interface — mirrors
/// `CrashlyticsClient` (`core/services/crash_reporting/firebase_crashlytics_service.dart`,
/// Sprint 9A): the real `firebase_auth` SDK is unavailable under
/// `flutter test` (it's backed by a platform channel), so every real
/// consumer wraps a narrow, mockable interface instead of calling
/// `FirebaseAuth.instance` directly. No vendor type (`fb.User`,
/// `fb.UserCredential`) crosses this boundary — only [FirebaseAuthResult],
/// so the rest of the app never depends on the `firebase_auth` package
/// directly either.
abstract interface class FirebaseAuthClient {
  /// Starts phone verification for [phoneNumber] (already normalized to
  /// `+905XXXXXXXXX`). Resolves with an opaque `verificationId` once the
  /// backend has sent (or, against the Auth Emulator, simulated) the SMS
  /// challenge. Throws [FirebaseAuthClientException] if the backend rejects
  /// the request outright (malformed number, quota exceeded, etc).
  Future<String> verifyPhoneNumber(String phoneNumber);

  /// Confirms [smsCode] against the challenge identified by
  /// [verificationId] and completes the sign-in. Throws
  /// [FirebaseAuthClientException] on an invalid/expired code.
  Future<FirebaseAuthResult> confirmSmsCode({
    required String verificationId,
    required String smsCode,
  });

  Future<void> signOut();
}

/// The narrow, vendor-free shape of a successful sign-in — just the
/// canonical identity [FirebaseAuthRepository] needs to build an
/// [AuthSession] (see `../../domain/models/auth_session.dart`).
class FirebaseAuthResult {
  final String uid;
  final String? phoneNumber;

  const FirebaseAuthResult({required this.uid, this.phoneNumber});
}

/// Thrown by [FirebaseAuthClient] instead of leaking a raw
/// `fb.FirebaseAuthException` past this boundary. [code] mirrors
/// `FirebaseAuthException.code` values (`invalid-verification-code`,
/// `session-expired`, `too-many-requests`, ...) so
/// [FirebaseAuthRepository] can branch on the same vocabulary
/// `ErrorMapper._mapFirebaseAuthError` already understands.
class FirebaseAuthClientException implements Exception {
  final String code;
  final String message;

  const FirebaseAuthClientException(this.code, this.message);

  @override
  String toString() => 'FirebaseAuthClientException($code): $message';
}

/// The real implementation, wrapping [fb.FirebaseAuth.instance].
///
/// Deliberate scope limitation: Android's silent auto-retrieval path
/// (`verificationCompleted` firing before the user ever sees a code entry
/// screen) is intentionally not special-cased into an "instant sign-in" —
/// this app's flow always shows an OTP screen regardless of platform, so
/// auto-retrieval would only be a UX nicety (pre-filling the code), not a
/// correctness requirement. If it fires, this client currently ignores it
/// and lets the explicit [confirmSmsCode] call the user makes complete the
/// sign-in as normal; documented here, not silently dropped.
class DefaultFirebaseAuthClient implements FirebaseAuthClient {
  DefaultFirebaseAuthClient({fb.FirebaseAuth? auth}) : _providedAuth = auth;

  // Resolved lazily, not in the constructor — mirrors
  // `_DefaultCrashlyticsClient`'s exact reasoning
  // (`core/services/crash_reporting/firebase_crashlytics_service.dart`):
  // `fb.FirebaseAuth.instance` throws if no real Firebase app exists yet,
  // and a test that overrides `firebaseReadyProvider` to `true` without a
  // real Firebase app (proving the provider *wiring*, not the real SDK)
  // would otherwise crash at construction rather than at first real use.
  final fb.FirebaseAuth? _providedAuth;
  fb.FirebaseAuth get _auth => _providedAuth ?? fb.FirebaseAuth.instance;

  @override
  Future<String> verifyPhoneNumber(String phoneNumber) {
    final completer = Completer<String>();
    // 2026-10-28 — `verifyPhoneNumber`'s own returned `Future<void>` was
    // never awaited/caught here: on a platform where the native
    // implementation rejects before ever invoking ANY of the three
    // callbacks below (confirmed directly on Windows desktop —
    // `[firebase_auth/unimplemented] VerifyPhoneNumber is not available
    // on this platform yet`, thrown synchronously, not via
    // `verificationFailed`), `completer.future` never completed at all —
    // a permanent hang (the real cause of "ekranda kilitlenip kalıyor"),
    // not just an unhandled-exception log line. `.catchError` below makes
    // any such early rejection resolve the SAME completer the same way
    // `verificationFailed` already does, so every caller already handles
    // it (`StaffAuthRepository.startPhoneSignIn` -> `StaffAuthUnavailableException`
    // -> a visible Turkish error message, never a stuck spinner).
    _auth
        .verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (_) {
        // See class doc comment — deliberately not wired to an instant
        // sign-in; the explicit confirmSmsCode call still completes it.
      },
      verificationFailed: (error) {
        if (!completer.isCompleted) {
          completer.completeError(
            FirebaseAuthClientException(
              error.code,
              error.message ?? error.code,
            ),
          );
        }
      },
      codeSent: (verificationId, _) {
        if (!completer.isCompleted) {
          completer.complete(verificationId);
        }
      },
      codeAutoRetrievalTimeout: (_) {},
    )
        .catchError((Object error) {
      if (!completer.isCompleted) {
        final code = error is fb.FirebaseAuthException ? error.code : 'unknown';
        final message = error is fb.FirebaseAuthException
            ? (error.message ?? error.code)
            : error.toString();
        completer.completeError(FirebaseAuthClientException(code, message));
      }
    });
    return completer.future;
  }

  @override
  Future<FirebaseAuthResult> confirmSmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = fb.PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    try {
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) {
        throw const FirebaseAuthClientException(
          'user-not-found',
          'Sign-in did not return a user.',
        );
      }
      return FirebaseAuthResult(uid: user.uid, phoneNumber: user.phoneNumber);
    } on fb.FirebaseAuthException catch (error) {
      throw FirebaseAuthClientException(
          error.code, error.message ?? error.code);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
