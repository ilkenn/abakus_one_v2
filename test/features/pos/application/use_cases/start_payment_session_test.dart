import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/start_payment_session.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

void main() {
  group('StartPaymentSession', () {
    test('builds a session at collecting status, revision 1, no splits', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = StartPaymentSession(clock: clock).call(
        sessionId: 'ps1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(100, Currency.tryLira),
      );

      expect(session.id, 'ps1');
      expect(session.status, PaymentSessionStatus.collecting);
      expect(session.revision, 1);
      expect(session.splits, isEmpty);
      expect(session.remainingAmount, Money.fromWhole(100, Currency.tryLira));
      expect(session.createdAt, DateTime(2026, 7, 29, 12, 0));
    });
  });
}
