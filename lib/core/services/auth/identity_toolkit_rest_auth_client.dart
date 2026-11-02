import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../bootstrap/app_environment.dart';
import '../../../bootstrap/firebase_auth_emulator_config.dart';
import '../../config/firebase_options_selector.dart';

/// One successful Identity-Toolkit sign-in/sign-up/refresh result — the
/// REST equivalent of what `fb.UserCredential`/`fb.User` carry, narrowed to
/// exactly what [WindowsRestAuthSession] needs to keep the session alive
/// and what [StaffClaimsSyncClient]/[ActorSession]-building needs to read
/// claims from.
class RestAuthTokens {
  const RestAuthTokens({
    required this.idToken,
    required this.refreshToken,
    required this.localId,
    required this.expiresAt,
  });

  final String idToken;
  final String refreshToken;
  final String localId;

  /// When [idToken] actually expires (server-reported `expiresIn`,
  /// resolved to a wall-clock instant at the moment this was minted) — see
  /// [WindowsRestAuthSession]'s own refresh-ahead-of-expiry logic.
  final DateTime expiresAt;
}

/// Mirrors [EmailPasswordAuthClientException]'s exact shape (`code`/
/// `message`) rather than reusing that type directly — this class has no
/// dependency on `firebase_auth` at all (the whole point of this bridge),
/// and `RestEmailPasswordAuthClient` is the one place that translates this
/// into the shared [EmailPasswordAuthClientException] type every existing
/// caller already handles.
class IdentityToolkitAuthException implements Exception {
  const IdentityToolkitAuthException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'IdentityToolkitAuthException($code): $message';
}

/// 2026-10-30 — the Windows fix for `firebase_auth`'s native plugin
/// hanging on `signInWithEmailAndPassword` (`[AUTH-TRACE] signIn: timeout`
/// after the full `staffAuthNetworkTimeout`, with the prior entry's own
/// preflight proving the network path to `identitytoolkit.googleapis.com`
/// itself is fine — a native-transport-specific problem, not a dead
/// network). Speaks Firebase Auth's own public REST API directly
/// (`https://identitytoolkit.googleapis.com/v1/accounts:*`,
/// `https://securetoken.googleapis.com/v1/token`) — the exact protocol the
/// native SDK itself implements under the hood, performing the exact same
/// real credential verification against the exact same real Firebase Auth
/// backend. This is **not** a bypass of authentication: a wrong password
/// is rejected by Google's own servers exactly as it would be natively;
/// only the broken Windows *transport* is replaced, the same category of
/// fix `RestCallableClient` already is for `cloud_functions`.
///
/// **Disclosed, real architectural limitation** (surfaced before this was
/// built, not hidden): the native `firebase_auth`/`cloud_firestore`
/// plugins on every platform share one underlying SDK-managed auth
/// session (`FirebaseAuth.instance.currentUser`) — there is no public API
/// to inject a REST-obtained token pair into that shared state. A handful
/// of Admin/POS repositories read Firestore *directly* via the native
/// plugin rather than through a callable (`firestore_kitchen_ticket_repository
/// .dart`, `firestore_kitchen_work_item_repository.dart`,
/// `delivery_dispatch_order_repository.dart`, `admin_reservation_repository
/// .dart`, `approval_repository.dart`, `customer_photo_repository.dart`,
/// `trusted_device_repository.dart`) — `firestore.rules`'s
/// `request.auth` is genuinely null for those reads on Windows under this
/// bridge, since the native SDK's own session was never established, so
/// they may still see `permission-denied` until/unless the native sign-in
/// also succeeds. `RestEmailPasswordAuthClient` fires that native sign-in
/// in the background (unawaited, best-effort) specifically so those
/// features can self-heal the moment it does, without ever blocking the
/// fast REST path everything else (every `RestCallableClient`-routed
/// POS/KDS-action/Admin-menu/entitlement/catalog-sync call this whole app
/// already has on Windows) uses instead.
abstract interface class IdentityToolkitRestAuthClient {
  Future<RestAuthTokens> signInWithPassword({
    required String email,
    required String password,
  });

