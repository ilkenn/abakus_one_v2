import '../../../bootstrap/app_environment.dart';
import '../../../bootstrap/firebase_auth_emulator_config.dart';
import 'quick_test_login_config.dart';

/// TEMPORARY_DEVELOPER_LOGIN
///
/// Configuration/gating for "Geliştirici Girişi" — a phone+PIN-gated
/// convenience login built to avoid repeated SMS/emulator-code friction
/// while the customer app is still under active development. This whole
/// feature is INTENTIONALLY TEMPORARY (unlike "Hızlı Test Girişi"'s
/// underlying emulator machinery, which stays permanent dev
/// infrastructure) — every file that is part of it is marked with the
/// literal string `TEMPORARY_DEVELOPER_LOGIN` specifically so it can be
/// found (`grep -r TEMPORARY_DEVELOPER_LOGIN`) and removed as a complete,
/// self-contained unit before a real production release. Files carrying
/// this marker:
/// - `lib/features/auth/data/dev_login_config.dart` (this file)
/// - `lib/features/auth/presentation/providers/dev_login_provider.dart`
/// - `lib/features/auth/presentation/screens/login_screen.dart`
///   (`_DevLoginSection` + its call site only — the rest of the screen is
///   permanent)
///
/// **The PIN is a convenience gate, never the real authentication
/// boundary.** The actual authentication is still a genuine Firebase Auth
/// Emulator phone sign-in (`QuickTestLoginConfig`/`QuickTestLoginNotifier`,
/// reused verbatim, not duplicated) — this class only decides whether a
/// human may trigger that flow via a phone+PIN form instead of the
/// existing one-tap button, and only in a running app instance where a
/// real emulator phone challenge was always going to succeed anyway
/// (development + `FirebaseAuthEmulatorConfig.shouldUseEmulator`).
///
/// **Never enables Firebase's Email/Password provider, never creates a
/// password-auth user.** No such call exists anywhere in this file or
/// [DevLoginNotifier] — the resulting session is a real
/// `sign_in_provider == 'phone'` credential because it is produced by
/// exactly the same `AuthNotifier.requestOtp`/`verifyOtp` ->
/// `FirebaseAuthRepository` -> `verifyPhoneNumber`/`confirmSmsCode` path
/// every other sign-in (manual or Quick Test Login) already uses.
abstract final class DevLoginConfig {
  DevLoginConfig._();

  /// The one locked developer account this flow will ever sign in as —
  /// **the same number** `QuickTestLoginConfig.developmentPhoneLocalInput`
  /// already names, reused rather than duplicated as a second literal
  /// (`+905337106414` = `+90` + this local form).
  static String get developerPhoneLocalInput =>
      QuickTestLoginConfig.developmentPhoneLocalInput;

  /// Read once from `--dart-define=DEV_LOGIN_PIN=<value>` — **never
  /// hardcoded, never committed**. Empty (`''`) when the define is
  /// absent, which [isAvailableFor] treats as "developer login must be
  /// unavailable" (locked requirement), not as an unset-but-implicitly-OK
  /// PIN.
  static const String pin = String.fromEnvironment('DEV_LOGIN_PIN');

  /// Pure, parameterized form — independently testable against every
  /// [AppEnvironment] value and an arbitrary [pin] without depending on
  /// either [AppEnvironment.current] or the real compile-time [pin]
  /// constant (both `static final`/`static const` values resolved once,
  /// which cannot be swapped at test time — mirrors
  /// `QuickTestLoginConfig.isAvailableFor`'s exact same reasoning, extended
  /// with the one extra condition this feature adds).
  static bool isAvailableFor(AppEnvironment environment, {required String pin}) {
    return environment == AppEnvironment.development &&
        FirebaseAuthEmulatorConfig.shouldUseEmulator(environment) &&
        pin.isNotEmpty;
  }

  /// Whether "Geliştirici Girişi" may ever be shown or invoked in this
  /// running app instance. `false` in every build where `DEV_LOGIN_PIN`
  /// was not supplied — including every staging/production build, which
  /// never has a reason to supply it.
  static bool get isAvailable =>
      isAvailableFor(AppEnvironment.current, pin: pin);
}
