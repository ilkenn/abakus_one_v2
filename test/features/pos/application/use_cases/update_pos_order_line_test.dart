import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/update_pos_order_line.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/pos_test_fixtures.dart';

void main() {
  group('UpdatePosOrderLine', () {
    test('updates the quantity of the line with the given draft id', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: [
          buildTestLineDraft(
            id: 'line-1',
            item: const CartItem(
                id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
          ),
        ],
      );

      final updated = UpdatePosOrderLine(clock: clock)(
        session: session,
        orderLineDraftId: 'line-1',
        quantity: 3,
      );

      expect(updated.lines.single.item.quantity, 3);
    });

    test('updates the note of the line with the given draft id', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: [
          buildTestLineDraft(
            id: 'line-1',
            item: const CartItem(
                id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
          ),
        ],
      );

      final updated = UpdatePosOrderLine(clock: clock)(
        session: session,
        orderLineDraftId: 'line-1',
        note: 'Az baharatlı',
      );

      expect(updated.lines.single.item.note, 'Az baharatlı');
    });

    test('recalculates pricing after a quantity change', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: [
          buildTestLineDraft(
            id: 'line-1',
            item: const CartItem(
                id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
          ),
        ],
      );

      final updated = UpdatePosOrderLine(clock: clock)(
        session: session,
        orderLineDraftId: 'line-1',
        quantity: 2,
      );

      // 100.00 TRY x 2 = 200.00 TRY = 20000 minor units.
      expect(updated.pricing.grossSubtotal.minorUnits, 20000);
      expect(
          updated.pricing.grossSubtotal, isNot(session.pricing.grossSubtotal));
    });

    test('rejects a non-positive quantity', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: [
          buildTestLineDraft(
            id: 'line-1',
            item: const CartItem(
                id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
          ),
        ],
      );

      expect(
        () => UpdatePosOrderLine(clock: clock)(
          session: session,
          orderLineDraftId: 'line-1',
          quantity: 0,
        ),
        throwsA(isA<NonPositiveQuantityViolation>()),
      );
    });

    test('rejects an unknown draft id', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now());

      expect(
        () => UpdatePosOrderLine(clock: clock)(
          session: session,
          orderLineDraftId: 'nonexistent',
          quantity: 1,
        ),
        throwsA(isA<UnknownOrderLineDraftViolation>()),
      );
    });
  });
}
