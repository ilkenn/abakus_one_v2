import 'app_environment.dart';

/// Where the local Firebase Storage Emulator listens, and which
/// [AppEnvironment] is allowed to connect to it — Phase 9
/// (`docs/decisions.md` ADR-026), mirrors [FirebaseAuthEmulatorConfig]'s
/// exact reasoning and shape, applied to Storage instead of Auth.
///
/// [host]/[port] must stay in sync with `firebase.json`'s
/// `emulators.storage.port` by hand, for the same reason
/// `FirebaseAuthEmulatorConfig` already documents.
///
/// [host] defaults to `127.0.0.1`, not the literal `'localhost'` — see
/// `FirebaseAuthEmulatorConfig`'s doc comment for why (the Android
/// `firebase_storage` plugin has the same `localhost` → `10.0.2.2`
/// rewrite, which breaks a physical device reached via `adb reverse`).
/// Override via `--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2` for an
/// Android Emulator session.
abstract final class FirebaseStorageEmulatorConfig {
  FirebaseStorageEmulatorConfig._();

  static const String host = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  static const int port = 9199;

  /// Only ever `true` for [AppEnvironment.development] — same reasoning
  /// as `FirebaseFirestoreEmulatorConfig.shouldUseEmulator`.
  static bool shouldUseEmulator(AppEnvironment environment) {
    return environment == AppEnvironment.development;
  }
}
