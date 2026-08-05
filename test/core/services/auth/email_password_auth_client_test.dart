import 'package:abakus_one_v2/core/services/auth/email_password_auth_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_email_password_auth_client.dart';

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
}
