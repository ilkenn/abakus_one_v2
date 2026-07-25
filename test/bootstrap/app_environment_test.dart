import 'package:abakus_one_v2/bootstrap/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppEnvironment.fromDefine', () {
    test('resolves "development" to AppEnvironment.development', () {
      expect(
        AppEnvironment.fromDefine('development'),
        AppEnvironment.development,
      );
    });

    test('resolves "staging" to AppEnvironment.staging', () {
      expect(AppEnvironment.fromDefine('staging'), AppEnvironment.staging);
    });

    test('resolves "production" to AppEnvironment.production', () {
      expect(
        AppEnvironment.fromDefine('production'),
        AppEnvironment.production,
      );
    });

    test('falls back to development for an unrecognized value', () {
      expect(
        AppEnvironment.fromDefine('not-a-real-environment'),
        AppEnvironment.development,
      );
    });

    test('falls back to development for an empty value', () {
      expect(AppEnvironment.fromDefine(''), AppEnvironment.development);
    });
  });

  group('AppEnvironment.current', () {
    test('defaults to development when no --dart-define is passed', () {
      // No ENVIRONMENT define is passed to the test runner, so this
      // exercises the same default path a plain `flutter run` would.
      expect(AppEnvironment.current, AppEnvironment.development);
    });
  });
}
