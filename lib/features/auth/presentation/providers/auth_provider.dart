import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/auth_session.dart';
import '../../domain/models/otp_challenge.dart';
import '../../domain/phone_number.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/development_local_auth_repository.dart';
import '../../data/repositories/production_unavailable_auth_repository.dart';

/// The [AuthRepository] implementation currently in use. Mirrors
/// `ordersRepositoryProvider` in `orders_provider.dart`: a future
/// backend-backed phase overrides only this provider — nothing in
/// [AuthNotifier] or any screen depends on either concrete implementation
/// directly.
///
/// The choice itself is the one place release builds are protected from
/// ever authenticating without a real backend: [kReleaseMode] selects
/// [ProductionUnavailableAuthRepository] (fails closed on every call);
/// anything else (debug/profile — i.e. every build this app has today)
/// selects [DevelopmentLocalAuthRepository].
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (kReleaseMode) {
    return const ProductionUnavailableAuthRepository();
  }
  return DevelopmentLocalAuthRepository();
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

  /// Called once by Splash at startup. Looks for a persisted session and,
  /// if a valid one exists, marks the user authenticated — this is the
  /// entire "auto login" behavior. Never throws: a broken/unreadable
  /// session must never crash the app, only leave the user logged out.
  Future<void> checkPersistedSession() async {
    try {
      final session = await _repository.loadSession();
      if (session != null) {
        state = state.copyWith(isAuthenticated: true, session: session);
      }
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

  Future<void> logout() async {
    await _repository.clearSession();
    state = const AuthState(isAuthenticated: false, isGuest: false);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
