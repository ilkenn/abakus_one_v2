import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/discounts/discount.dart';
import 'package:abakus_one_v2/features/pos/domain/models/discount_snapshot.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiscountSnapshot.percentage', () {
    test('a line-scoped snapshot requires a targetOrderLineId', () {
      expect(
        () => DiscountSnapshot.percentage(
          discountId: 'd1',
          discountName: '%10',
          percentageBasisPoints: 1000,
          discountAmount: Money.fromWhole(10, Currency.tryLira),
          scope: DiscountScope.line,
          appliedByStaffId: 'staff-1',
          appliedAt: DateTime(2026, 7, 28),
        ),
        throwsA(isA<LineDiscountMissingTargetViolation>()),
      );
    });

    test('an order-scoped snapshot must not carry a targetOrderLineId', () {
      expect(
        () => DiscountSnapshot.percentage(
          discountId: 'd1',
          discountName: '%10',
          percentageBasisPoints: 1000,
          discountAmount: Money.fromWhole(10, Currency.tryLira),
          scope: DiscountScope.order,
          targetOrderLineId: 'line-1',
          appliedByStaffId: 'staff-1',
          appliedAt: DateTime(2026, 7, 28),
        ),
        throwsA(isA<OrderDiscountMustNotTargetLineViolation>()),
      );
    });

    test('a valid line-scoped snapshot constructs successfully', () {
      final snapshot = DiscountSnapshot.percentage(
        discountId: 'd1',
        discountName: '%10',
        percentageBasisPoints: 1000,
        discountAmount: Money.fromWhole(10, Currency.tryLira),
        scope: DiscountScope.line,
        targetOrderLineId: 'line-1',
        appliedByStaffId: 'staff-1',
        appliedAt: DateTime(2026, 7, 28),
      );

      expect(snapshot.targetOrderLineId, 'line-1');
      expect(snapshot.type, DiscountType.percentage);
      expect(snapshot.percentageBasisPoints, 1000);
    });
  });

  group('DiscountSnapshot.fixedAmount', () {
    test('a valid order-scoped snapshot has no percentageBasisPoints', () {
      final snapshot = DiscountSnapshot.fixedAmount(
        discountId: 'd2',
        discountName: 'Manager comp',
        discountAmount: Money.fromWhole(20, Currency.tryLira),
        scope: DiscountScope.order,
        appliedByStaffId: 'staff-1',
        appliedAt: DateTime(2026, 7, 28),
      );

      expect(snapshot.type, DiscountType.fixedAmount);
      expect(snapshot.percentageBasisPoints, isNull);
      expect(snapshot.targetOrderLineId, isNull);
    });
  });
}
