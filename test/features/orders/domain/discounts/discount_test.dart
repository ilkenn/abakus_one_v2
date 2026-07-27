import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/discounts/discount.dart';
import 'package:abakus_one_v2/features/orders/domain/discounts/discount_stacking_policy.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Discount.fixedAmount', () {
    test('reduces the base by the fixed amount', () {
      final discount = Discount.fixedAmount(
        id: 'd1',
        scope: DiscountScope.order,
        amount: Money.fromWhole(20, Currency.tryLira),
      );

      expect(
        discount.amountFor(Money.fromWhole(100, Currency.tryLira)),
        Money.fromWhole(20, Currency.tryLira),
      );
    });

    test('never exceeds the base amount even if the fixed amount is larger',
        () {
      final discount = Discount.fixedAmount(
        id: 'd1',
        scope: DiscountScope.line,
        amount: Money.fromWhole(200, Currency.tryLira),
      );

      expect(
        discount.amountFor(Money.fromWhole(50, Currency.tryLira)),
        Money.fromWhole(50, Currency.tryLira),
      );
    });
  });

  group('Discount.percentage', () {
    test('computes a percentage of the base, rounded half away from zero', () {
      const discount = Discount.percentage(
        id: 'd2',
        scope: DiscountScope.order,
        percentageBasisPoints: 1000, // 10%
      );

      expect(
        discount.amountFor(Money.fromWhole(100, Currency.tryLira)),
        Money.fromWhole(10, Currency.tryLira),
      );
    });

    test('a 100% discount reduces the base to zero, never negative', () {
      const discount = Discount.percentage(
        id: 'd3',
        scope: DiscountScope.order,
        percentageBasisPoints: 10000,
      );

      expect(
        discount.amountFor(Money.fromWhole(75, Currency.tryLira)),
        Money.fromWhole(75, Currency.tryLira),
      );
    });
  });

  group('SingleDiscountOnlyPolicy', () {
    const policy = SingleDiscountOnlyPolicy();

    test('zero discounts pass through unchanged', () {
      expect(policy.resolve(const []), isEmpty);
    });

    test('exactly one discount passes through unchanged', () {
      final discount = Discount.fixedAmount(
        id: 'd1',
        scope: DiscountScope.order,
        amount: Money.fromWhole(10, Currency.tryLira),
      );
      expect(policy.resolve([discount]), [discount]);
    });

    test(
        'more than one discount is rejected (stacking is unresolved, not guessed)',
        () {
      final a = Discount.fixedAmount(
        id: 'a',
        scope: DiscountScope.order,
        amount: Money.fromWhole(10, Currency.tryLira),
      );
      const b = Discount.percentage(
        id: 'b',
        scope: DiscountScope.order,
        percentageBasisPoints: 500,
      );

      expect(
        () => policy.resolve([a, b]),
        throwsA(isA<MultipleDiscountsNotSupportedViolation>()),
      );
    });
  });
}
