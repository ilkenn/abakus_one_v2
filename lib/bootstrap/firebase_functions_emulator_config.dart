import 'app_environment.dart';

/// Where the local Cloud Functions Emulator listens, and which
/// [AppEnvironment] is allowed to connect to it — Phase 9
/// (`docs/decisions.md` ADR-026), mirrors [FirebaseAuthEmulatorConfig]'s
/// exact reasoning and shape, applied to Functions instead of Auth.
///
/// [host]/[port] must stay in sync with `firebase.json`'s
/// `emulators.functions.port` by hand, for the same reason
/// `FirebaseAuthEmulatorConfig` already documents.
///
/// [host] defaults to `127.0.0.1`, not the literal `'localhost'` — see
/// `FirebaseAuthEmulatorConfig`'s doc comment for why (the Android
/// `cloud_functions` plugin has the same `localhost` → `10.0.2.2`
/// rewrite, which breaks a physical device reached via `adb reverse`).
/// Override via `--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2` for an
/// Android Emulator session. Not in this project's currently-documented
/// `adb reverse` port list (9099/8080/9199/4000) — add
/// `adb reverse tcp:5001 tcp:5001` too if Functions are exercised from a
/// physical device.
abstract final class FirebaseFunctionsEmulatorConfig {
  FirebaseFunctionsEmulatorConfig._();

  static const String host = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  static const int port = 5001;

  /// Only ever `true` for [AppEnvironment.development] — same reasoning
  /// as `FirebaseFirestoreEmulatorConfig.shouldUseEmulator`. Callable
  /// functions deployed to staging/production are the only ones ever
  /// reachable from those environments.
  static bool shouldUseEmulator(AppEnvironment environment) {
    return environment == AppEnvironment.development;
  }
}
