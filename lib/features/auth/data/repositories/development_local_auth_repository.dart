import '../../domain/models/auth_session.dart';
import '../../domain/models/otp_challenge.dart';
import '../session_storage.dart';
import 'auth_repository.dart';

/// Test/dev-tooling [AuthRepository] fixture — there is no real backend, no
/// real SMS delivery, and no real OTP security behind this class. It exists
/// so widget/provider tests can exercise the Login → OTP → session flow
/// without a real Firebase Auth Emulator running.
///
/// As of Sprint 9C (`docs/decisions.md` ADR-026) this is **no longer the
/// app's own default dev-mode implementation** — `authRepositoryProvider`
/// now selects `FirebaseAuthRepository` (real Firebase Auth, connected to
/// the local Auth Emulator in `AppEnvironment.development`) whenever
/// Firebase is ready, and `ProductionUnavailableAuthRepository` otherwise —
/// never this class. It remains in `lib/` (not `test/`) only because ~10
/// existing test files already construct it directly as an explicit
/// provider override; do not wire it into any production provider again.
///
/// The OTP code is a **fixed, publicly documented development value**
/// ([developmentOtpCode]) rather than a randomly generated one that's then
/// hidden from the user — a random code the user couldn't see would make
/// this untestable and would look like real security it isn't.
class DevelopmentLocalAuthRepository implements AuthRepository {
  /// The only code [verifyOtp] ever accepts. Never referenced or honored
  /// in a release build.
  static const String developmentOtpCode = '123456';

  /// How long an OTP challenge stays valid after being requested.
  static const Duration otpValidity = Duration(minutes: 3);

  /// How long a phone number must wait between OTP requests. Enforced
  /// here, not just by the OTP screen's countdown — see
  /// [AuthCooldownActiveException].
  static const Duration resendCooldown = Duration(seconds: 30);

  /// How long a freshly-verified session stays valid before the user is
  /// asked to sign in again. An explicit, documented local choice; a real
  /// backend would decide this server-side instead.
  static const Duration sessionValidity = Duration(days: 30);

  final SessionStorage _sessionStorage;

  final Map<String, OtpChallenge> _activeChallenges = {};
  final Map<String, DateTime> _lastRequestedAt = {};

  DevelopmentLocalAuthRepository({SessionStorage? sessionStorage})
      : _sessionStorage = sessionStorage ?? const SecureSessionStorage();

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
  Future<void> clearSession() {
    return _sessionStorage.clearSession();
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

    // Simulates a realistic network round-trip so the loading state this
    // phase requires is actually exercised, rather than resolving
    // instantly.
    await Future.delayed(const Duration(milliseconds: 600));

    final now = DateTime.now();
    _lastRequestedAt[phoneNumber] = now;
    _activeChallenges[phoneNumber] = OtpChallenge(
      phoneNumber: phoneNumber,
      issuedAt: now,
      expiresAt: now.add(otpValidity),
    );
  }

  @override
  Future<OtpVerificationResult> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));

    final challenge = _activeChallenges[phoneNumber];
    if (challenge == null || challenge.isExpired) {
      return OtpVerificationResult.expired;
    }
    if (code != developmentOtpCode) {
      return OtpVerificationResult.invalidCode;
    }
    _activeChallenges.remove(phoneNumber);

    final now = DateTime.now();
    await saveSession(AuthSession(
      uid: 'dev-$phoneNumber',
      phoneNumber: phoneNumber,
      createdAt: now,
      expiresAt: now.add(sessionValidity),
    ));
    return OtpVerificationResult.success;
  }
}
