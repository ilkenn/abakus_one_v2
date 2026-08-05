import 'app_environment.dart';

/// Where the local Cloud Functions Emulator listens, and which
/// [AppEnvironment] is allowed to connect to it — Phase 9
/// (`docs/decisions.md` ADR-026), mirrors [FirebaseAuthEmulatorConfig]'s
/// exact reasoning and shape, applied to Functions instead of Auth.
///
/// [host]/[port] must stay in sync with `firebase.json`'s
/// `emulators.functions.port` by hand, for the same reason
/// `FirebaseAuthEmulatorConfig` already documents.
abstract final class FirebaseFunctionsEmulatorConfig {
  FirebaseFunctionsEmulatorConfig._();

  static const String host = 'localhost';
  static const int port = 5001;

  /// Only ever `true` for [AppEnvironment.development] — same reasoning
  /// as `FirebaseFirestoreEmulatorConfig.shouldUseEmulator`. Callable
  /// functions deployed to staging/production are the only ones ever
  /// reachable from those environments.
  static bool shouldUseEmulator(AppEnvironment environment) {
    return environment == AppEnvironment.development;
  }
}
