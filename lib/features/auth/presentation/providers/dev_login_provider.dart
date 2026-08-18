import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../bootstrap/firebase_auth_emulator_config.dart';
import '../../data/dev_login_config.dart';
import '../../data/emulator_verification_code_client.dart';
import '../../domain/models/otp_challenge.dart';
import '../../domain/phone_number.dart';
import 'auth_provider.dart';
import 'quick_test_login_provider.dart' show emulatorVerificationCodeClientProvider;

/// TEMPORARY_DEVELOPER_LOGIN — see `DevLoginConfig`'s own doc comment for
/// the full removal-marker list.
///
/// Drives "Geliştirici Girişi": validates the human-entered phone+PIN pair
/// locally, then runs the real phone-verification flow itself —
/// `AuthNotifier.requestOtp` -> fetch the emulator's own generated code ->
/// `AuthNotifier.verifyOtp` — using ONLY:
/// - the developer-entered, validated phone (never a re-derived constant),
/// - the CURRENT live Firebase app's own `projectId`
///   ([currentFirebaseProjectIdProvider], `Firebase.app().options.projectId`
///   — never a second, independently hardcoded/derived value),
/// - the configured emulator host/port ([FirebaseAuthEmulatorConfig]).
///
/// **Deliberately does NOT delegate to [QuickTestLoginNotifier].** An
/// earlier version of this file did — that notifier's own `run()` ignores
/// whatever phone it's asked about and always requests OTP for its own
/// internal `QuickTestLoginConfig.developmentPhoneLocalInput`/
/// `QuickTestLoginConfig.emulatorProjectId` instead, which is correct for
/// its own one-tap purpose but wrong to delegate through here: this class
/// exists specifically so the phone the developer actually typed (and the
/// project this app instance actually initialized against) are what get
/// used, not a value substituted by a different feature's own config.
/// [EmulatorVerificationCodeClient]/`emulatorVerificationCodeClientProvider`
/// — the lower-level HTTP client, not the higher-level notifier — is still
/// reused as-is, per "reuse lower-level phone-auth/emulator components."
class DevLoginState {
  const DevLoginState({this.isRunning = false, this.error});

  final bool isRunning;
  final String? error;

  DevLoginState copyWith({
    bool? isRunning,
    String? error,
    bool clearError = false,
  }) {
    return DevLoginState(
      isRunning: isRunning ?? this.isRunning,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// TEMPORARY_DEVELOPER_LOGIN — resolves to the current live Firebase app's
/// own `projectId`, the exact value `Firebase.initializeApp` was itself
/// called with (`FirebaseBootstrapService` -> `FirebaseOptionsSelector
/// .forEnvironment`). The emulator verification-code REST lookup MUST use
/// this — never a second, independently maintained project id constant —
/// so it can never drift out of sync with whatever project this running
/// app instance actually talks to. `Firebase.app()` throws if no app has
/// been initialized (true under `flutter test`, where no real Firebase
/// exists); mirrors `firebaseReadyProvider`'s own "a provider, overridable
/// in tests/real bootstrap, never a bare static call sprinkled at each use
/// site" shape.
final currentFirebaseProjectIdProvider = Provider<String>((ref) {
  return Firebase.app().options.projectId;
});

/// Locked, dev-only, deliberately generic per the required UX spec — never
/// reveals whether the phone or the PIN was the specific mismatch, and
/// never surfaces the underlying emulator flow's own more detailed error
/// text ("Do not expose emulator internals to normal users").
const String _devLoginFailedMessage = 'Geliştirici girişi başarısız.';

class DevLoginNotifier extends AutoDisposeNotifier<DevLoginState> {
  @override
  DevLoginState build() => const DevLoginState();

  Future<bool> run({required String phoneInput, required String pin}) async {
    // Defense in depth — re-verified independently of whatever gated the
    // UI that invoked this. `DevLoginConfig.pin.isEmpty` is checked
    // explicitly (not just `pin == DevLoginConfig.pin`) so an unset
    // DEV_LOGIN_PIN can never be satisfied by an equally-empty submitted
    // PIN.
    if (!DevLoginConfig.isAvailable || DevLoginConfig.pin.isEmpty) {
      state = state.copyWith(error: _devLoginFailedMessage);
      return false;
    }

    state = state.copyWith(isRunning: true, clearError: true);

    final normalizedPhone = TurkishPhoneNumber.normalize(phoneInput);
    final expectedPhone = '+90${DevLoginConfig.developerPhoneLocalInput}';
    if (normalizedPhone != expectedPhone) {
      state = state.copyWith(isRunning: false, error: _devLoginFailedMessage);
      return false;
    }
    if (pin != DevLoginConfig.pin) {
      state = state.copyWith(isRunning: false, error: _devLoginFailedMessage);
      return false;
    }

    final authNotifier = ref.read(authProvider.notifier);

    // Step 1 — the real phone-verification flow's own entry point, given
    // the ACTUAL developer-typed input (already proven above to normalize
    // to the one locked developer number) — never a separately re-derived
    // constant.
    final sent = await authNotifier.requestOtp(phoneInput);
    if (!sent) {
      state = state.copyWith(
        isRunning: false,
        error: _devLoginFailedMessage,
      );
      return false;
    }
    final pendingPhoneNumber = ref.read(authProvider).pendingPhoneNumber;
    if (pendingPhoneNumber == null) {
      state = state.copyWith(isRunning: false, error: _devLoginFailedMessage);
      return false;
    }

    // Step 2 — read the code the emulator just generated, against the
    // CURRENT live Firebase app's own project id.
    String? code;
    try {
      code = await ref
          .read(emulatorVerificationCodeClientProvider)
          .fetchLatestCode(
            host: FirebaseAuthEmulatorConfig.host,
            port: FirebaseAuthEmulatorConfig.port,
            projectId: ref.read(currentFirebaseProjectIdProvider),
            phoneNumber: pendingPhoneNumber,
          );
    } on EmulatorVerificationCodeException {
      state = state.copyWith(isRunning: false, error: _devLoginFailedMessage);
      return false;
    }
    if (code == null) {
      state = state.copyWith(isRunning: false, error: _devLoginFailedMessage);
      return false;
    }

    // Step 3 — the real confirmation call.
    final result = await authNotifier.verifyOtp(code);
    final success = result == OtpVerificationResult.success;
    state = state.copyWith(
      isRunning: false,
      error: success ? null : _devLoginFailedMessage,
    );
    return success;
  }
}

final devLoginProvider =
    NotifierProvider.autoDispose<DevLoginNotifier, DevLoginState>(
  DevLoginNotifier.new,
);
