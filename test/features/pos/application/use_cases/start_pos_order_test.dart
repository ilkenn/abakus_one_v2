import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/start_pos_order.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

void main() {
  group('StartPosOrder', () {
    test('opens a new, empty session with the given identity/context', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 10, 0));
      final useCase = StartPosOrder(clock: clock);

      final session = useCase(
        sessionId: 'session-1',
        branchId: 'branch-1',
        openedByStaffId: 'staff-1',
        channel: OrderChannel.dineInStaff,
        tableId: 'table-5',
      );

      expect(session.sessionId, 'session-1');
      expect(session.branchId, 'branch-1');
      expect(session.openedByStaffId, 'staff-1');
      expect(session.channel, OrderChannel.dineInStaff);
      expect(session.tableId, 'table-5');
      expect(session.lines, isEmpty);
    });

    test('openedAt and lastUpdatedAt both come from the injected clock', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 10, 0));
      final useCase = StartPosOrder(clock: clock);

      final session = useCase(
        sessionId: 'session-1',
        branchId: 'branch-1',
        openedByStaffId: 'staff-1',
        channel: OrderChannel.takeaway,
      );

      expect(session.openedAt, DateTime(2026, 7, 29, 10, 0));
      expect(session.lastUpdatedAt, DateTime(2026, 7, 29, 10, 0));
    });

    test('starts with zero fees/tip and a zero PriceBreakdown', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 10, 0));
      final session = StartPosOrder(clock: clock)(
        sessionId: 'session-1',
        branchId: 'branch-1',
        openedByStaffId: 'staff-1',
        channel: OrderChannel.takeaway,
      );

      expect(session.fees.isZero, isTrue);
      expect(session.tip.isZero, isTrue);
      expect(session.pricing.grandTotal.isZero, isTrue);
      expect(session.fees.currency, Currency.accountingCurrency);
    });
  });
}
