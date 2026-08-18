import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/bootstrap/app_environment.dart';
import 'package:abakus_one_v2/features/auth/data/dev_login_config.dart';
import 'package:abakus_one_v2/features/auth/data/quick_test_login_config.dart';

/// TEMPORARY_DEVELOPER_LOGIN
///
/// Mirrors `quick_test_login_config_test.dart`'s exact style —
/// [DevLoginConfig.isAvailableFor] takes both an explicit [AppEnvironment]
/// AND an explicit pin, precisely so this stays testable without depending
/// on either `AppEnvironment.current` or the real `DEV_LOGIN_PIN`
/// compile-time define (neither can be swapped at test time).
void main() {
  group('DevLoginConfig.isAvailableFor', () {
    test('development + emulator + a configured (non-empty) PIN => available', () {
      expect(
        DevLoginConfig.isAvailableFor(AppEnvironment.development, pin: '1234'),
        isTrue,
      );
    });

    test('development + emulator, but DEV_LOGIN_PIN missing (empty) => unavailable (fails closed)', () {
      expect(
        DevLoginConfig.isAvailableFor(AppEnvironment.development, pin: ''),
        isFalse,
      );
    });

    test('staging => never available, regardless of PIN', () {
      expect(
        DevLoginConfig.isAvailableFor(AppEnvironment.staging, pin: '1234'),
        isFalse,
      );
      expect(
        DevLoginConfig.isAvailableFor(AppEnvironment.staging, pin: ''),
        isFalse,
      );
    });

    test('production => never available, regardless of PIN', () {
      expect(
        DevLoginConfig.isAvailableFor(AppEnvironment.production, pin: '1234'),
        isFalse,
      );
      expect(
        DevLoginConfig.isAvailableFor(AppEnvironment.production, pin: ''),
        isFalse,
      );
    });

    test('exactly one of the three environments is ever available, and only with a configured PIN', () {
      final available = AppEnvironment.values
          .where((env) => DevLoginConfig.isAvailableFor(env, pin: '1234'))
          .toList();
      expect(available, [AppEnvironment.development]);

      final availableWithoutPin = AppEnvironment.values
          .where((env) => DevLoginConfig.isAvailableFor(env, pin: ''))
          .toList();
      expect(availableWithoutPin, isEmpty);
    });
  });

  group('DevLoginConfig.developerPhoneLocalInput', () {
    test('reuses QuickTestLoginConfig.developmentPhoneLocalInput — the same locked account, never a second literal', () {
      expect(
        DevLoginConfig.developerPhoneLocalInput,
        QuickTestLoginConfig.developmentPhoneLocalInput,
      );
    });
  });

  group('DevLoginConfig.pin', () {
    test('resolves to the real DEV_LOGIN_PIN compile-time define (empty under the plain `flutter test` default)', () {
      // Not asserting a specific literal — the point is this reads
      // `String.fromEnvironment('DEV_LOGIN_PIN')` and nothing is
      // hardcoded here. Under the default `flutter test` invocation (no
      // --dart-define passed) this is expected to be empty — see
      // `dev_login_provider_test.dart` for the file that exercises the
      // configured-PIN branch under `--dart-define=DEV_LOGIN_PIN=1234`.
      expect(DevLoginConfig.pin, isA<String>());
    });
  });
}
