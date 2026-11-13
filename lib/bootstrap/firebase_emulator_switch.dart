import 'app_environment.dart';

/// The one switch for whether a [AppEnvironment.development] build talks to
/// the local Firebase Emulator Suite or to the real development project
/// (`abakus-one-dev`).
///
/// Every `Firebase*EmulatorConfig.shouldUseEmulator` (Auth, Firestore,
/// Functions, Storage) delegates here, so the four services can never
/// disagree: a build is either fully local or fully real.
///
/// The default is unchanged from before this switch existed: development
/// uses the emulator. A real-device test against the deployed dev project
/// opts out at build time:
///
/// ```
/// flutter build apk --flavor development \
///   --dart-define=ENVIRONMENT=development \
///   --dart-define=FIREBASE_USE_EMULATOR=false
/// ```
///
/// Staging and production never use the emulator, whatever this flag says.
/// The flag can only turn the emulator *off*, never on, outside development.
abstract final class FirebaseEmulatorSwitch {
  FirebaseEmulatorSwitch._();

  /// `--dart-define=FIREBASE_USE_EMULATOR=false` turns the emulator off for
  /// a development build. Defaults to `true`.
  static const bool developmentUsesEmulator = bool.fromEnvironment(
    'FIREBASE_USE_EMULATOR',
    defaultValue: true,
  );

  /// Whether [environment] should connect to the local emulators.
  ///
  /// [developmentUsesEmulatorOverride] exists for tests only, since the
  /// compile-time define cannot change inside one test run.
  static bool shouldUseEmulator(
    AppEnvironment environment, {
    bool? developmentUsesEmulatorOverride,
  }) {
    return environment == AppEnvironment.development &&
        (developmentUsesEmulatorOverride ?? developmentUsesEmulator);
  }
}
