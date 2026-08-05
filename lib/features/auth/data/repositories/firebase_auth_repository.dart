import '../../domain/models/auth_session.dart';
import '../../domain/models/otp_challenge.dart';
import '../session_storage.dart';
import 'auth_repository.dart';
import 'firebase_auth_client.dart';

/// The real, Firebase-Auth-backed [AuthRepository] — Sprint 9C
/// (`docs/decisions.md` ADR-026). Replaces `DevelopmentLocalAuthRepository`
/// as the app's actual customer sign-in path: selected by
/// `authRepositoryProvider` whenever `firebaseReadyProvider` is `true`,
/// which in `AppEnvironment.development` means the local Auth Emulator
/// (`FirebaseAuthEmulatorConfig`, wired by `FirebaseBootstrapService`) and
/// in staging/production means the real, already-provisioned Firebase
/// project. Unlike the emulator, staging/production genuinely deliver an
/// SMS and genuinely enforce Firebase's own OTP/abuse limits — there is no
/// separate "is this really production" branch in this class; the
/// difference is entirely which project [FirebaseAuthClient] is connected
/// to, decided once at bootstrap.
///
/// [AuthSession.uid] here is always a real Firebase Auth UID — this is what
/// makes it safe for `ResolveCurrentCustomer`/`profileProvider` to treat it
/// as the canonical identity rather than a derived, guessable string.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    required FirebaseAuthClient client,
    SessionStorage? sessionStorage,
    this.sessionValidity = const Duration(days: 30),
  })  : _client = client,
        _sessionStorage = sessionStorage ?? const SecureSessionStorage();

  /// How long a freshly-verified session stays valid before the user is
  /// asked to sign in again. Firebase Auth itself keeps the underlying
  /// credential valid far longer; this bounds only the app's own local
  /// "is this session still good" check, same as the value
  /// `DevelopmentLocalAuthRepository` used before this sprint.
  final Duration sessionValidity;

  /// How long a phone number must wait between OTP requests — enforced
  /// here (not just the OTP screen's countdown) in addition to whatever
  /// rate limit Firebase itself applies server-side.
  static const Duration resendCooldown = Duration(seconds: 30);

  final FirebaseAuthClient _client;
  final SessionStorage _sessionStorage;

  final Map<String, DateTime> _lastRequestedAt = {};
  final Map<String, String> _verificationIdsByPhoneNumber = {};

  @override
  Duration get resendCooldownDuration => resendCooldown;

  @override
  Future<AuthSession?> loadSession() async {
    final session = await _sessionStorage.readSession();
    if (session == null) return null;
    if (session.isExpired) {
      await _sessionStorage.clearSession();
      return null;
    }
    return session;
  }

  @override
  Future<void> saveSession(AuthSession session) {
    return _sessionStorage.writeSession(session);
  }

  @override
  Future<void> clearSession() async {
    await _client.signOut();
    await _sessionStorage.clearSession();
  }

  @override
  Future<void> requestOtp(String phoneNumber) async {
    final lastRequest = _lastRequestedAt[phoneNumber];
    if (lastRequest != null) {
      final elapsed = DateTime.now().difference(lastRequest);
      if (elapsed < resendCooldown) {
        throw AuthCooldownActiveException(resendCooldown - elapsed);
      }
    }

    try {
      final verificationId = await _client.verifyPhoneNumber(phoneNumber);
      _lastRequestedAt[phoneNumber] = DateTime.now();
      _verificationIdsByPhoneNumber[phoneNumber] = verificationId;
    } on FirebaseAuthClientException {
      throw const AuthServiceUnavailableException();
    }
  }

  @override
  Future<OtpVerificationResult> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {
    final verificationId = _verificationIdsByPhoneNumber[phoneNumber];
    if (verificationId == null) {
      return OtpVerificationResult.expired;
    }

    try {
      final result = await _client.confirmSmsCode(
        verificationId: verificationId,
        smsCode: code,
      );
      _verificationIdsByPhoneNumber.remove(phoneNumber);

      final now = DateTime.now();
      await saveSession(AuthSession(
        uid: result.uid,
        phoneNumber: result.phoneNumber ?? phoneNumber,
        createdAt: now,
        expiresAt: now.add(sessionValidity),
      ));
      return OtpVerificationResult.success;
    } on FirebaseAuthClientException catch (error) {
      switch (error.code) {
        case 'session-expired':
        case 'invalid-verification-id':
          _verificationIdsByPhoneNumber.remove(phoneNumber);
          return OtpVerificationResult.expired;
        default:
          // Covers 'invalid-verification-code' and any other rejection —
          // the challenge itself is still live, so the user may retry
          // without re-requesting a code.
          return OtpVerificationResult.invalidCode;
      }
    }
  }
}
