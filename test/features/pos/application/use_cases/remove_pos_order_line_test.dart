import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/domain/discounts/discount.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/remove_pos_order_line.dart';
import 'package:abakus_one_v2/features/pos/domain/models/discount_snapshot.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/pos_test_fixtures.dart';

void main() {
  group('RemovePosOrderLine', () {
    test('removes the line with the given draft id', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: [
          buildTestLineDraft(
            id: 'line-1',
            item: const CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
          ),
          buildTestLineDraft(
            id: 'line-2',
            item: const CartItem(id: 'p2', name: 'Ayran', desc: '', price: 25.0, quantity: 1),
          ),
        ],
      );

      final updated = RemovePosOrderLine(clock: clock)(
        session: session,
        orderLineDraftId: 'line-1',
      );

      expect(updated.lines, hasLength(1));
      expect(updated.lines.single.id, 'line-2');
    });

    test('recalculates pricing after removal', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: [
          buildTestLineDraft(
            id: 'line-1',
            item: const CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
          ),
          buildTestLineDraft(
            id: 'line-2',
            item: const CartItem(id: 'p2', name: 'Ayran', desc: '', price: 25.0, quantity: 1),
          ),
        ],
      );

      final updated = RemovePosOrderLine(clock: clock)(
        session: session,
        orderLineDraftId: 'line-2',
      );

      expect(updated.pricing.grossSubtotal.minorUnits, 10000);
    });

    test('removing the only line leaves an empty session', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: [
          buildTestLineDraft(
            id: 'line-1',
            item: const CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
          ),
        ],
      );

      final updated = RemovePosOrderLine(clock: clock)(
        session: session,
        orderLineDraftId: 'line-1',
      );

      expect(updated.lines, isEmpty);
      expect(updated.pricing.grandTotal.isZero, isTrue);
    });

    test('rejects an unknown draft id', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now());

      expect(
        () => RemovePosOrderLine(clock: clock)(
          session: session,
          orderLineDraftId: 'nonexistent',
        ),
        throwsA(isA<UnknownOrderLineDraftViolation>()),
      );
    });

    test('also drops any discount snapshot targeting the removed line', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: [
          buildTestLineDraft(
            id: 'line-1',
            item: const CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
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

      final updated = RemovePosOrderLine(clock: clock)(
        session: session,
        orderLineDraftId: 'line-1',
      );

      expect(updated.discounts, isEmpty);
    });
  });
}
