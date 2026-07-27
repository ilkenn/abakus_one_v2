import 'package:abakus_one_v2/bootstrap/app_environment.dart';
import 'package:abakus_one_v2/core/config/app_environment_config.dart';
import 'package:abakus_one_v2/core/config/app_environment_config_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppEnvironmentConfig', () {
    test('development config has the correct identity', () {
      expect(
        AppEnvironmentConfig.development.environment,
        AppEnvironment.development,
      );
      expect(AppEnvironmentConfig.development.isProduction, isFalse);
      expect(
        AppEnvironmentConfig.development.firebaseProjectId,
        'abakus-one-dev',
      );
      expect(AppEnvironmentConfig.development.allowsDebugTooling, isTrue);
    });

    test('staging config has the correct identity', () {
      expect(
        AppEnvironmentConfig.staging.environment,
        AppEnvironment.staging,
      );
      expect(AppEnvironmentConfig.staging.isProduction, isFalse);
      expect(
        AppEnvironmentConfig.staging.firebaseProjectId,
        'abakus-one-staging',
      );
      expect(AppEnvironmentConfig.staging.allowsDebugTooling, isFalse);
    });

    test('production config has the correct identity', () {
      expect(
        AppEnvironmentConfig.production.environment,
        AppEnvironment.production,
      );
      expect(AppEnvironmentConfig.production.isProduction, isTrue);
      expect(AppEnvironmentConfig.production.firebaseProjectId, 'abakusone');
      expect(AppEnvironmentConfig.production.allowsDebugTooling, isFalse);
    });

    test('production never allows debug tooling regardless of identity', () {
      // A production safety indicator that must never flip, since it gates
      // whether App Check's debug provider (and other dev-only tooling)
      // can ever be selected — see FirebaseAppCheckService.
      expect(AppEnvironmentConfig.production.allowsDebugTooling, isFalse);
    });

    test('current resolves to the config matching AppEnvironment.current', () {
      expect(
        AppEnvironmentConfig.current.environment,
        AppEnvironment.current,
      );
    });
  });

  group('appEnvironmentConfigProvider', () {
    test('resolves to AppEnvironmentConfig.current by default', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(appEnvironmentConfigProvider),
        AppEnvironmentConfig.current,
      );
    });

    test('supports override for tests', () {
      final container = ProviderContainer(
        overrides: [
          appEnvironmentConfigProvider.overrideWithValue(
            AppEnvironmentConfig.staging,
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(appEnvironmentConfigProvider),
        AppEnvironmentConfig.staging,
      );
    });
  });
}
