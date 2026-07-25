/// The build-time-selected environment this app instance is running as.
///
/// Selected via `--dart-define=ENVIRONMENT=<name>` at build/run time (e.g.
/// `flutter run --dart-define=ENVIRONMENT=staging`). Defaults to
/// [development] when not specified, so a plain `flutter run` during local
/// development works without requiring the flag.
///
/// No backend or per-environment Firebase project split exists yet (see
/// `docs/decisions.md` ADR-005) — this enum is the flavor-selection
/// mechanism only. Concrete per-environment values live in
/// `AppEnvironmentConfig`, not here.
enum AppEnvironment {
  development,
  staging,
  production;

  /// Resolves [value] (typically
  /// `const String.fromEnvironment('ENVIRONMENT')`) to an [AppEnvironment].
  /// An unrecognized or empty value falls back to [development] rather
  /// than throwing — a misconfigured or missing define must never crash
  /// the app, just default to the safest local-development behavior.
  static AppEnvironment fromDefine(String value) {
    return AppEnvironment.values.firstWhere(
      (environment) => environment.name == value,
      orElse: () => AppEnvironment.development,
    );
  }

  /// The environment this running app instance was built for, resolved
  /// once from the `ENVIRONMENT` compile-time define.
  static final AppEnvironment current = fromDefine(
    const String.fromEnvironment('ENVIRONMENT', defaultValue: 'development'),
  );
}
