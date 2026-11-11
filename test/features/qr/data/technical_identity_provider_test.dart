import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/qr/data/technical_identity_provider.dart';

/// 2026-11-11 — the browser kept an anonymous guest the auth backend no
/// longer knew, so every QR table entry failed before reaching the server
/// ("Masa açılırken bir sorun oluştu"). These tests pin the recovery rules
/// of [ensureValidTechnicalIdentity] without a real Firebase app.
class _FakeAuth {
  _FakeAuth({this.user, this.reloadError});

  ({String uid, bool isAnonymous})? user;
  Object? reloadError;
  int reloadCount = 0;
  int signOutCount = 0;
  int anonymousSignInCount = 0;

  Future<String> ensure() => ensureValidTechnicalIdentity(
        currentUser: () => user,
        reloadCurrentUser: () async {
          reloadCount += 1;
          final error = reloadError;
          if (error != null) throw error;
        },
        signOut: () async {
          signOutCount += 1;
          user = null;
        },
        signInAnonymously: () async {
          anonymousSignInCount += 1;
          final uid = 'fresh-anon-$anonymousSignInCount';
          user = (uid: uid, isAnonymous: true);
          return uid;
        },
      );
}

void main() {
  test('nobody signed in: signs in anonymously', () async {
    final auth = _FakeAuth();

    expect(await auth.ensure(), 'fresh-anon-1');
    expect(auth.anonymousSignInCount, 1);
    expect(auth.reloadCount, 0);
  });

  test('a valid cached anonymous guest is checked and reused', () async {
    final auth = _FakeAuth(user: (uid: 'anon-old', isAnonymous: true));

    expect(await auth.ensure(), 'anon-old');
    expect(auth.reloadCount, 1);
    expect(auth.signOutCount, 0);
    expect(auth.anonymousSignInCount, 0);
  });

  for (final code in [
    'user-not-found',
    'user-token-expired',
    'invalid-user-token',
  ]) {
    test(
        'a cached anonymous guest the backend no longer knows ($code) is '
        'signed out and replaced by a fresh anonymous guest', () async {
      final auth = _FakeAuth(
        user: (uid: 'anon-deleted', isAnonymous: true),
        reloadError: fb.FirebaseAuthException(code: code),
      );

      expect(await auth.ensure(), 'fresh-anon-1');
      expect(auth.signOutCount, 1);
      expect(auth.anonymousSignInCount, 1);
    });
  }

  test(
      'a DISABLED anonymous guest is not silently replaced — a deliberate '
      'block must not be bypassed with a new identity', () async {
    final auth = _FakeAuth(
      user: (uid: 'anon-blocked', isAnonymous: true),
      reloadError: fb.FirebaseAuthException(code: 'user-disabled'),
    );

    await expectLater(auth.ensure(), throwsA(isA<fb.FirebaseAuthException>()));
    expect(auth.signOutCount, 0);
    expect(auth.anonymousSignInCount, 0);
  });

  test('a network failure while checking is rethrown, nothing signed out',
      () async {
    final auth = _FakeAuth(
      user: (uid: 'anon-old', isAnonymous: true),
      reloadError: fb.FirebaseAuthException(code: 'network-request-failed'),
    );

    await expectLater(auth.ensure(), throwsA(isA<fb.FirebaseAuthException>()));
    expect(auth.signOutCount, 0);
    expect(auth.anonymousSignInCount, 0);
  });

  test(
      'a real (non-anonymous) customer is reused as-is: never checked, never '
      'signed out', () async {
    final auth = _FakeAuth(
      user: (uid: 'customer-1', isAnonymous: false),
      reloadError: fb.FirebaseAuthException(code: 'user-not-found'),
    );

    expect(await auth.ensure(), 'customer-1');
    expect(auth.reloadCount, 0);
    expect(auth.signOutCount, 0);
    expect(auth.anonymousSignInCount, 0);
  });
}
