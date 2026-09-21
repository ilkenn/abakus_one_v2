import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:abakus_one_v2/core/services/functions/rest_callable_client.dart';

/// Covers `RestCallableClient`'s own Dart-side logic (request construction,
/// response parsing, error wrapping) via an injected `MockClient` and a
/// fake `idTokenProvider` — no real `firebase_auth`/`cloud_functions` SDK
/// involved, matching this codebase's established constraint that those
/// are unavailable under `flutter test`. This is the Windows-desktop
/// bridge for `getPosBranchTableOverview`/`getPosTableOperationalView`/
/// the trusted-device callables (PC Yönetici İnceleme Modu, 2026-09-20).
void main() {
  test('a successful response returns the parsed result map', () async {
    final mockClient = MockClient((request) async {
      return http.Response('{"result":{"tables":[],"version":"v1"}}', 200);
    });
    final client = RestCallableClient(
      httpClient: mockClient,
      idTokenProvider: () async => 'fake-id-token',
    );

    final result = await client.call('getPosBranchTableOverview', {
      'organizationId': 'org-1',
    });

    expect(result, {'tables': [], 'version': 'v1'});
  });

  test('a successful response with no result field returns an empty map',
      () async {
    final mockClient = MockClient((request) async {
      return http.Response('{}', 200);
    });
    final client = RestCallableClient(
      httpClient: mockClient,
      idTokenProvider: () async => 'fake-id-token',
    );

    final result = await client.call('someCallable', const {});

    expect(result, isEmpty);
  });

  test(
      'an error response throws RestCallableException with the server\'s '
      'status (lower-cased) and message', () async {
    final mockClient = MockClient((request) async {
      return http.Response(
        '{"error":{"status":"PERMISSION_DENIED","message":"nope"}}',
        403,
      );
    });
    final client = RestCallableClient(
      httpClient: mockClient,
      idTokenProvider: () async => 'fake-id-token',
    );

    await expectLater(
      client.call('getPosBranchTableOverview', const {}),
      throwsA(isA<RestCallableException>()
          .having((e) => e.code, 'code', 'permission_denied')
          .having((e) => e.message, 'message', 'nope')),
    );
  });

  test(
      'a non-2xx response with no parseable error body still throws '
      'RestCallableException, never a raw exception', () async {
    final mockClient = MockClient((request) async {
      return http.Response('Internal Server Error', 500);
    });
    final client = RestCallableClient(
      httpClient: mockClient,
      idTokenProvider: () async => 'fake-id-token',
    );

    await expectLater(
      client.call('getPosBranchTableOverview', const {}),
      throwsA(isA<RestCallableException>()),
    );
  });

  test(
      'no signed-in user (idTokenProvider returns null) throws '
      'RestCallableException with code "unauthenticated", never makes a '
      'network call', () async {
    var callCount = 0;
    final mockClient = MockClient((request) async {
      callCount++;
      return http.Response('{}', 200);
    });
    final client = RestCallableClient(
      httpClient: mockClient,
      idTokenProvider: () async => null,
    );

    await expectLater(
      client.call('getPosBranchTableOverview', const {}),
      throwsA(isA<RestCallableException>()
          .having((e) => e.code, 'code', 'unauthenticated')),
    );
    expect(callCount, 0,
        reason: 'must fail before attempting the HTTP request at all');
  });

  test(
      'a transport-level failure (e.g. connection refused — emulator not '
      'running) is wrapped, not left raw', () async {
    final mockClient = MockClient((request) async {
      throw Exception('Connection refused');
    });
    final client = RestCallableClient(
      httpClient: mockClient,
      idTokenProvider: () async => 'fake-id-token',
    );

    await expectLater(
      client.call('getPosBranchTableOverview', const {}),
      throwsA(isA<RestCallableException>()),
    );
  });

  test(
      'posts to the callable-functions HTTP protocol URL/shape: '
      'host:port/projectId/us-central1/name, Bearer header, {"data": ...} body',
      () async {
    http.Request? captured;
    final mockClient = MockClient((request) async {
      captured = request;
      return http.Response('{"result":{}}', 200);
    });
    final client = RestCallableClient(
      httpClient: mockClient,
      idTokenProvider: () async => 'fake-id-token',
    );

    await client.call('getPosBranchTableOverview', {
      'organizationId': 'org-1',
      'branchId': 'branch-1',
    });

    expect(captured, isNotNull);
    expect(captured!.method, 'POST');
    expect(captured!.url.host, '127.0.0.1');
    expect(captured!.url.port, 5001);
    expect(
      captured!.url.path,
      // AppEnvironmentConfig.current resolves to `development` by default
      // under `flutter test` (no ENVIRONMENT dart-define set) ->
      // 'abakus-one-dev'.
      '/abakus-one-dev/us-central1/getPosBranchTableOverview',
    );
    expect(captured!.headers['Authorization'], 'Bearer fake-id-token');
    expect(captured!.headers['Content-Type'], 'application/json');
    expect(
      captured!.body,
      '{"data":{"organizationId":"org-1","branchId":"branch-1"}}',
    );
  });

  test('the default constructor (no injections) still constructs cleanly',
      () {
    final client = RestCallableClient();
    expect(client, isA<RestCallableClient>());
  });
}
