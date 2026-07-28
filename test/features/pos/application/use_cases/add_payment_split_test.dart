import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/identity/payment_split_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/add_payment_split.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/start_payment_session.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session_status.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/exchange_rate_snapshot.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

PaymentSession _startSession({Money? total}) {
  final clock = FakeClock(DateTime(2026, 7, 29, 12, 0));
  return StartPaymentSession(clock: clock).call(
    sessionId: 'ps1',
    orderId: OrderId('order-1'),
    totalAmount: total ?? Money.fromWhole(645, Currency.tryLira),
  );
}

AddPaymentSplit _useCase() =>
    AddPaymentSplit(splitIdGenerator: SequentialPaymentSplitIdGenerator());

void main() {
  group('AddPaymentSplit — same-currency', () {
    test('adds a split and stays in collecting when remaining > 0', () {
      final session = _startSession();

      final updated = _useCase()(
        session: session,
        method: PaymentMethodSeedData.cash,
        amount: Money.fromWhole(200, Currency.tryLira),
      );

      expect(updated.splits, hasLength(1));
      expect(updated.status, PaymentSessionStatus.collecting);
      expect(updated.remainingAmount, Money.fromWhole(445, Currency.tryLira));
      expect(updated.revision, 2);
    });

    test('moves to readyToComplete the instant remaining hits zero', () {
      final session = _startSession();

      final updated = _useCase()(
        session: session,
        method: PaymentMethodSeedData.cash,
        amount: Money.fromWhole(645, Currency.tryLira),
      );

      expect(updated.status, PaymentSessionStatus.readyToComplete);
      expect(updated.remainingAmount.isZero, isTrue);
    });

    test('a cash split may exceed remaining — the excess becomes change', () {
      final session = _startSession();

      final updated = _useCase()(
        session: session,
        method: PaymentMethodSeedData.cash,
        amount: Money.fromWhole(1000, Currency.tryLira),
      );

      expect(updated.status, PaymentSessionStatus.readyToComplete);
      expect(updated.remainingAmount.isZero, isTrue);
      expect(updated.changeAmount, Money.fromWhole(355, Currency.tryLira));
    });

    test('a non-cash split that would exceed remaining is rejected', () {
      final session = _startSession();

      expect(
        () => _useCase()(
          session: session,
          method: PaymentMethodSeedData.creditCard,
          amount: Money.fromWhole(1000, Currency.tryLira),
        ),
        throwsA(isA<NonCashOverpaymentViolation>()),
      );
    });

    test('splits across multiple different methods accumulate correctly', () {
      final useCase = _useCase();
      var session = _startSession();
      session = useCase(session: session, method: PaymentMethodSeedData.cash, amount: Money.fromWhole(250, Currency.tryLira));
      session = useCase(session: session, method: PaymentMethodSeedData.pluxee, amount: Money.fromWhole(300, Currency.tryLira));
      session = useCase(session: session, method: PaymentMethodSeedData.creditCard, amount: Money.fromWhole(95, Currency.tryLira));

      expect(session.splits, hasLength(3));
      expect(session.remainingAmount.isZero, isTrue);
      expect(session.status, PaymentSessionStatus.readyToComplete);
    });

    test('rejects adding a split to a session that is not editable', () {
      final session = _startSession().copyWith(status: PaymentSessionStatus.completed);

      expect(
        () => _useCase()(
          session: session,
          method: PaymentMethodSeedData.cash,
          amount: Money.fromWhole(100, Currency.tryLira),
        ),
        throwsA(isA<PaymentSessionNotEditableViolation>()),
      );
    });
  });

  group('AddPaymentSplit — foreign currency', () {
    test('callForeignCurrency settles via the exchange rate snapshot', () {
      final session = _startSession(total: Money.fromWhole(840, Currency.tryLira));
      final rate = ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.eur,
        marketSellingRate: Money.fromWhole(47, Currency.tryLira),
        rateTimestamp: DateTime(2026, 7, 29),
        rateSource: 'manual',
      );

      final updated = _useCase().callForeignCurrency(
        session: session,
        method: PaymentMethodSeedData.creditCard,
        amount: Money.fromWhole(20, Currency.eur),
        exchangeRate: rate,
      );

      expect(updated.remainingAmount.isZero, isTrue);
    });
  });
}
