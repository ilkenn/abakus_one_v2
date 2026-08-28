import 'dart:async';

import 'package:abakus_one_v2/core/services/auth/email_password_auth_client.dart';

/// A deterministic, in-memory [EmailPasswordAuthClient] fake — no real
/// Firebase SDK involved. [createAccount] mints a stable, predictable uid
/// from [email] so tests can assert on it without needing real Firebase
/// Auth Emulator connectivity.
class FakeEmailPasswordAuthClient implements EmailPasswordAuthClient {
  FakeEmailPasswordAuthClient({this.neverResolvesSignIn = false});

  final Map<String, String> _passwordsByEmail = {};
  final Map<String, String> _uidsByEmail = {};
  int _nextUid = 1;

  /// Simulates a `signInWithEmailAndPassword` call whose underlying
  /// JS-interop promise never settles — the real-world condition
  /// `staff_auth_repository.dart`'s own network timeout exists to bound.
  final bool neverResolvesSignIn;

  @override
  Future<EmailPasswordAuthResult> createAccount({
    required String email,
    required String password,
  }) async {
    final uid = 'fake-uid-${_nextUid++}';
    _passwordsByEmail[email] = password;
    _uidsByEmail[email] = uid;
    return EmailPasswordAuthResult(uid: uid, email: email);
  }

  @override
  Future<EmailPasswordAuthResult> signIn({
    required String email,
    required String password,
  }) async {
    if (neverResolvesSignIn) return Completer<EmailPasswordAuthResult>().future;
    final uid = _uidsByEmail[email];
    if (uid == null || _passwordsByEmail[email] != password) {
      throw const EmailPasswordAuthClientException(
        'invalid-credential',
        'Invalid email or password.',
      );
    }
    return EmailPasswordAuthResult(uid: uid, email: email);
  }

  @override
  Future<void> signOut() async {}
}