  Future<RestAuthTokens> createAccount({
    required String email,
    required String password,
  });

  Future<RestAuthTokens> refresh(String refreshToken);
}

class DefaultIdentityToolkitRestAuthClient
    implements IdentityToolkitRestAuthClient {
  DefaultIdentityToolkitRestAuthClient({
    http.Client? httpClient,
    AppEnvironment? environmentOverride,
  })  : _injectedClient = httpClient,
        _environmentOverride = environmentOverride;

  final http.Client? _injectedClient;

  /// Test-only override — real call sites always leave this `null` and
  /// use the real [AppEnvironment.current], matching
  /// `RestCallableClient`'s identical reasoning.
  final AppEnvironment? _environmentOverride;

  static const _timeout = Duration(seconds: 20);

  AppEnvironment get _environment =>
      _environmentOverride ?? AppEnvironment.current;

  String get _apiKey =>
      FirebaseOptionsSelector.forEnvironment(_environment).apiKey;

  Uri _endpoint(String path) {
    if (FirebaseAuthEmulatorConfig.shouldUseEmulator(_environment)) {
      return Uri.http(
        '${FirebaseAuthEmulatorConfig.host}:${FirebaseAuthEmulatorConfig.port}',
        '/identitytoolkit.googleapis.com/v1/$path',
        {'key': 'fake-api-key'},
      );
    }
    return Uri.https(
      path.startsWith('token')
          ? 'securetoken.googleapis.com'
          : 'identitytoolkit.googleapis.com',
      '/v1/$path',
      {'key': _apiKey},
    );
  }

  Future<Map<String, dynamic>> _post(Uri uri, Object body) async {
    final client = _injectedClient ?? http.Client();
    try {
      final response = await client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: body is String ? body : jsonEncode(body),
          )
          .timeout(_timeout);
      final Map<String, dynamic> decoded;
      try {
        final raw = jsonDecode(response.body);
        if (raw is! Map<String, dynamic>) throw const FormatException();
        decoded = raw;
      } on FormatException {
        throw IdentityToolkitAuthException(
          'unknown',
          'Unexpected response shape (HTTP ${response.statusCode}).',
        );
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }
      final error = decoded['error'];
      final rawMessage = error is Map ? error['message'] as String? : null;
      throw IdentityToolkitAuthException(
        _mapErrorCode(rawMessage),
        _mapErrorMessage(rawMessage),
      );
    } on IdentityToolkitAuthException {
      rethrow;
    } catch (error) {
      throw IdentityToolkitAuthException(
        'network-request-failed',
        'Could not reach "$uri": $error',
      );
    } finally {
      if (_injectedClient == null) client.close();
    }
  }

  /// Maps Identity Toolkit's `error.message` enum (`INVALID_PASSWORD`,
  /// `EMAIL_NOT_FOUND`, `INVALID_LOGIN_CREDENTIALS`, `USER_DISABLED`,
  /// `TOO_MANY_ATTEMPTS_TRY_LATER`, `EMAIL_EXISTS`, ...) onto the exact
  /// `firebase_auth`-style codes `EmailPasswordAuthClientException`/
  /// `ErrorMapper._mapFirebaseAuthError` already understand — so the UI
  /// layer needs zero changes regardless of which transport ran.
  String _mapErrorCode(String? rawMessage) {
    final message = rawMessage ?? '';
    if (message.startsWith('EMAIL_NOT_FOUND')) return 'user-not-found';
    if (message.startsWith('INVALID_PASSWORD')) return 'wrong-password';
    if (message.startsWith('INVALID_LOGIN_CREDENTIALS')) {
      return 'invalid-credential';
    }
    if (message.startsWith('USER_DISABLED')) return 'user-disabled';
    if (message.startsWith('TOO_MANY_ATTEMPTS_TRY_LATER')) {
      return 'too-many-requests';
    }
    if (message.startsWith('EMAIL_EXISTS')) return 'email-already-in-use';
    if (message.startsWith('WEAK_PASSWORD')) return 'weak-password';
    if (message.startsWith('INVALID_EMAIL')) return 'invalid-email';
    if (message.startsWith('TOKEN_EXPIRED') ||
        message.startsWith('INVALID_REFRESH_TOKEN') ||
        message.startsWith('USER_NOT_FOUND')) {
      return 'invalid-credential';
    }
    return 'unknown';
  }

  String _mapErrorMessage(String? rawMessage) {
    switch (_mapErrorCode(rawMessage)) {
      case 'user-not-found':
        return 'Bu e-posta ile kayıtlı bir kullanıcı yok.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-posta veya şifre hatalı.';
      case 'user-disabled':
        return 'Bu hesap devre dışı bırakılmış.';
      case 'too-many-requests':
        return 'Çok fazla deneme yapıldı — bir süre sonra tekrar deneyin.';
      case 'email-already-in-use':
        return 'Bu e-posta zaten kullanımda.';
      case 'weak-password':
        return 'Şifre çok zayıf.';
      case 'invalid-email':
        return 'Geçersiz e-posta adresi.';
      default:
        return rawMessage ?? 'Kimlik doğrulama başarısız.';
    }
  }

  RestAuthTokens _parseTokenResponse(Map<String, dynamic> data) {
    final idToken = data['idToken'] as String?;
    final refreshToken = data['refreshToken'] as String?;
    final localId = data['localId'] as String?;
    final expiresInRaw = data['expiresIn'];
    if (idToken == null || refreshToken == null || localId == null) {
      throw const IdentityToolkitAuthException(
        'unknown',
        'Identity Toolkit response missing idToken/refreshToken/localId.',
      );
    }
    final expiresInSeconds =
        expiresInRaw is String ? int.tryParse(expiresInRaw) ?? 3600 : 3600;
    return RestAuthTokens(
      idToken: idToken,
      refreshToken: refreshToken,
      localId: localId,
      expiresAt: DateTime.now().add(Duration(seconds: expiresInSeconds)),
    );
  }

  @override
  Future<RestAuthTokens> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final data = await _post(
      _endpoint('accounts:signInWithPassword'),
      {'email': email, 'password': password, 'returnSecureToken': true},
    );
    return _parseTokenResponse(data);
  }

  @override
  Future<RestAuthTokens> createAccount({
    required String email,
    required String password,
  }) async {
    final data = await _post(
      _endpoint('accounts:signUp'),
      {'email': email, 'password': password, 'returnSecureToken': true},
    );
    return _parseTokenResponse(data);
  }

  @override
  Future<RestAuthTokens> refresh(String refreshToken) async {
    // The Secure Token API is form-encoded, not JSON, and its response
    // fields are snake_case (`id_token`/`refresh_token`/`expires_in`/
    // `user_id`) — genuinely different from every other Identity Toolkit
    // endpoint, not an inconsistency in this class.
    final data = await _post(
      _endpoint('token'),
      'grant_type=refresh_token&refresh_token=$refreshToken',
    );
    final idToken = data['id_token'] as String?;
    final newRefreshToken = data['refresh_token'] as String?;
    final userId = data['user_id'] as String?;
    final expiresInRaw = data['expires_in'];
    if (idToken == null || newRefreshToken == null || userId == null) {
      throw const IdentityToolkitAuthException(
        'unknown',
        'Secure Token response missing id_token/refresh_token/user_id.',
      );
    }
    final expiresInSeconds =
        expiresInRaw is String ? int.tryParse(expiresInRaw) ?? 3600 : 3600;
    return RestAuthTokens(
      idToken: idToken,
      refreshToken: newRefreshToken,
      localId: userId,
      expiresAt: DateTime.now().add(Duration(seconds: expiresInSeconds)),
    );
  }
}
