import 'package:abakus_one_v2/shared/models/money_rounding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MoneyRounding.halfAwayFromZero', () {
    test('exact division returns the exact quotient', () {
      expect(MoneyRounding.halfAwayFromZero(100, 10), 10);
      expect(MoneyRounding.halfAwayFromZero(0, 7), 0);
    });

    test('a tie (exactly .5) rounds away from zero for a positive numerator',
        () {
      // 5 / 2 = 2.5 -> rounds to 3
      expect(MoneyRounding.halfAwayFromZero(5, 2), 3);
      // 10 / 4 = 2.5 -> rounds to 3
      expect(MoneyRounding.halfAwayFromZero(10, 4), 3);
    });

    test('a tie (exactly .5) rounds away from zero for a negative numerator',
        () {
      // -5 / 2 = -2.5 -> rounds to -3
      expect(MoneyRounding.halfAwayFromZero(-5, 2), -3);
    });

    test('rounds down when the fraction is below half', () {
      // 5 / 4 = 1.25 -> rounds to 1
      expect(MoneyRounding.halfAwayFromZero(5, 4), 1);
    });

    test('rounds up when the fraction is above half', () {
      // 11 / 4 = 2.75 -> rounds to 3
      expect(MoneyRounding.halfAwayFromZero(11, 4), 3);
      // 7 / 4 = 1.75 -> rounds to 2
      expect(MoneyRounding.halfAwayFromZero(7, 4), 2);
    });

    test('a negative numerator with fraction below half rounds toward zero',
        () {
      // -5 / 4 = -1.25 -> rounds to -1
      expect(MoneyRounding.halfAwayFromZero(-5, 4), -1);
    });
  });
}
