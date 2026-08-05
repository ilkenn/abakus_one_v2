import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../bootstrap/firebase_ready_provider.dart';
import '../../../../core/account_deletion/account_deletion_providers.dart';
import '../../../../core/account_deletion/domain/account_deletion_request.dart';
import '../../../../core/device_tokens/device_token_providers.dart';
import '../../domain/models/auth_session.dart';
import '../../domain/models/otp_challenge.dart';
import '../../domain/phone_number.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/firebase_auth_client.dart';
import '../../data/repositories/firebase_auth_repository.dart';
import '../../data/repositories/production_unavailable_auth_repository.dart';

/// The [AuthRepository] implementation currently in use. Mirrors
/// `ordersRepositoryProvider` in `orders_provider.dart`: nothing in
/// [AuthNotifier] or any screen depends on either concrete implementation
/// directly.
///
/// As of Sprint 9C (`docs/decisions.md` ADR-026), the choice is gated on
/// [firebaseReadyProvider] — the same fail-closed seam every other
/// Firebase-dependent provider uses (`crashReportingServiceProvider`,
/// `appCheckServiceProvider`) — not `kReleaseMode`: a release build with a
/// healthy Firebase connection genuinely authenticates users via
/// [FirebaseAuthRepository] (connected to the local Auth Emulator in
/// `AppEnvironment.development`, or the real project in staging/
/// production); any build whose Firebase bootstrap failed falls back to
/// [ProductionUnavailableAuthRepository] instead of ever faking success.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final isFirebaseReady = ref.watch(firebaseReadyProvider);
  if (!isFirebaseReady) {
    return const ProductionUnavailableAuthRepository();
  }
  return FirebaseAuthRepository(client: DefaultFirebaseAuthClient());
});

class AuthState {
  final bool isAuthenticated;
  final bool isGuest;
  final bool isLoading;
  final String? error;
  final String? pendingPhoneNumber;
  final AuthSession? session;

  const AuthState({
    required this.isAuthenticated,
    required this.isGuest,
    this.isLoading = false,
    this.error,
    this.pendingPhoneNumber,
    this.session,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isGuest,
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? pendingPhoneNumber,
    bool clearPendingPhoneNumber = false,
    AuthSession? session,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isGuest: isGuest ?? this.isGuest,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      pendingPhoneNumber: clearPendingPhoneNumber
          ? null
          : (pendingPhoneNumber ?? this.pendingPhoneNumber),
      session: session ?? this.session,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    return const AuthState(isAuthenticated: false, isGuest: false);
  }

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  /// Sprint 9G (`docs/decisions.md` ADR-026) — "during cooling-off: login
  /// blocked/restricted"; a [AccountDeletionStatus.completed] account
  /// stays blocked permanently (its data has already been anonymized —
  /// there is no account left to sign back into). Only
  /// [AccountDeletionStatus.cancelled] (or no request at all) allows
  /// sign-in through. Deliberately reads `core/account_deletion` — never
  /// `features/profile` — for the `core -> feature` layering reason
  /// `AccountDeletionRequestRepository`'s own doc comment explains.
  Future<bool> _isBlockedByDeletionRequest(String uid) async {
    final request = await ref
        .read(accountDeletionRequestRepositoryProvider)
        .findLatestByUid(uid);
    if (request == null) return false;
    return request.status == AccountDeletionStatus.coolingOff ||
        request.status == AccountDeletionStatus.completed;
  }

  /// Called once by Splash at startup. Looks for a persisted session and,
  /// if a valid one exists, marks the user authenticated — this is the
  /// entire "auto login" behavior. Never throws: a broken/unreadable
  /// session must never crash the app, only leave the user logged out.
  Future<void> checkPersistedSession() async {
    try {
      final session = await _repository.loadSession();
      if (session == null) return;
      if (await _isBlockedByDeletionRequest(session.uid)) {
        await _repository.clearSession();
        state = state.copyWith(
          error: 'Bu hesap için silme talebi bulunmaktadır. Giriş engellendi.',
        );
        return;
      }
      state = state.copyWith(isAuthenticated: true, session: session);
    } catch (_) {
      // Defensive last line — loadSession itself should never throw, but
      // a corrupted/unreadable session must never crash the app.
    }
  }

  /// Validates and normalizes [rawLocalInput] before ever reaching the
  /// repository — an invalid Turkish mobile number is never sent to it.
  /// Returns whether the OTP request was actually sent.
  Future<bool> requestOtp(String rawLocalInput) async {
    final normalized = TurkishPhoneNumber.normalize(rawLocalInput);
    if (normalized == null) {
      state =
          state.copyWith(error: 'Lütfen geçerli bir telefon numarası girin.');
      return false;
    }
    return _sendOtp(normalized);
  }

  /// Re-requests a code for the already-validated
  /// [AuthState.pendingPhoneNumber] — used by the OTP screen's resend
  /// action, which never re-normalizes a number that's already normalized.
  Future<bool> resendOtp() async {
    final phoneNumber = state.pendingPhoneNumber;
    if (phoneNumber == null) return false;
    return _sendOtp(phoneNumber);
  }

  Future<bool> _sendOtp(String normalizedPhoneNumber) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.requestOtp(normalizedPhoneNumber);
      state = state.copyWith(
        isLoading: false,
        pendingPhoneNumber: normalizedPhoneNumber,
      );
      return true;
    } on AuthCooldownActiveException {
      state = state.copyWith(
        isLoading: false,
        error: 'Lütfen tekrar denemeden önce birkaç saniye bekleyin.',
      );
      return false;
    } on AuthServiceUnavailableException {
      state = state.copyWith(
        isLoading: false,
        error: 'Giriş hizmeti şu anda kullanılamıyor.',
      );
      return false;
    }
  }

  Future<OtpVerificationResult> verifyOtp(String code) async {
    final phoneNumber = state.pendingPhoneNumber;
    if (phoneNumber == null) {
      return OtpVerificationResult.invalidCode;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await _repository.verifyOtp(
        phoneNumber: phoneNumber,
        code: code,
      );
      if (result == OtpVerificationResult.success) {
        final session = await _repository.loadSession();
        if (session != null && await _isBlockedByDeletionRequest(session.uid)) {
          await _repository.clearSession();
          state = state.copyWith(
            isLoading: false,
            clearPendingPhoneNumber: true,
            error:
                'Bu hesap için silme talebi bulunmaktadır. Giriş engellendi.',
          );
          return OtpVerificationResult.accountBlocked;
        }
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          session: session,
          clearPendingPhoneNumber: true,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
      return result;
    } on AuthServiceUnavailableException {
      state = state.copyWith(
        isLoading: false,
        error: 'Giriş hizmeti şu anda kullanılamıyor.',
      );
      return OtpVerificationResult.invalidCode;
    }
  }

  /// Guest sessions are never persisted (see `docs/master_spec_migration.md`)
  /// — they last only as long as the app process does, so no
  /// `AuthSession`/secure-storage entry is ever created for one.
  void loginAsGuest() {
    state = state.copyWith(isGuest: true);
  }

  /// Sprint 9H (`docs/decisions.md` ADR-026): also revokes every active
  /// device token for the signed-out uid — a signed-out device should
  /// not keep receiving push notifications addressed to that identity.
  /// No-ops safely if there was no session (nothing to revoke for).
  Future<void> logout() async {
    final uid = state.session?.uid;
    await _repository.clearSession();
    if (uid != null) {
      await ref
          .read(revokeDeviceTokensForUserProvider)
          .call(uid: uid, now: DateTime.now());
    }
    state = const AuthState(isAuthenticated: false, isGuest: false);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
