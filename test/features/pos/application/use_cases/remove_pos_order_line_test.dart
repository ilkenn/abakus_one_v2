import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/remove_pos_order_line.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/pos_test_fixtures.dart';

void main() {
  group('RemovePosOrderLine', () {
    test('removes the line at the given index', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
          CartItem(id: 'p2', name: 'Ayran', desc: '', price: 25.0, quantity: 1),
        ],
      );

      final updated = RemovePosOrderLine(clock: clock)(
        session: session,
        lineIndex: 0,
      );

      expect(updated.lines, hasLength(1));
      expect(updated.lines.single.id, 'p2');
    });

    test('recalculates pricing after removal', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
          CartItem(id: 'p2', name: 'Ayran', desc: '', price: 25.0, quantity: 1),
        ],
      );

      final updated = RemovePosOrderLine(clock: clock)(
        session: session,
        lineIndex: 1,
      );

      expect(updated.pricing.grossSubtotal.minorUnits, 10000);
    });

    test('removing the only line leaves an empty session', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now()).copyWith(
        lines: const [
          CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
      );

      final updated = RemovePosOrderLine(clock: clock)(session: session, lineIndex: 0);

      expect(updated.lines, isEmpty);
      expect(updated.pricing.grandTotal.isZero, isTrue);
    });

    test('rejects an out-of-range line index', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now());

      expect(
        () => RemovePosOrderLine(clock: clock)(session: session, lineIndex: 0),
        throwsA(isA<RangeError>()),
      );
    });
  });
}
