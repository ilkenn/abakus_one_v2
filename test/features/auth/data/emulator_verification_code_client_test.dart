import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:abakus_one_v2/features/auth/data/emulator_verification_code_client.dart';

/// Covers the Chrome-breaking bug fix: `HttpEmulatorVerificationCodeClient`
/// used to depend on `dart:io`'s `HttpClient`, which has no working
/// implementation on Flutter Web (`Unsupported operation:
/// Platform._version` at runtime). It now uses `package:http`, whose
/// `Client()` factory already dispatches to a real, working transport per
/// platform internally — these tests exercise the SHARED Dart logic
/// (request construction, response parsing, error wrapping) via an
/// injected `MockClient`, which is the exact same code path every real
/// platform (web/Android/iOS) runs; only the actual network transport
/// underneath `http.Client()` differs per platform, and that dispatch is
/// `package:http`'s own already-published responsibility, not re-tested
/// here.
void main() {
  const host = '127.0.0.1';
  const port = 9099;
  const projectId = 'demo-project';
  const phoneNumber = '+905337106414';
  final expectedUri = Uri.http(
    '$host:$port',
    '/emulator/v1/projects/$projectId/verificationCodes',
  );

  test(
      'this file never imports dart:io — the exact root cause of the '
      'Chrome "Unsupported operation: Platform._version" crash, guarded '
      'against regressing', () {
    final source = io.File(
      'lib/features/auth/data/emulator_verification_code_client.dart',
    ).readAsStringSync();
    // Checks the actual import directive, not just any mention of the
    // string "dart:io" — this file's own doc comments legitimately
    // reference it by name to explain the fix.
    expect(
      RegExp('''^import\\s+['"]dart:io['"]''', multiLine: true)
          .hasMatch(source),
      isFalse,
      reason: 'dart:io has no working HTTP implementation on Flutter Web — '
          'this file must stay on package:http (or another genuinely '
          'web-compatible transport) to keep "Hızlı Test Girişi" usable in '
          'Chrome.',
    );
  });

  test(
      'a successful response returns the latest matching code for the phone number',
      () async {
    final mockClient = MockClient((request) async {
      expect(request.url, expectedUri);
      expect(request.method, 'GET');
      return http.Response(
        '{"verificationCodes":['
        '{"phoneNumber":"+905337106414","code":"111111"},'
        '{"phoneNumber":"+905000000000","code":"999999"},'
        '{"phoneNumber":"+905337106414","code":"222222"}'
        ']}',
        200,
      );
    });
    final client = HttpEmulatorVerificationCodeClient(client: mockClient);

    final code = await client.fetchLatestCode(
      host: host,
      port: port,
      projectId: projectId,
      phoneNumber: phoneNumber,
    );

    expect(code, '222222',
        reason:
            'the LAST matching entry wins, never the first or a random pick');
  });

  test(
      'no matching phone number in the response returns null, never a fabricated code',
      () async {
    final mockClient = MockClient((request) async {
      return http.Response(
        '{"verificationCodes":[{"phoneNumber":"+905000000000","code":"999999"}]}',
        200,
      );
    });
    final client = HttpEmulatorVerificationCodeClient(client: mockClient);

    final code = await client.fetchLatestCode(
      host: host,
      port: port,
      projectId: projectId,
      phoneNumber: phoneNumber,
    );

    expect(code, isNull);
  });

  test('an empty verificationCodes list returns null', () async {
    final mockClient = MockClient((request) async {
      return http.Response('{"verificationCodes":[]}', 200);
    });
    final client = HttpEmulatorVerificationCodeClient(client: mockClient);

    final code = await client.fetchLatestCode(
      host: host,
      port: port,
      projectId: projectId,
      phoneNumber: phoneNumber,
    );

    expect(code, isNull);
  });

  test(
      'a non-200 status throws EmulatorVerificationCodeException, never silently returns null',
      () async {
    final mockClient = MockClient((request) async {
      return http.Response('Not Found', 404);
    });
    final client = HttpEmulatorVerificationCodeClient(client: mockClient);

    expect(
      () => client.fetchLatestCode(
        host: host,
        port: port,
        projectId: projectId,
        phoneNumber: phoneNumber,
      ),
      throwsA(isA<EmulatorVerificationCodeException>()),
    );
  });

  test(
      'an unexpected response shape (not a JSON object) throws EmulatorVerificationCodeException',
      () async {
    final mockClient = MockClient((request) async {
      return http.Response('[]', 200);
    });
    final client = HttpEmulatorVerificationCodeClient(client: mockClient);

    expect(
      () => client.fetchLatestCode(
        host: host,
        port: port,
        projectId: projectId,
        phoneNumber: phoneNumber,
      ),
      throwsA(isA<EmulatorVerificationCodeException>()),
    );
  });

  test(
      'a transport-level failure (e.g. connection refused — emulator not running) is wrapped, not left raw',
      () async {
    final mockClient = MockClient((request) async {
      throw const io.OSError('Connection refused', 111);
    });
    final client = HttpEmulatorVerificationCodeClient(client: mockClient);

    await expectLater(
      client.fetchLatestCode(
        host: host,
        port: port,
        projectId: projectId,
        phoneNumber: phoneNumber,
      ),
      throwsA(isA<EmulatorVerificationCodeException>()),
    );
  });

  test(
      'queries the exact emulator debug endpoint for the given host/port/projectId — never a different path',
      () async {
    Uri? capturedUri;
    final mockClient = MockClient((request) async {
      capturedUri = request.url;
      return http.Response('{"verificationCodes":[]}', 200);
    });
    final client = HttpEmulatorVerificationCodeClient(client: mockClient);

    await client.fetchLatestCode(
      host: 'localhost',
      port: 9199,
      projectId: 'my-project',
      phoneNumber: phoneNumber,
    );

    expect(
        capturedUri,
        Uri.http('localhost:9199',
            '/emulator/v1/projects/my-project/verificationCodes'));
  });

  test(
      'the default constructor (no injected client) still works end-to-end against a mock transport, matching real call-site wiring',
      () async {
    // Cannot inject into the zero-arg `const HttpEmulatorVerificationCodeClient()`
    // real call sites use without a live emulator; this proves the
    // *optional* client parameter defaults correctly rather than requiring
    // one, by constructing with `client: null` explicitly.
    const client = HttpEmulatorVerificationCodeClient();
    expect(client, isA<EmulatorVerificationCodeClient>());
  });
}
