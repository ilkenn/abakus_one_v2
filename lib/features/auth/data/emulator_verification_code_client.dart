import 'dart:convert';
import 'dart:io';

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

/// The real implementation — raw `dart:io` HTTP rather than adding a new
/// `http`/`dio` package dependency for one dev-only GET request (this
/// codebase has neither today; `CLAUDE.md` §2's "never add a dependency
/// without a recorded reason" applies).
class HttpEmulatorVerificationCodeClient
    implements EmulatorVerificationCodeClient {
  const HttpEmulatorVerificationCodeClient();

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

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) {
        throw EmulatorVerificationCodeException(
          'Auth Emulator "$uri" returned HTTP ${response.statusCode} — is '
          'it running?',
        );
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
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
      client.close(force: true);
    }
  }
}
