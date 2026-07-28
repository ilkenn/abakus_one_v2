import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/domain/discounts/discount.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/calculate_pos_order_totals.dart';
import 'package:abakus_one_v2/features/pos/domain/models/discount_snapshot.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/pos_test_fixtures.dart';

void main() {
  group('CalculatePosOrderTotals', () {
    test('computes gross subtotal and grand total from session lines', () {
      final session = buildTestSession().copyWith(
        lines: [
          buildTestLineDraft(
            item: const CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 2),
          ),
        ],
      );

      final pricing = const CalculatePosOrderTotals()(session);

      expect(pricing.grossSubtotal, Money.fromWhole(200, Currency.tryLira));
      expect(pricing.grandTotal, Money.fromWhole(200, Currency.tryLira));
    });

    test('includes fees and tip in the grand total', () {
      final session = buildTestSession().copyWith(
        lines: [
          buildTestLineDraft(
            item: const CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
          ),
        ],
        fees: Money.fromWhole(5, Currency.tryLira),
        tip: Money.fromWhole(15, Currency.tryLira),
      );

      final pricing = const CalculatePosOrderTotals()(session);

      // 100 + 5 (fees, via serviceFee) + 15 (tip) = 120.
      expect(pricing.grandTotal, Money.fromWhole(120, Currency.tryLira));
      expect(pricing.serviceFee, Money.fromWhole(5, Currency.tryLira));
      expect(pricing.tip, Money.fromWhole(15, Currency.tryLira));
    });

    test('applies the active order-scoped discount snapshot against the gross subtotal', () {
      final session = buildTestSession().copyWith(
        lines: [
          buildTestLineDraft(
            item: const CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
          ),
        ],
        discounts: [
          DiscountSnapshot.fixedAmount(
            discountId: 'd1',
            discountName: 'Manager comp',
            discountAmount: Money.fromWhole(20, Currency.tryLira),
            scope: DiscountScope.order,
            appliedByStaffId: 'staff-1',
            appliedAt: DateTime(2026, 7, 29),
          ),
        ],
      );

      final pricing = const CalculatePosOrderTotals()(session);

      expect(pricing.grandTotal, Money.fromWhole(80, Currency.tryLira));
    });

    test('applies a line-scoped discount snapshot only to its own line', () {
      final session = buildTestSession().copyWith(
        lines: [
          buildTestLineDraft(
            id: 'line-1',
            item: const CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
          ),
          buildTestLineDraft(
            id: 'line-2',
            item: const CartItem(id: 'p2', name: 'Ayran', desc: '', price: 50.0, quantity: 1),
          ),
        ],
        discounts: [
          DiscountSnapshot.percentage(
            discountId: 'd1',
            discountName: '%10',
            percentageBasisPoints: 1000,
            discountAmount: Money.fromWhole(10, Currency.tryLira),
            scope: DiscountScope.line,
            targetOrderLineId: 'line-1',
            appliedByStaffId: 'staff-1',
            appliedAt: DateTime(2026, 7, 29),
          ),
        ],
      );

      final pricing = const CalculatePosOrderTotals()(session);

      // line-1: 100 - 10 = 90; line-2: 50 unaffected. Total = 140.
      expect(pricing.grossSubtotal, Money.fromWhole(140, Currency.tryLira));
    });

    test('never invents an OrderId/OrderNumber (pure preview, no CartToOrderMapper call)', () {
      // If this were implemented via CartToOrderMapper.map(), an empty
      // session would throw EmptyOrderViolation. It must not.
      final session = buildTestSession();

      expect(() => const CalculatePosOrderTotals()(session), returnsNormally);
    });

    test('an empty session produces a zero breakdown', () {
      final session = buildTestSession();

      final pricing = const CalculatePosOrderTotals()(session);

      expect(pricing.grandTotal.isZero, isTrue);
    });
  });
}
