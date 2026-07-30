import 'package:abakus_one_v2/features/courier/domain/location/traffic_multiplier_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoOpTrafficMultiplierProvider', () {
    test('always returns 1.0', () {
      const provider = NoOpTrafficMultiplierProvider();
      expect(provider.multiplierFor(DateTime(2026, 1, 1, 8)), 1.0);
      expect(provider.multiplierFor(DateTime(2026, 1, 1, 23)), 1.0);
    });
  });

  group('TimeOfDayTrafficMultiplierProvider', () {
    test('applies the rush-hour multiplier inside a configured window', () {
      const provider = TimeOfDayTrafficMultiplierProvider();
      expect(provider.multiplierFor(DateTime(2026, 1, 1, 8)), 1.4);
      expect(provider.multiplierFor(DateTime(2026, 1, 1, 18)), 1.4);
    });

    test('returns 1.0 outside every configured window', () {
      const provider = TimeOfDayTrafficMultiplierProvider();
      expect(provider.multiplierFor(DateTime(2026, 1, 1, 3)), 1.0);
      expect(provider.multiplierFor(DateTime(2026, 1, 1, 12)), 1.0);
    });

    test('window bounds are start-inclusive, end-exclusive', () {
      const provider = TimeOfDayTrafficMultiplierProvider();
      expect(provider.multiplierFor(DateTime(2026, 1, 1, 7)), 1.4);
      expect(provider.multiplierFor(DateTime(2026, 1, 1, 9)), 1.0);
    });

    test(
        'windows and multiplier are adjustable via the constructor, '
        'never hardcoded', () {
      const provider = TimeOfDayTrafficMultiplierProvider(
        rushHourWindows: [(startHour: 22, endHour: 23)],
        rushHourMultiplier: 2.0,
      );
      expect(provider.multiplierFor(DateTime(2026, 1, 1, 22)), 2.0);
      expect(provider.multiplierFor(DateTime(2026, 1, 1, 8)), 1.0);
    });
  });
}
