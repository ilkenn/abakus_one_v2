import '../../domain/models/auth_session.dart';
import '../../domain/models/otp_challenge.dart';
import 'auth_repository.dart';

/// Selected in release builds until a real backend-backed [AuthRepository]
/// exists — fails closed on every operation instead of faking success.
/// This is what makes it impossible for a release build to ever
/// authenticate a user without a real backend, per the explicit "do not
/// show authentication success without a real backend" requirement:
/// nothing in a release build ever reuses `DevelopmentLocalAuthRepository`.
class ProductionUnavailableAuthRepository implements AuthRepository {
  const ProductionUnavailableAuthRepository();

  @override
  Duration get resendCooldownDuration => Duration.zero;

  @override
  Future<AuthSession?> loadSession() async => null;

  @override
  Future<void> saveSession(AuthSession session) async {
    // No real backend to persist against yet — intentionally a no-op
    // rather than writing a session that would imply a real login
    // happened.
  }

  @override
  Future<void> clearSession() async {}

  @override
  Future<void> requestOtp(String phoneNumber) async {
    // Deliberately `async` (not a bare synchronous `throw`) so this
    // surfaces to every caller as a rejected `Future`, exactly like
    // `DevelopmentLocalAuthRepository`'s exceptions do — callers can
    // always `await`/`catch` this uniformly regardless of which
    // implementation is active.
    throw const AuthServiceUnavailableException();
  }

  @override
  Future<OtpVerificationResult> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {
    throw const AuthServiceUnavailableException();
  }
}
