import '../../bootstrap/app_environment.dart';

/// Per-[AppEnvironment] configuration values.
///
/// No backend exists yet and no dev/staging/production Firebase project
/// split has been provisioned (see `docs/decisions.md` ADR-005) — every
/// value below is deliberately limited to what's actually known today
/// (environment identity, display name, production status). Fields like an
/// API base URL or a per-environment Firebase project alias are not added
/// here speculatively; they land when the backend/project split they'd
/// describe actually exists, so this class's *shape* stays stable for
/// callers rather than being redesigned when real values arrive.
class AppEnvironmentConfig {
  final AppEnvironment environment;
  final String displayName;
  final bool isProduction;

  const AppEnvironmentConfig({
    required this.environment,
    required this.displayName,
    required this.isProduction,
  });

  static const AppEnvironmentConfig development = AppEnvironmentConfig(
    environment: AppEnvironment.development,
    displayName: 'Development',
    isProduction: false,
  );

  static const AppEnvironmentConfig staging = AppEnvironmentConfig(
    environment: AppEnvironment.staging,
    displayName: 'Staging',
    isProduction: false,
  );

  static const AppEnvironmentConfig production = AppEnvironmentConfig(
    environment: AppEnvironment.production,
    displayName: 'Production',
    isProduction: true,
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
