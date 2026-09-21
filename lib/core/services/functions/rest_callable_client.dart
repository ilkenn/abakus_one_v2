import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:http/http.dart' as http;

import '../../../bootstrap/firebase_functions_emulator_config.dart';
import '../../config/app_environment_config.dart';

/// Thrown for any REST-callable failure — a non-2xx HTTP response with a
/// parseable Firebase-callable error body, or the request/response
/// plumbing itself failing (network error, unexpected shape). [code]
/// mirrors `FirebaseFunctionsException.code` values where the server
/// supplied one (`error.status`, lower-cased, e.g. `'permission-denied'`),
/// falling back to `'unknown'` — the same vocabulary every existing
/// `_rethrow(FirebaseFunctionsException)` helper in this codebase already
/// expects, so a caller can normalize this into its own gateway-specific
/// exception type without inventing a second vocabulary.
class RestCallableException implements Exception {
  const RestCallableException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'RestCallableException($code): $message';
}

/// Calls a Cloud Functions "callable" endpoint via plain HTTP, bypassing
/// `cloud_functions`'s native plugin entirely — **the** workaround for
/// Windows desktop, which ships no native implementation of that plugin at
/// all (confirmed absent from `windows/flutter/generated_plugin_registrant.cc`,
/// unlike `firebase_auth`/`cloud_firestore`, both present there and both
/// used by this class/its callers). Speaks the exact same wire protocol
/// `functions/scripts/seed_dev_staff.mjs`/`seed_dev_pos_showcase.mjs`'s own
/// `callCallable` helper already uses successfully against this project's
/// emulator: `POST /<projectId>/us-central1/<name>` with an
/// `Authorization: Bearer <idToken>` header and a `{"data": {...}}` body;
/// a 2xx response carries `{"result": {...}}`, anything else carries
/// `{"error": {"status": ..., "message": ...}}`.
///
/// **Only ever constructed for the Windows-desktop-plus-local-emulator
/// case** (see each call site's own `defaultTargetPlatform`/
/// `FirebaseFunctionsEmulatorConfig.shouldUseEmulator` gate) — this class
/// itself does not re-check that, it only knows how to make one HTTP call;
/// gating which platform/environment ever reaches it is the caller's job,
/// exactly like `HttpEmulatorVerificationCodeClient`'s own precedent
/// (`features/auth/data/emulator_verification_code_client.dart`).
///
/// [httpClient] is an injection point purely for testing (a
/// `package:http/testing.dart` `MockClient`) — real call sites always use
/// the default. Mirrors `HttpEmulatorVerificationCodeClient`'s exact
/// per-call-client lifecycle: a caller-injected client is never closed by
/// this class, only a self-created one.
///
/// [idTokenProvider] defaults to the real `fb.FirebaseAuth.instance
/// .currentUser?.getIdToken()` — deliberately a plain callback, not a
/// `fb.FirebaseAuth` instance, so this entire class stays unit-testable
/// with a fake token function and zero real `firebase_auth` SDK
/// involvement, matching this codebase's own established "the real SDK is
/// unavailable under `flutter test`" constraint (e.g.
/// `parseStaffAuthorizationClaims` being factored out as a top-level
/// function for the same reason, `staff_claims_sync_client.dart`).
class RestCallableClient {
  RestCallableClient({
    http.Client? httpClient,
    Future<String?> Function()? idTokenProvider,
  })  : _injectedClient = httpClient,
        _idTokenProvider = idTokenProvider ?? _defaultIdTokenProvider;

  final http.Client? _injectedClient;
  final Future<String?> Function() _idTokenProvider;

  static Future<String?> _defaultIdTokenProvider() async =>
      fb.FirebaseAuth.instance.currentUser?.getIdToken();

  static const _timeout = Duration(seconds: 20);
  static const _region = 'us-central1';

  /// Defaults to [AppEnvironmentConfig.current]'s real per-environment
  /// project id (`'abakus-one-dev'` for `development`) — matching a
  /// `firebase emulators:start --project abakus-one-dev`-style invocation,
  /// not `.firebaserc`'s bare default (`'demo-abakus-one-emulator'`, what
  /// the Node seed scripts fall back to when run standalone without
  /// `--project`, a different invocation context). Overridable via
  /// `--dart-define=FUNCTIONS_EMULATOR_PROJECT_ID=...` for a local setup
  /// that genuinely differs — no code change needed for that case.
  static const String _projectId = String.fromEnvironment(
    'FUNCTIONS_EMULATOR_PROJECT_ID',
    defaultValue: '',
  );

  static String get _resolvedProjectId => _projectId.isNotEmpty
      ? _projectId
      : AppEnvironmentConfig.current.firebaseProjectId;

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final uri = Uri.http(
      '${FirebaseFunctionsEmulatorConfig.host}:${FirebaseFunctionsEmulatorConfig.port}',
      '/$_resolvedProjectId/$_region/$name',
    );

    final idToken = await _idTokenProvider();
    if (idToken == null) {
      throw const RestCallableException(
        'unauthenticated',
        'No signed-in Firebase user to attach to this call.',
      );
    }

    final client = _injectedClient ?? http.Client();
    try {
      final response = await client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'data': data}),
          )
          .timeout(_timeout);

      final Map<String, dynamic> decoded;
      try {
        final raw = jsonDecode(response.body);
        if (raw is! Map<String, dynamic>) throw const FormatException();
        decoded = raw;
      } on FormatException {
        throw RestCallableException(
          'unknown',
          'Unexpected response shape from "$name" (HTTP ${response.statusCode}).',
        );
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final result = decoded['result'];
        if (result is Map<String, dynamic>) return result;
        if (result is Map) return Map<String, dynamic>.from(result);
        return const <String, dynamic>{};
      }

      final error = decoded['error'];
      final code = error is Map ? error['status'] as String? : null;
      final message = error is Map ? error['message'] as String? : null;
      throw RestCallableException(
        (code ?? 'unknown').toString().toLowerCase(),
        message ?? 'Call to "$name" failed (HTTP ${response.statusCode}).',
      );
    } on RestCallableException {
      rethrow;
    } catch (error) {
      throw RestCallableException(
        'unknown',
        'Could not reach the Functions Emulator at "$uri" for "$name": $error',
      );
    } finally {
      // Never close a client this instance did not itself create — see
      // this class's own doc comment.
      if (_injectedClient == null) client.close();
    }
  }
}
