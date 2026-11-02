import 'package:abakus_one_v2/core/services/auth/email_password_auth_client.dart';
import 'package:abakus_one_v2/core/services/auth/identity_toolkit_rest_auth_client.dart';
import 'package:abakus_one_v2/core/services/auth/windows_rest_auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_email_password_auth_client.dart';

class _FakeIdentityToolkitRestAuthClient
    implements IdentityToolkitRestAuthClient {
  _FakeIdentityToolkitRestAuthClient({this.signInError});

  IdentityToolkitAuthException? signInError;
  int signInCallCount = 0;

  @override
  Future<RestAuthTokens> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signInCallCount += 1;
    if (signInError != null) throw signInError!;
    return RestAuthTokens(
      idToken: 'id-$signInCallCount',
      refreshToken: 'refresh-1',
      localId: 'uid-1',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<RestAuthTokens> createAccount({
    required String email,
    required String password,
  }) async {
    return RestAuthTokens(
      idToken: 'id-signup',
      refreshToken: 'refresh-1',
      localId: 'uid-1',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<RestAuthTokens> refresh(String refreshToken) =>
      throw UnimplementedError();
}

void main() {
  group('FakeEmailPasswordAuthClient (test-support sanity)', () {
    test(
        'createAccount then signIn with the same credential succeeds and '
        'returns the same uid', () async {
      final client = FakeEmailPasswordAuthClient();

      final created = await client.createAccount(
        email: 'owner@abakus.test',
        password: 'S3curePass!',
      );
      final signedIn = await client.signIn(
        email: 'owner@abakus.test',
        password: 'S3curePass!',
      );

      expect(signedIn.uid, created.uid);
    });

    test('signIn with the wrong password throws', () async {
      final client = FakeEmailPasswordAuthClient();
      await client.createAccount(
        email: 'owner@abakus.test',
        password: 'S3curePass!',
      );

      await expectLater(
        client.signIn(email: 'owner@abakus.test', password: 'wrong'),
        throwsA(isA<EmailPasswordAuthClientException>()),
      );
    });

    test('signIn for an email with no account throws', () async {
      final client = FakeEmailPasswordAuthClient();

      await expectLater(
        client.signIn(email: 'nobody@abakus.test', password: 'anything'),
        throwsA(isA<EmailPasswordAuthClientException>()),
      );
    });

    test('two different accounts get two different uids', () async {
      final client = FakeEmailPasswordAuthClient();

      final a = await client.createAccount(
          email: 'a@abakus.test', password: 'S3curePass!');
      final b = await client.createAccount(
          email: 'b@abakus.test', password: 'S3curePass!');

      expect(a.uid, isNot(b.uid));
    });
  });

  // 2026-10-30 — the Windows sign-in-hang fix.
  group('RestEmailPasswordAuthClient', () {
    setUp(() => WindowsRestAuthSession.clear());
    tearDown(() => WindowsRestAuthSession.clear());

    test(
        'signIn returns a result built from the REST tokens and populates '
        'WindowsRestAuthSession', () async {
      final restClient = _FakeIdentityToolkitRestAuthClient();
      final client = RestEmailPasswordAuthClient(
        restClient: restClient,
        // Never touches the real `firebase_auth` SDK under `flutter test`.
        attemptNativeSignInInBackground: false,
      );

      final result =
          await client.signIn(email: 'a@abakus.test', password: 'pw');

      expect(result.uid, 'uid-1');
      expect(result.email, 'a@abakus.test');
      expect(WindowsRestAuthSession.isActive, isTrue);
      expect(WindowsRestAuthSession.uid, 'uid-1');
    });

    test(
        'a rejected credential throws EmailPasswordAuthClientException, '
        'the same type every existing caller already handles', () async {
      final restClient = _FakeIdentityToolkitRestAuthClient(
        signInError:
            const IdentityToolkitAuthException('wrong-password', 'nope'),
      );
      final client = RestEmailPasswordAuthClient(
        restClient: restClient,
        attemptNativeSignInInBackground: false,
      );

      await expectLater(
        client.signIn(email: 'a@abakus.test', password: 'wrong'),
        throwsA(isA<EmailPasswordAuthClientException>()
            .having((e) => e.code, 'code', 'wrong-password')),
      );
      expect(WindowsRestAuthSession.isActive, isFalse);
    });

    test('signOut clears WindowsRestAuthSession', () async {
      final restClient = _FakeIdentityToolkitRestAuthClient();
      final client = RestEmailPasswordAuthClient(
        restClient: restClient,
        attemptNativeSignInInBackground: false,
      );
      await client.signIn(email: 'a@abakus.test', password: 'pw');
      expect(WindowsRestAuthSession.isActive, isTrue);

      await client.signOut();

      expect(WindowsRestAuthSession.isActive, isFalse);
    });
  });
}
