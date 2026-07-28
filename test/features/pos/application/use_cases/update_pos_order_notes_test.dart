import 'package:abakus_one_v2/features/pos/application/use_cases/update_pos_order_notes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/pos_test_fixtures.dart';

void main() {
  group('UpdatePosOrderNotes', () {
    test('updates customerNote and kitchenNote independently', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now());

      final withCustomerNote = UpdatePosOrderNotes(clock: clock)(
        session: session,
        customerNote: 'Zile basmayın',
      );
      expect(withCustomerNote.customerNote, 'Zile basmayın');
      expect(withCustomerNote.kitchenNote, '');

      final withKitchenNote = UpdatePosOrderNotes(clock: clock)(
        session: withCustomerNote,
        kitchenNote: 'Acil',
      );
      expect(withKitchenNote.customerNote, 'Zile basmayın');
      expect(withKitchenNote.kitchenNote, 'Acil');
    });

    test('does not affect pricing', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now());

      final updated = UpdatePosOrderNotes(clock: clock)(
        session: session,
        customerNote: 'Test',
      );

      expect(updated.pricing.grandTotal, session.pricing.grandTotal);
    });

    test('bumps lastUpdatedAt via the injected clock', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = buildTestSession(openedAt: clock.now());
      clock.advance(const Duration(minutes: 1));

      final updated = UpdatePosOrderNotes(clock: clock)(
        session: session,
        kitchenNote: 'Test',
      );

      expect(updated.lastUpdatedAt, DateTime(2026, 7, 29, 12, 1));
    });
  });
}
