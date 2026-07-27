import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/bootstrap/app_environment.dart';
import 'package:abakus_one_v2/bootstrap/firebase_auth_emulator_config.dart';

void main() {
  group('FirebaseAuthEmulatorConfig.shouldUseEmulator', () {
    test('development connects to the emulator', () {
      expect(
        FirebaseAuthEmulatorConfig.shouldUseEmulator(
          AppEnvironment.development,
        ),
        isTrue,
      );
    });

    test('staging never connects to the emulator', () {
      expect(
        FirebaseAuthEmulatorConfig.shouldUseEmulator(AppEnvironment.staging),
        isFalse,
      );
    });

    test('production never connects to the emulator', () {
      expect(
        FirebaseAuthEmulatorConfig.shouldUseEmulator(
          AppEnvironment.production,
        ),
        isFalse,
      );
    });

    test('exactly one of the three environments uses the emulator', () {
      final usingEmulator = AppEnvironment.values
          .where(FirebaseAuthEmulatorConfig.shouldUseEmulator)
          .toList();
      expect(usingEmulator, [AppEnvironment.development]);
    });
  });

  group('FirebaseAuthEmulatorConfig host/port', () {
    test('matches the documented, firebase.json-synchronized values', () {
      expect(FirebaseAuthEmulatorConfig.host, 'localhost');
      expect(FirebaseAuthEmulatorConfig.port, 9099);
    });
  });
}
