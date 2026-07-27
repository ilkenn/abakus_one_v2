import 'app_environment.dart';

/// Where the local Firebase Auth Emulator listens, and which
/// [AppEnvironment] is allowed to connect to it.
///
/// [host]/[port] must stay in sync with `firebase.json`'s
/// `emulators.auth.port` by hand — `firebase.json` is read by the
/// `firebase` CLI, not by this app, so there's no single source of truth
/// to derive one from the other without adding a JSON-parsing dependency
/// for a single well-known constant. See `docs/firebase_emulator.md` for
/// the emulator startup command and setup steps.
///
/// Nothing calls [shouldUseEmulator] yet — `FirebaseAuthRepository`
/// (Sprint 4) is the first real consumer, mirroring how P1-011/P1-012
/// built `Failure`/`ErrorMapper` as tested contracts ahead of their
/// consumer. It's built and tested now so that decision is deterministic
/// and reviewable on its own, not authored inline alongside the real
/// Firebase Auth integration later.
abstract final class FirebaseAuthEmulatorConfig {
  FirebaseAuthEmulatorConfig._();

  static const String host = 'localhost';
  static const int port = 9099;

  /// Whether [environment] should connect to the local Auth Emulator
  /// instead of a real Firebase Auth backend.
  ///
  /// Only ever `true` for [AppEnvironment.development] — staging and
  /// production must always reach a real backend. The local emulator has
  /// no real security behind it (any phone number "verifies" without a
  /// real SMS) by design, exactly like `DevelopmentLocalAuthRepository`;
  /// letting staging or production connect to it would be the same class
  /// of mistake `ProductionUnavailableAuthRepository`'s `kReleaseMode`
  /// gate already exists to prevent for the mock repository, applied here
  /// to the emulator instead.
  static bool shouldUseEmulator(AppEnvironment environment) {
    return environment == AppEnvironment.development;
  }
}
