import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/bootstrap/app_environment.dart';
import 'package:abakus_one_v2/bootstrap/firebase_functions_emulator_config.dart';

/// Faz — Dev Functions Emulator Routing Audit. Closes a real, pre-existing
/// coverage gap: every other `FirebaseXEmulatorConfig` (Auth, at least) has
/// a dedicated test file proving `shouldUseEmulator` is development-only;
/// `FirebaseFunctionsEmulatorConfig` had none, so its production/staging
/// exclusion was previously true by code inspection only, never verified.
void main() {
  group('FirebaseFunctionsEmulatorConfig.shouldUseEmulator', () {
    test('development connects to the emulator', () {
      expect(
        FirebaseFunctionsEmulatorConfig.shouldUseEmulator(
          AppEnvironment.development,
        ),
        isTrue,
      );
    });

    test('staging never connects to the emulator', () {
      expect(
        FirebaseFunctionsEmulatorConfig.shouldUseEmulator(
          AppEnvironment.staging,
        ),
        isFalse,
      );
    });

    test('production never connects to the emulator', () {
      expect(
        FirebaseFunctionsEmulatorConfig.shouldUseEmulator(
          AppEnvironment.production,
        ),
        isFalse,
      );
    });

    test('exactly one of the three environments uses the emulator', () {
      final usingEmulator = AppEnvironment.values
          .where(FirebaseFunctionsEmulatorConfig.shouldUseEmulator)
          .toList();
      expect(usingEmulator, [AppEnvironment.development]);
    });
  });

  group('FirebaseFunctionsEmulatorConfig host/port', () {
    test('matches the documented, firebase.json-synchronized values', () {
      // 127.0.0.1, not 'localhost' — same physical-device-via-adb-reverse
      // reasoning as FirebaseAuthEmulatorConfig. Port 5001 matches
      // firebase.json's emulators.functions.port and the region Cloud
      // Functions v2 `onCall` defaults to when no `region` option is set
      // (`deliveryPlaces.ts` sets none) — us-central1 both sides, so
      // FirebaseFunctions.instance's own default region already matches
      // without this app ever calling `instanceFor(region: ...)`.
      expect(FirebaseFunctionsEmulatorConfig.host, '127.0.0.1');
      expect(FirebaseFunctionsEmulatorConfig.port, 5001);
    });
  });
}
