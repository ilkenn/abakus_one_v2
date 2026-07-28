import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/domain/discounts/discount.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/apply_pos_discount.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/pos_test_fixtures.dart';

void main() {
  group('ApplyPosDiscount', () {
    test('sets a fixed-amount discount and recalculates the grand total', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
      );
      final discount = Discount.fixedAmount(
        id: 'd1',
        scope: DiscountScope.order,
        amount: Money.fromWhole(10, Currency.tryLira),
      );

      final updated = ApplyPosDiscount(clock: clock)(
        session: session,
        discount: discount,
      );

      expect(updated.discount, discount);
      expect(updated.pricing.discount, Money.fromWhole(10, Currency.tryLira));
      expect(updated.pricing.grandTotal, Money.fromWhole(90, Currency.tryLira));
    });

    test('a percentage discount is computed against the gross subtotal', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
      );
      const discount = Discount.percentage(
        id: 'd2',
        scope: DiscountScope.order,
        percentageBasisPoints: 1000, // 10%
      );

      final updated = ApplyPosDiscount(clock: clock)(
        session: session,
        discount: discount,
      );

      expect(updated.pricing.discount, Money.fromWhole(10, Currency.tryLira));
    });

    test('passing null clears an existing discount', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final withDiscount = buildTestSession(openedAt: clock.now()).copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
        discount: Discount.fixedAmount(
          id: 'd1',
          scope: DiscountScope.order,
          amount: Money.fromWhole(10, Currency.tryLira),
        ),
      );

      final cleared = ApplyPosDiscount(clock: clock)(
        session: withDiscount,
        discount: null,
      );

      expect(cleared.discount, isNull);
      expect(cleared.pricing.discount.isZero, isTrue);
    });
  });
}
