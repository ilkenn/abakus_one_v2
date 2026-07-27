import '../../../bootstrap/app_environment.dart';

/// How aggressively [FirebaseRemoteConfigService] is allowed to re-fetch
/// from the Remote Config backend for a given [AppEnvironment] — a pure,
/// environment-driven policy with no Firebase dependency, so it's testable
/// without the SDK.
class RemoteConfigFetchPolicy {
  const RemoteConfigFetchPolicy({
    required this.fetchTimeout,
    required this.minimumFetchInterval,
  });

  /// Maximum time to wait for a single fetch before giving up.
  final Duration fetchTimeout;

  /// Minimum age a cached config must reach before a new fetch is allowed
  /// to hit the network again (Remote Config's own client-side throttle).
  final Duration minimumFetchInterval;

  /// Development gets a short interval so flag changes are visible almost
  /// immediately while iterating locally. Staging is treated production-
  /// like (it exists to verify production behavior, not to offer a faster
  /// debug loop) but with a shorter interval than production so QA sees
  /// changes within the working day rather than waiting up to 12 hours.
  /// Production uses Firebase's own recommended conservative interval to
  /// avoid unnecessary load/cost at scale.
  static RemoteConfigFetchPolicy forEnvironment(AppEnvironment environment) {
    switch (environment) {
      case AppEnvironment.development:
        return const RemoteConfigFetchPolicy(
          fetchTimeout: Duration(seconds: 10),
          minimumFetchInterval: Duration(minutes: 1),
        );
      case AppEnvironment.staging:
        return const RemoteConfigFetchPolicy(
          fetchTimeout: Duration(seconds: 30),
          minimumFetchInterval: Duration(hours: 1),
        );
      case AppEnvironment.production:
        return const RemoteConfigFetchPolicy(
          fetchTimeout: Duration(seconds: 30),
          minimumFetchInterval: Duration(hours: 12),
        );
    }
  }
}
