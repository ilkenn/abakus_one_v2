import '../../domain/models/auth_session.dart';
import '../../domain/models/otp_challenge.dart';
import 'auth_repository.dart';

/// Selected whenever Firebase is not ready (`firebaseReadyProvider` is
/// `false` — see `authRepositoryProvider`) — fails closed on every
/// operation instead of faking success. As of Sprint 9C
/// (`docs/decisions.md` ADR-026) this is no longer gated on `kReleaseMode`:
/// a release build with a healthy Firebase connection uses the real
/// `FirebaseAuthRepository` and genuinely authenticates users, while any
/// build — debug, profile, or release — whose Firebase bootstrap failed
/// falls back here instead of ever faking a success.
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
