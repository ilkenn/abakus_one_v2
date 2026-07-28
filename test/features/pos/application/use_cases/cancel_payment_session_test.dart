import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/cancel_payment_session.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/start_payment_session.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

void main() {
  group('CancelPaymentSession', () {
    test('cancels a collecting session', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = StartPaymentSession(clock: clock).call(
        sessionId: 'ps1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(100, Currency.tryLira),
      );

      final cancelled = const CancelPaymentSession()(
        session: session,
        expectedRevision: session.revision,
      );

      expect(cancelled.status, PaymentSessionStatus.cancelled);
      expect(cancelled.revision, session.revision + 1);
    });

    test('rejects a stale expectedRevision', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = StartPaymentSession(clock: clock).call(
        sessionId: 'ps1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(100, Currency.tryLira),
      );

      expect(
        () => const CancelPaymentSession()(
          session: session,
          expectedRevision: session.revision + 1,
        ),
        throwsA(isA<StaleRevisionViolation>()),
      );
    });

    test('rejects cancelling an already-completed session', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = StartPaymentSession(clock: clock)
          .call(
            sessionId: 'ps1',
            orderId: OrderId('order-1'),
            totalAmount: Money.fromWhole(100, Currency.tryLira),
          )
          .copyWith(status: PaymentSessionStatus.completed);

      expect(
        () => const CancelPaymentSession()(
          session: session,
          expectedRevision: session.revision,
        ),
        throwsA(isA<InvalidPaymentSessionStatusTransitionViolation>()),
      );
    });

    test('rejects cancelling an already-cancelled session', () {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = StartPaymentSession(clock: clock)
          .call(
            sessionId: 'ps1',
            orderId: OrderId('order-1'),
            totalAmount: Money.fromWhole(100, Currency.tryLira),
          )
          .copyWith(status: PaymentSessionStatus.cancelled);

      expect(
        () => const CancelPaymentSession()(
          session: session,
          expectedRevision: session.revision,
        ),
        throwsA(isA<InvalidPaymentSessionStatusTransitionViolation>()),
      );
    });
  });
}
