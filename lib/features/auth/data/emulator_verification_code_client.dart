import 'dart:convert';

import 'package:http/http.dart' as http;

/// Reads a phone-verification SMS code back out of the local Firebase Auth
/// Emulator's own debug REST endpoint (`GET /emulator/v1/projects/
/// {projectId}/verificationCodes`) — the piece that makes "Hızlı Test
/// Girişi" possible: the emulator never sends a real SMS, it only records
/// the code it *would* have sent, retrievable only through this
/// undocumented-to-production, emulator-only endpoint. Never used, and
/// structurally unreachable, outside `QuickTestLoginConfig.isAvailable`
/// (development + emulator only) — see that class's own doc comment.
///
/// No production/staging code path ever constructs or calls this — it has
/// no relationship to `FirebaseAuthClient`/`FirebaseAuthRepository`'s own
/// real phone-verification calls, which remain completely untouched.
abstract interface class EmulatorVerificationCodeClient {
  /// The most recently issued verification code for [phoneNumber] (already
  /// normalized, `+905XXXXXXXXX`), or `null` if the emulator has no
  /// matching entry at all — never a fabricated/fallback code. Throws
  /// [EmulatorVerificationCodeException] if the emulator itself can't be
  /// reached or returns an unexpected shape; callers must treat that as a
  /// hard failure, never as "no code, try a default."
  Future<String?> fetchLatestCode({
    required String host,
    required int port,
    required String projectId,
    required String phoneNumber,
  });
}

class EmulatorVerificationCodeException implements Exception {
  const EmulatorVerificationCodeException(this.message);

  final String message;

  @override
  String toString() => 'EmulatorVerificationCodeException: $message';
}

/// The real implementation — `package:http` rather than `dart:io`'s
/// `HttpClient`. **This is a fix, not a stylistic swap**: `dart:io` has no
/// working HTTP implementation on Flutter Web — it compiles (a stub
/// exists), but calling it throws `Unsupported operation:
/// Platform._version` at runtime the moment "Hızlı Test Girişi" is used in
/// Chrome. `package:http`'s `Client()` factory already dispatches to a
/// genuinely working platform-specific transport internally (`BrowserClient`
/// on web via `fetch`, an `IOClient` elsewhere) — this file needs no
/// conditional-import/stub-file split of its own; the package already does
/// that once, correctly, for every consumer. `http` was already present in
/// this repo's resolved dependency graph as a transitive dependency of
/// existing Firebase plugins (`pubspec.lock`, unpinned) — promoted to a
/// direct `pubspec.yaml` dependency for this file to import it explicitly,
/// with zero change to the resolved version.
///
/// [client] is an optional injection point purely for testing (via
/// `package:http/testing.dart`'s `MockClient` — no additional package
/// dependency, it ships inside `http` itself) — real call sites always use
/// the default, which lazily creates (and closes) a fresh `http.Client()`
/// per call, matching the previous per-call-client lifecycle exactly.
class HttpEmulatorVerificationCodeClient
    implements EmulatorVerificationCodeClient {
  const HttpEmulatorVerificationCodeClient({http.Client? client})
      : _injectedClient = client;

  final http.Client? _injectedClient;

  static const _timeout = Duration(seconds: 5);

  @override
  Future<String?> fetchLatestCode({
    required String host,
    required int port,
    required String projectId,
    required String phoneNumber,
  }) async {
    final uri = Uri.http(
      '$host:$port',
      '/emulator/v1/projects/$projectId/verificationCodes',
    );

    final client = _injectedClient ?? http.Client();
    try {
      final response = await client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        throw EmulatorVerificationCodeException(
          'Auth Emulator "$uri" returned HTTP ${response.statusCode} — is '
          'it running?',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const EmulatorVerificationCodeException(
          'Auth Emulator returned an unexpected response shape.',
        );
      }

      final rawCodes = decoded['verificationCodes'];
      if (rawCodes is! List) return null;

      // "Latest" — the last entry matching [phoneNumber] in the emulator's
      // own list, which it appends to in issuance order. Never a random
      // pick among matches.
      String? latestCode;
      for (final entry in rawCodes) {
        if (entry is! Map) continue;
        if (entry['phoneNumber'] != phoneNumber) continue;
        final code = entry['code'];
        if (code is String && code.isNotEmpty) latestCode = code;
      }
      return latestCode;
    } on EmulatorVerificationCodeException {
      rethrow;
    } catch (error) {
      throw EmulatorVerificationCodeException(
        'Could not reach the Auth Emulator at "$uri": $error',
      );
    } finally {
      // Never close a client this instance did not itself create — a
      // caller-injected client (real or `MockClient`) outlives this call
      // and its lifecycle belongs to whoever constructed it.
      if (_injectedClient == null) client.close();
    }
  }
}
