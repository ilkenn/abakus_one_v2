import 'app_environment.dart';

/// Where the local Firebase Storage Emulator listens, and which
/// [AppEnvironment] is allowed to connect to it — Phase 9
/// (`docs/decisions.md` ADR-026), mirrors [FirebaseAuthEmulatorConfig]'s
/// exact reasoning and shape, applied to Storage instead of Auth.
///
/// [host]/[port] must stay in sync with `firebase.json`'s
/// `emulators.storage.port` by hand, for the same reason
/// `FirebaseAuthEmulatorConfig` already documents.
abstract final class FirebaseStorageEmulatorConfig {
  FirebaseStorageEmulatorConfig._();

  static const String host = 'localhost';
  static const int port = 9199;

  /// Only ever `true` for [AppEnvironment.development] — same reasoning
  /// as `FirebaseFirestoreEmulatorConfig.shouldUseEmulator`.
  static bool shouldUseEmulator(AppEnvironment environment) {
    return environment == AppEnvironment.development;
  }
}
