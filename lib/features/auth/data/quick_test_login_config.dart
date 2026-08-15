import '../../../bootstrap/app_environment.dart';
import '../../../bootstrap/firebase_auth_emulator_config.dart';
import '../../../core/config/firebase_options_selector.dart';

/// Configuration for "Hızlı Test Girişi" — a development-only shortcut that
/// drives the app's real phone-verification flow end-to-end against the
/// local Firebase Auth Emulator, reading the emulator's own generated SMS
/// code via its debug REST endpoint instead of requiring the developer to
/// look it up and type it in by hand. See `quick_test_login_provider.dart`
/// for the orchestration; this file is pure configuration/gating only.
///
/// **Never available in staging/production** — [isAvailable] structurally
/// requires both [AppEnvironment.development] and
/// [FirebaseAuthEmulatorConfig.shouldUseEmulator] to independently agree,
/// mirroring the exact fail-closed shape [FirebaseAuthEmulatorConfig]
/// itself already established for "does this environment ever talk to the
/// local emulator." Neither check is redundant busywork: keeping both
/// means this stays correct even if one of the two conditions' own logic
/// changes independently later.
abstract final class QuickTestLoginConfig {
  QuickTestLoginConfig._();

  /// The canonical Abaküs development/owner test phone number this flow
  /// always signs in as (`+905337106414`) — the single source, never
  /// duplicated across UI or any other file. Shaped exactly like a real
  /// user's input (a bare 10-digit local number starting with `5`,
  /// matching `TurkishPhoneNumber.isValidLocalNumber`) so it goes through
  /// the exact same `requestOtp`/`verifyOtp` path a real phone number
  /// would — there is no special-cased "magic number" branch anywhere in
  /// the auth stack that treats this value differently.
  static const String developmentPhoneLocalInput = '5337106414';

  /// Pure, parameterized form — independently testable against every
  /// [AppEnvironment] value without depending on [AppEnvironment.current]
  /// (a `static final` resolved once from a compile-time define, which
  /// cannot be swapped at test time). [isAvailable] is the convenience
  /// wrapper real call sites use.
  static bool isAvailableFor(AppEnvironment environment) {
    return environment == AppEnvironment.development &&
        FirebaseAuthEmulatorConfig.shouldUseEmulator(environment);
  }

  /// Whether "Hızlı Test Girişi" may ever be shown or invoked in this
  /// running app instance.
  static bool get isAvailable => isAvailableFor(AppEnvironment.current);

  /// The Firebase project id this running app is actually configured
  /// against for [AppEnvironment.current] — **not** `.firebaserc`'s own
  /// default project (that only controls which project `firebase
  /// emulators:start` itself defaults to when no `--project` flag is
  /// given). The local Auth Emulator manages verification codes/users
  /// per the project id the *connecting client* presents, which for this
  /// app is always whatever `firebase_options_development.dart` declares
  /// — the exact same source `FirebaseBootstrapService.initialize` itself
  /// initializes Firebase from (`FirebaseOptionsSelector`), reused here
  /// rather than a second, independently-maintained project id literal.
  static String emulatorProjectIdFor(AppEnvironment environment) {
    return FirebaseOptionsSelector.forEnvironment(environment).projectId;
  }

  static String get emulatorProjectId =>
      emulatorProjectIdFor(AppEnvironment.current);
}
