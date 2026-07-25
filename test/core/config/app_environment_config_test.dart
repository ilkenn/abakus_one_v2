import 'package:abakus_one_v2/bootstrap/app_environment.dart';
import 'package:abakus_one_v2/core/config/app_environment_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppEnvironmentConfig', () {
    test('development config has the correct identity', () {
      expect(
        AppEnvironmentConfig.development.environment,
        AppEnvironment.development,
      );
      expect(AppEnvironmentConfig.development.isProduction, isFalse);
    });

    test('staging config has the correct identity', () {
      expect(
        AppEnvironmentConfig.staging.environment,
        AppEnvironment.staging,
      );
      expect(AppEnvironmentConfig.staging.isProduction, isFalse);
    });

    test('production config has the correct identity', () {
      expect(
        AppEnvironmentConfig.production.environment,
        AppEnvironment.production,
      );
      expect(AppEnvironmentConfig.production.isProduction, isTrue);
    });

    test('current resolves to the config matching AppEnvironment.current', () {
      expect(
        AppEnvironmentConfig.current.environment,
        AppEnvironment.current,
      );
    });
  });
}
