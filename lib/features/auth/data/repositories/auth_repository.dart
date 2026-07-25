import '../../domain/models/auth_session.dart';
import '../../domain/models/otp_challenge.dart';

/// Everything the app needs from an authentication backend, behind one
/// seam — mirrors the existing `OrdersRepository` pattern in
/// `lib/features/orders/data/orders_repository.dart` so a future real
/// backend is a single new implementation plus a single provider
/// override, with no change to `AuthNotifier` or any screen.
///
/// Two implementations exist today: `DevelopmentLocalAuthRepository`
/// (debug/profile builds — see its own doc comment for exactly what it
/// fakes and why) and `ProductionUnavailableAuthRepository` (release
/// builds, until a real backend is wired in) — see `auth_provider.dart`'s
/// `authRepositoryProvider` for how the choice is made.
abstract interface class AuthRepository {
  /// How long a caller must wait between OTP resend requests — exposed so
  /// the UI can render an accurate countdown without hardcoding a value
  /// that belongs to one specific implementation. The repository itself
  /// still independently enforces this in [requestOtp] regardless of what
  /// the UI displays.
  Duration get resendCooldownDuration;

  /// The persisted session, or `null` if none exists, it's expired, or it
  /// couldn't be read. Never throws.
  Future<AuthSession?> loadSession();

  Future<void> saveSession(AuthSession session);

  Future<void> clearSession();

  /// Starts an OTP challenge for [phoneNumber] (already normalized to
  /// `+905XXXXXXXXX` by the caller). Throws [AuthCooldownActiveException]
  /// if a request for the same number was made too recently, or
  /// [AuthServiceUnavailableException] if this repository can't service
  /// requests at all (see `ProductionUnavailableAuthRepository`).
  Future<void> requestOtp(String phoneNumber);

  /// Throws [AuthServiceUnavailableException] under the same condition as
  /// [requestOtp].
  Future<OtpVerificationResult> verifyOtp({
    required String phoneNumber,
    required String code,
  });
}

/// Thrown by [AuthRepository.requestOtp] when called again before the
/// resend cooldown for that phone number has elapsed. Enforced by the
/// repository itself, not just the OTP screen's countdown display, so the
/// rule holds even if a caller bypasses the UI. Real rate-limiting is a
/// backend's job once one exists — this is the client-side placeholder
/// for that same rule in the meantime.
class AuthCooldownActiveException implements Exception {
  final Duration remaining;
  const AuthCooldownActiveException(this.remaining);
}

/// Thrown by a repository that cannot service authentication at all right
/// now (see `ProductionUnavailableAuthRepository`) — surfaced to the user
/// as an honest "Giriş hizmeti şu anda kullanılamıyor" message, never as a
/// fake success.
class AuthServiceUnavailableException implements Exception {
  const AuthServiceUnavailableException();
}
