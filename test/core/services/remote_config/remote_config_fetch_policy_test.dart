import 'package:abakus_one_v2/bootstrap/app_environment.dart';
import 'package:abakus_one_v2/core/services/remote_config/remote_config_fetch_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteConfigFetchPolicy.forEnvironment', () {
    test('development uses a short, iteration-friendly minimum fetch interval',
        () {
      final policy = RemoteConfigFetchPolicy.forEnvironment(
        AppEnvironment.development,
      );
      expect(policy.minimumFetchInterval, const Duration(minutes: 1));
    });

    test('production uses a conservative minimum fetch interval', () {
      final policy = RemoteConfigFetchPolicy.forEnvironment(
        AppEnvironment.production,
      );
      expect(policy.minimumFetchInterval, const Duration(hours: 12));
    });

    test('staging is stricter than development but looser than production', () {
      final development = RemoteConfigFetchPolicy.forEnvironment(
        AppEnvironment.development,
      );
      final staging = RemoteConfigFetchPolicy.forEnvironment(
        AppEnvironment.staging,
      );
      final production = RemoteConfigFetchPolicy.forEnvironment(
        AppEnvironment.production,
      );

      expect(
        staging.minimumFetchInterval,
        greaterThan(development.minimumFetchInterval),
      );
      expect(
        staging.minimumFetchInterval,
        lessThan(production.minimumFetchInterval),
      );
    });

    test('every environment has a positive fetch timeout', () {
      for (final environment in AppEnvironment.values) {
        final policy = RemoteConfigFetchPolicy.forEnvironment(environment);
        expect(policy.fetchTimeout, greaterThan(Duration.zero));
      }
    });
  });
}
