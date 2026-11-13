import 'package:abakus_one_v2/bootstrap/app_environment.dart';
import 'package:abakus_one_v2/bootstrap/firebase_auth_emulator_config.dart';
import 'package:abakus_one_v2/bootstrap/firebase_emulator_switch.dart';
import 'package:abakus_one_v2/bootstrap/firebase_firestore_emulator_config.dart';
import 'package:abakus_one_v2/bootstrap/firebase_functions_emulator_config.dart';
import 'package:abakus_one_v2/bootstrap/firebase_storage_emulator_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FirebaseEmulatorSwitch', () {
    test('the default (no define) keeps development on the emulator', () {
      expect(FirebaseEmulatorSwitch.developmentUsesEmulator, isTrue);
      expect(
        FirebaseEmulatorSwitch.shouldUseEmulator(AppEnvironment.development),
        isTrue,
      );
    });

    test('FIREBASE_USE_EMULATOR=false sends development to the real project',
        () {
      expect(
        FirebaseEmulatorSwitch.shouldUseEmulator(
          AppEnvironment.development,
          developmentUsesEmulatorOverride: false,
        ),
        isFalse,
      );
    });

    test('staging and production never use the emulator, whatever the flag',
        () {
      for (final environment in [
        AppEnvironment.staging,
        AppEnvironment.production,
      ]) {
        for (final flag in [true, false]) {
          expect(
            FirebaseEmulatorSwitch.shouldUseEmulator(
              environment,
              developmentUsesEmulatorOverride: flag,
            ),
            isFalse,
            reason: '$environment with flag=$flag',
          );
        }
      }
    });

    test('all four service configs agree with the switch', () {
      for (final environment in AppEnvironment.values) {
        final expected = FirebaseEmulatorSwitch.shouldUseEmulator(environment);
        expect(FirebaseAuthEmulatorConfig.shouldUseEmulator(environment),
            expected);
        expect(FirebaseFirestoreEmulatorConfig.shouldUseEmulator(environment),
            expected);
        expect(FirebaseFunctionsEmulatorConfig.shouldUseEmulator(environment),
            expected);
        expect(FirebaseStorageEmulatorConfig.shouldUseEmulator(environment),
            expected);
      }
    });
  });
}
