import '../../bootstrap/app_environment.dart';

/// Per-[AppEnvironment] configuration values.
///
/// No backend exists yet, so most of this remains identity/policy rather
/// than live service configuration. [firebaseProjectId] reflects the three
/// Firebase projects actually provisioned in Phase 2 Sprint 1 (see
/// `docs/decisions.md` ADR-005 and `firebase.json`) — this is no longer
/// speculative. Fields describing a not-yet-real backend (e.g. an API base
/// URL) are still not added here speculatively; they land when the thing
/// they'd describe actually exists, so this class's *shape* stays stable
/// for callers rather than being redesigned when real values arrive.
class AppEnvironmentConfig {
  final AppEnvironment environment;
  final String displayName;
  final bool isProduction;

  /// The Firebase project ID this environment talks to (matches
  /// `firebase.json`'s `flutter.platforms.*.projectId` /
  /// `flutter.platforms.dart.lib/firebase_options*.dart.projectId`
  /// entries). Used by anything that needs to know which project it's
  /// pointed at without importing the generated `firebase_options*.dart`
  /// files directly (e.g. logging, diagnostics).
  final String firebaseProjectId;

  /// Whether developer-only tooling (debug logging verbosity, App Check's
  /// debug provider, local emulators, etc.) is permitted in this
  /// environment. `true` only for [AppEnvironment.development] — staging
  /// is deliberately treated like production here, since its purpose is to
  /// verify production-like behavior, not to offer a second debug surface.
  final bool allowsDebugTooling;

  const AppEnvironmentConfig({
    required this.environment,
    required this.displayName,
    required this.isProduction,
    required this.firebaseProjectId,
    required this.allowsDebugTooling,
  });

  static const AppEnvironmentConfig development = AppEnvironmentConfig(
    environment: AppEnvironment.development,
    displayName: 'Development',
    isProduction: false,
    firebaseProjectId: 'abakus-one-dev',
    allowsDebugTooling: true,
  );

  static const AppEnvironmentConfig staging = AppEnvironmentConfig(
    environment: AppEnvironment.staging,
    displayName: 'Staging',
    isProduction: false,
    firebaseProjectId: 'abakus-one-staging',
    allowsDebugTooling: false,
  );

  static const AppEnvironmentConfig production = AppEnvironmentConfig(
    environment: AppEnvironment.production,
    displayName: 'Production',
    isProduction: true,
    firebaseProjectId: 'abakusone',
    allowsDebugTooling: false,
  );

  /// The config matching [AppEnvironment.current].
  static AppEnvironmentConfig get current {
    switch (AppEnvironment.current) {
      case AppEnvironment.development:
        return development;
      case AppEnvironment.staging:
        return staging;
      case AppEnvironment.production:
        return production;
    }
  }
}
