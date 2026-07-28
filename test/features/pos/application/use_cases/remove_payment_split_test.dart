import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/identity/payment_split_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/add_payment_split.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/remove_payment_split.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/start_payment_session.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session_status.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

void main() {
  group('RemovePaymentSplit', () {
    PaymentSession buildSessionWithOneSplit() {
      final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
      final session = StartPaymentSession(clock: clock).call(
        sessionId: 'ps1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(645, Currency.tryLira),
      );
      return AddPaymentSplit(
          splitIdGenerator: SequentialPaymentSplitIdGenerator())(
        session: session,
        method: PaymentMethodSeedData.cash,
        amount: Money.fromWhole(645, Currency.tryLira),
      );
    }

    test('removes the split and drops back to collecting', () {
      final session = buildSessionWithOneSplit();
      expect(session.status, PaymentSessionStatus.readyToComplete);
      final splitId = session.splits.single.id;

      final updated =
          const RemovePaymentSplit()(session: session, splitId: splitId);

      expect(updated.splits, isEmpty);
      expect(updated.status, PaymentSessionStatus.collecting);
      expect(updated.remainingAmount, Money.fromWhole(645, Currency.tryLira));
    });

    test('rejects an unknown splitId', () {
      final session = buildSessionWithOneSplit();

      expect(
        () => const RemovePaymentSplit()(
            session: session, splitId: 'nonexistent'),
        throwsA(isA<UnknownPaymentSplitViolation>()),
      );
    });

    test('rejects removal from a non-editable session', () {
      final session = buildSessionWithOneSplit().copyWith(
        status: PaymentSessionStatus.completed,
      );

      expect(
        () => const RemovePaymentSplit()(
          session: session,
          splitId: session.splits.single.id,
        ),
        throwsA(isA<PaymentSessionNotEditableViolation>()),
      );
    });
  });
}
