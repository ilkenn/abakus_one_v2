import 'app_environment.dart';

/// Where the local Firestore Emulator listens, and which [AppEnvironment]
/// is allowed to connect to it — Phase 9 (`docs/decisions.md` ADR-026),
/// mirrors [FirebaseAuthEmulatorConfig]'s exact reasoning and shape,
/// applied to Firestore instead of Auth.
///
/// [host]/[port] must stay in sync with `firebase.json`'s
/// `emulators.firestore.port` by hand, for the same reason
/// `FirebaseAuthEmulatorConfig` already documents.
abstract final class FirebaseFirestoreEmulatorConfig {
  FirebaseFirestoreEmulatorConfig._();

  static const String host = 'localhost';
  static const int port = 8080;

  /// Only ever `true` for [AppEnvironment.development] — staging and
  /// production must always reach real Firestore. The local emulator has
  /// no real security-rule enforcement guarantee outside the rules file
  /// under active local test, and no real persistence across a machine
  /// reset — letting staging or production connect would be the same
  /// class of mistake `FirebaseAuthEmulatorConfig.shouldUseEmulator`
  /// already exists to prevent for Auth.
  static bool shouldUseEmulator(AppEnvironment environment) {
    return environment == AppEnvironment.development;
  }
}
