import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_auth_emulator_config.dart';
import '../../data/emulator_verification_code_client.dart';
import '../../data/quick_test_login_config.dart';
import '../../domain/models/otp_challenge.dart';
import 'auth_provider.dart';

final emulatorVerificationCodeClientProvider =
    Provider<EmulatorVerificationCodeClient>((ref) {
  return const HttpEmulatorVerificationCodeClient();
});

class QuickTestLoginState {
  const QuickTestLoginState({this.isRunning = false, this.error});

  final bool isRunning;
  final String? error;

  QuickTestLoginState copyWith({
    bool? isRunning,
    String? error,
    bool clearError = false,
  }) {
    return QuickTestLoginState(
      isRunning: isRunning ?? this.isRunning,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives "Hızlı Test Girişi" — **reuses the existing phone-verification
/// architecture verbatim**, never a parallel one: [run] calls exactly the
/// same `AuthNotifier.requestOtp`/`verifyOtp` methods
/// [LoginScreen]/[OtpScreen] already call, in the same order, for the same
/// reason. The only thing this notifier adds is reading the emulator's own
/// generated SMS code automatically instead of a human typing it in — the
/// resulting `AuthSession`/`AuthState` is indistinguishable from a manual
/// sign-in with the same phone number, because it *is* the same code path.
///
/// Structurally cannot run outside development-with-emulator: [run]'s own
/// first check re-verifies [QuickTestLoginConfig.isAvailable] before doing
/// anything, independent of whatever gated the button that invoked it —
/// defense in depth, not merely a UI-level hide.
class QuickTestLoginNotifier extends AutoDisposeNotifier<QuickTestLoginState> {
  @override
  QuickTestLoginState build() => const QuickTestLoginState();

  Future<bool> run() async {
    if (!QuickTestLoginConfig.isAvailable) {
      state = state.copyWith(
        error:
            'Hızlı Test Girişi yalnızca geliştirme ortamında kullanılabilir.',
      );
      return false;
    }

    state = state.copyWith(isRunning: true, clearError: true);

    final authNotifier = ref.read(authProvider.notifier);

    // Step 1 — the existing phone-verification flow, unmodified. Against
    // the real `FirebaseAuthRepository` (always the case whenever
    // [QuickTestLoginConfig.isAvailable] is true — see its own doc
    // comment), this issues a genuine Firebase Auth phone challenge
    // against the local emulator, exactly like a manual sign-in would.
    final sent = await authNotifier.requestOtp(
      QuickTestLoginConfig.developmentPhoneLocalInput,
    );
    if (!sent) {
      state = state.copyWith(
        isRunning: false,
        error:
            ref.read(authProvider).error ?? 'Doğrulama isteği gönderilemedi.',
      );
      return false;
    }

    final phoneNumber = ref.read(authProvider).pendingPhoneNumber;
    if (phoneNumber == null) {
      state = state.copyWith(
        isRunning: false,
        error: 'Telefon numarası çözümlenemedi.',
      );
      return false;
    }

    // Step 2 — the one genuinely new piece: read the code the emulator
    // just generated instead of asking a human to type it in.
    String? code;
    try {
      code = await ref
          .read(emulatorVerificationCodeClientProvider)
          .fetchLatestCode(
            host: FirebaseAuthEmulatorConfig.host,
            port: FirebaseAuthEmulatorConfig.port,
            projectId: QuickTestLoginConfig.emulatorProjectId,
            phoneNumber: phoneNumber,
          );
    } on EmulatorVerificationCodeException catch (error) {
      state = state.copyWith(
        isRunning: false,
        error: 'Auth Emulator’a ulaşılamadı: ${error.message}',
      );
      return false;
    }

    if (code == null) {
      state = state.copyWith(
        isRunning: false,
        error: 'Emulator’da bu numara için bir doğrulama kodu bulunamadı.',
      );
      return false;
    }

    // Step 3 — the existing OTP confirmation flow, unmodified. On success
    // this sets `AuthState.isAuthenticated = true` with a real
    // Firebase-issued `AuthSession`, exactly like `OtpScreen`'s own
    // `_submit` does.
    final result = await authNotifier.verifyOtp(code);
    state = state.copyWith(isRunning: false);
    if (result != OtpVerificationResult.success) {
      state = state.copyWith(
        error: 'Hızlı test girişi başarısız oldu. Lütfen tekrar deneyin.',
      );
      return false;
    }
    return true;
  }
}

final quickTestLoginProvider =
    NotifierProvider.autoDispose<QuickTestLoginNotifier, QuickTestLoginState>(
  QuickTestLoginNotifier.new,
);
