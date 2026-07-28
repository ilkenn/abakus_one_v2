import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/domain/discounts/discount.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/price_calculator.dart';
import 'package:abakus_one_v2/features/pos/domain/models/discount_snapshot.dart';
import 'package:abakus_one_v2/features/pos/domain/models/pos_order_line_draft.dart';
import 'package:abakus_one_v2/features/pos/domain/models/pos_order_session.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

PosOrderSession _buildSession({
  List<PosOrderLineDraft> lines = const [],
  List<DiscountSnapshot> discounts = const [],
}) {
  final now = DateTime(2026, 7, 29, 12, 0);
  return PosOrderSession(
    sessionId: 'session-1',
    openedAt: now,
    lastUpdatedAt: now,
    openedByStaffId: 'staff-1',
    branchId: 'branch-1',
    channel: OrderChannel.dineInStaff,
    lines: lines,
    discounts: discounts,
    fees: Money.zero(Currency.tryLira),
    tip: Money.zero(Currency.tryLira),
    pricing: PriceCalculator.calculate(lines: const [], currency: Currency.tryLira),
  );
}

void main() {
  group('PosOrderSession — required fields', () {
    test('openedByStaffId is the canonical staff identity field', () {
      final session = _buildSession();
      expect(session.openedByStaffId, 'staff-1');
    });

    test('carries all approved session fields', () {
      final session = _buildSession();
      expect(session.sessionId, 'session-1');
      expect(session.branchId, 'branch-1');
      expect(session.channel, OrderChannel.dineInStaff);
      expect(session.tableId, isNull);
      expect(session.tableSessionId, isNull);
      expect(session.customerNote, '');
      expect(session.kitchenNote, '');
      expect(session.discounts, isEmpty);
    });
  });

  group('PosOrderSession — immutability and defensive copying', () {
    test('the lines list is unmodifiable', () {
      final session = _buildSession(
        lines: [
          const PosOrderLineDraft(
            id: 'line-1',
            item: CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100, quantity: 1),
          ),
        ],
      );
      expect(() => session.lines.add(session.lines.first), throwsUnsupportedError);
    });

    test('mutating the source list after construction does not affect the session', () {
      final sourceLines = <PosOrderLineDraft>[
        const PosOrderLineDraft(
          id: 'line-1',
          item: CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100, quantity: 1),
        ),
      ];
      final session = _buildSession(lines: sourceLines);

      sourceLines.add(
        const PosOrderLineDraft(
          id: 'line-2',
          item: CartItem(id: 'p2', name: 'Ayran', desc: '', price: 25, quantity: 1),
        ),
      );

      expect(session.lines, hasLength(1));
    });

    test('copyWith also defensively copies a new lines list', () {
      final session = _buildSession();
      final newLines = <PosOrderLineDraft>[
        const PosOrderLineDraft(
          id: 'line-1',
          item: CartItem(id: 'p1', name: 'Bowl', desc: '', price: 100, quantity: 1),
        ),
      ];
      final updated = session.copyWith(lines: newLines);

      newLines.clear();

      expect(updated.lines, hasLength(1));
    });

    test('the discounts list is unmodifiable', () {
      final session = _buildSession(
        discounts: [
          DiscountSnapshot.fixedAmount(
            discountId: 'd1',
            discountName: 'Test',
            discountAmount: Money.fromWhole(10, Currency.tryLira),
            scope: DiscountScope.order,
            appliedByStaffId: 'staff-1',
            appliedAt: DateTime(2026, 7, 29),
          ),
        ],
      );
      expect(
        () => session.discounts.add(session.discounts.first),
        throwsUnsupportedError,
      );
    });
  });

  group('PosOrderSession — openedAt / lastUpdatedAt', () {
    test('openedAt never changes across copyWith calls', () {
      final session = _buildSession();
      final updated = session.copyWith(
        lastUpdatedAt: session.openedAt.add(const Duration(minutes: 5)),
      );
      expect(updated.openedAt, session.openedAt);
    });

    test('lastUpdatedAt updates to exactly the value copyWith is given', () {
      final session = _buildSession();
      final later = session.openedAt.add(const Duration(minutes: 10));
      final updated = session.copyWith(lastUpdatedAt: later);

      expect(updated.lastUpdatedAt, later);
      expect(updated.openedAt, session.openedAt);
    });

    test('copyWith without lastUpdatedAt preserves the previous value', () {
      final session = _buildSession();
      final updated = session.copyWith(customerNote: 'test');
      expect(updated.lastUpdatedAt, session.lastUpdatedAt);
    });
  });

  group('PosOrderSession — discounts', () {
    test('copyWith can replace the discounts list wholesale', () {
      final session = _buildSession(
        discounts: [
          DiscountSnapshot.fixedAmount(
            discountId: 'd1',
            discountName: 'Test',
            discountAmount: Money.fromWhole(10, Currency.tryLira),
            scope: DiscountScope.order,
            appliedByStaffId: 'staff-1',
            appliedAt: DateTime(2026, 7, 29),
          ),
        ],
      );
      final cleared = session.copyWith(discounts: const []);
      expect(cleared.discounts, isEmpty);
    });
  });
}
