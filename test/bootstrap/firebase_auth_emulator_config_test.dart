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
      // 127.0.0.1, not 'localhost' — see the class doc comment: the
      // Android firebase_auth plugin silently rewrites the literal string
      // 'localhost' to 10.0.2.2, which breaks a physical device reached
      // via `adb reverse`. Overridable via
      // --dart-define=FIREBASE_EMULATOR_HOST for an Android Emulator run.
      expect(FirebaseAuthEmulatorConfig.host, '127.0.0.1');
      expect(FirebaseAuthEmulatorConfig.port, 9099);
    });
  });
}
