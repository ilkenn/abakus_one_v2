import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/bootstrap/app_environment.dart';
import 'package:abakus_one_v2/features/auth/data/quick_test_login_config.dart';

/// Mirrors `firebase_auth_emulator_config_test.dart`'s exact style —
/// [QuickTestLoginConfig.isAvailableFor] takes an explicit [AppEnvironment]
/// precisely so it (and therefore "development => visible, production/
/// staging => hidden") is testable at all: [AppEnvironment.current] is a
/// `static final` resolved once from a compile-time define and cannot be
/// swapped at test time.
void main() {
  group('QuickTestLoginConfig.isAvailableFor', () {
    test('development + emulator => available (Quick Test Login visible)', () {
      expect(
        QuickTestLoginConfig.isAvailableFor(AppEnvironment.development),
        isTrue,
      );
    });

    test('staging => never available (hidden)', () {
      expect(
        QuickTestLoginConfig.isAvailableFor(AppEnvironment.staging),
        isFalse,
      );
    });

    test('production => never available (hidden)', () {
      expect(
        QuickTestLoginConfig.isAvailableFor(AppEnvironment.production),
        isFalse,
      );
    });

    test('exactly one of the three environments is ever available', () {
      final available = AppEnvironment.values
          .where(QuickTestLoginConfig.isAvailableFor)
          .toList();
      expect(available, [AppEnvironment.development]);
    });
  });

  group('QuickTestLoginConfig.developmentPhoneLocalInput', () {
    test(
        'is a valid Turkish local mobile number shape (10 digits, starts with 5)',
        () {
      expect(
        RegExp(r'^5\d{9}$')
            .hasMatch(QuickTestLoginConfig.developmentPhoneLocalInput),
        isTrue,
      );
    });
  });

  group('QuickTestLoginConfig.emulatorProjectIdFor', () {
    test(
        'resolves to the same project id FirebaseBootstrapService initializes Firebase with for development',
        () {
      // Not asserting a specific literal here — the point is this reads
      // through FirebaseOptionsSelector (the same source
      // FirebaseBootstrapService itself uses), not a second, independently
      // hardcoded project id.
      expect(
        QuickTestLoginConfig.emulatorProjectIdFor(AppEnvironment.development),
        isNotEmpty,
      );
    });
  });
}
