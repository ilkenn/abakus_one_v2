import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/refunds/refund_intent.dart';
import 'package:abakus_one_v2/features/orders/domain/refunds/refund_type.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RefundIntent', () {
    test('carries a full-refund request', () {
      final intent = RefundIntent(
        id: 'r1',
        orderId: OrderId('order-1'),
        paymentSessionId: 'ps1',
        refundType: RefundType.full,
        amount: Money.fromWhole(200, Currency.tryLira),
        reason: 'Customer complaint',
        requestedByStaffId: 'staff-1',
        requestedAt: DateTime(2026, 7, 29),
      );

      expect(intent.refundType, RefundType.full);
      expect(intent.amount, Money.fromWhole(200, Currency.tryLira));
    });

    test('carries a partial-refund request', () {
      final intent = RefundIntent(
        id: 'r2',
        orderId: OrderId('order-1'),
        paymentSessionId: 'ps1',
        refundType: RefundType.partial,
        amount: Money.fromWhole(50, Currency.tryLira),
        reason: 'One item missing',
        requestedByStaffId: 'staff-1',
        requestedAt: DateTime(2026, 7, 29),
      );

      expect(intent.refundType, RefundType.partial);
    });
  });
}
