import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:abakus_one_v2/bootstrap/app_environment.dart';
import 'package:abakus_one_v2/core/services/auth/identity_toolkit_rest_auth_client.dart';

/// Covers `DefaultIdentityToolkitRestAuthClient`'s own Dart-side logic
/// (request construction, response parsing, error-code mapping) via an
/// injected `MockClient` — no real `firebase_auth` SDK involved, mirroring
/// `rest_callable_client_test.dart`'s own established pattern for the
/// identical reason (unavailable under `flutter test`). This is the
/// Windows-desktop sign-in bridge (2026-10-30) — see that class's own doc
/// comment for the full root-cause/limitation writeup.
void main() {
  group('DefaultIdentityToolkitRestAuthClient.signInWithPassword', () {
    test('a successful response parses idToken/refreshToken/localId/expiresAt',
        () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, 'identitytoolkit.googleapis.com');
        expect(request.url.path, '/v1/accounts:signInWithPassword');
        return http.Response(
          '{"idToken":"id-1","refreshToken":"refresh-1","localId":"uid-1",'
          '"expiresIn":"3600"}',
          200,
        );
      });
      final client = DefaultIdentityToolkitRestAuthClient(
        httpClient: mockClient,
        environmentOverride: AppEnvironment.staging,
      );

      final tokens = await client.signInWithPassword(
        email: 'a@abakus.test',
        password: 'pw',
      );

      expect(tokens.idToken, 'id-1');
      expect(tokens.refreshToken, 'refresh-1');
      expect(tokens.localId, 'uid-1');
      expect(
        tokens.expiresAt
            .isAfter(DateTime.now().add(const Duration(minutes: 59))),
        isTrue,
      );
    });

    test(
        'INVALID_PASSWORD maps to the firebase_auth-style "wrong-password" code',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          '{"error":{"message":"INVALID_PASSWORD"}}',
          400,
        );
      });
      final client = DefaultIdentityToolkitRestAuthClient(
        httpClient: mockClient,
        environmentOverride: AppEnvironment.staging,
      );

      await expectLater(
        () => client.signInWithPassword(
            email: 'a@abakus.test', password: 'wrong'),
        throwsA(isA<IdentityToolkitAuthException>()
            .having((e) => e.code, 'code', 'wrong-password')),
      );
    });

    test('EMAIL_NOT_FOUND maps to "user-not-found"', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"error":{"message":"EMAIL_NOT_FOUND"}}', 400);
      });
      final client = DefaultIdentityToolkitRestAuthClient(
        httpClient: mockClient,
        environmentOverride: AppEnvironment.staging,
      );

      await expectLater(
        () => client.signInWithPassword(email: 'x@abakus.test', password: 'pw'),
        throwsA(isA<IdentityToolkitAuthException>()
            .having((e) => e.code, 'code', 'user-not-found')),
      );
    });

    test('a transport-level failure is wrapped, never left raw', () async {
      final mockClient = MockClient((request) async {
        throw Exception('connection refused');
      });
      final client = DefaultIdentityToolkitRestAuthClient(
        httpClient: mockClient,
        environmentOverride: AppEnvironment.staging,
      );

      await expectLater(
        () => client.signInWithPassword(email: 'a@abakus.test', password: 'pw'),
        throwsA(isA<IdentityToolkitAuthException>()),
      );
    });

    test('against development, targets the local Auth Emulator host/path',
        () async {
      final mockClient = MockClient((request) async {
        expect(request.url.scheme, 'http');
        expect(request.url.path,
            '/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword');
        return http.Response(
          '{"idToken":"id-1","refreshToken":"refresh-1","localId":"uid-1",'
          '"expiresIn":"3600"}',
          200,
        );
      });
      final client = DefaultIdentityToolkitRestAuthClient(
        httpClient: mockClient,
        environmentOverride: AppEnvironment.development,
      );

      await client.signInWithPassword(email: 'a@abakus.test', password: 'pw');
    });
  });

  group('DefaultIdentityToolkitRestAuthClient.refresh', () {
    test('parses the Secure Token API\'s snake_case response shape', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, 'securetoken.googleapis.com');
        return http.Response(
          '{"id_token":"id-2","refresh_token":"refresh-2","user_id":"uid-1",'
          '"expires_in":"3600"}',
          200,
        );
      });
      final client = DefaultIdentityToolkitRestAuthClient(
        httpClient: mockClient,
        environmentOverride: AppEnvironment.staging,
      );

      final tokens = await client.refresh('refresh-1');

      expect(tokens.idToken, 'id-2');
      expect(tokens.refreshToken, 'refresh-2');
      expect(tokens.localId, 'uid-1');
    });

    test('an expired/invalid refresh token throws, not a generic failure',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          '{"error":{"message":"INVALID_REFRESH_TOKEN"}}',
          400,
        );
      });
      final client = DefaultIdentityToolkitRestAuthClient(
        httpClient: mockClient,
        environmentOverride: AppEnvironment.staging,
      );

      await expectLater(
        () => client.refresh('stale'),
        throwsA(isA<IdentityToolkitAuthException>()),
      );
    });
  });
}
