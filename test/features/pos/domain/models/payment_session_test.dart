import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/payment/payment_split.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_snapshot.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/exchange_rate_snapshot.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cashSnapshot =
      PaymentMethodSnapshot.capture(PaymentMethodSeedData.cash);
  final cardSnapshot =
      PaymentMethodSnapshot.capture(PaymentMethodSeedData.creditCard);

  group('PaymentSession — split payment', () {
    test("totalSettled sums every split's settlementAmount", () {
      final session = PaymentSession(
        id: 'ps1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(200, Currency.tryLira),
        status: PaymentSessionStatus.collecting,
        splits: [
          PaymentSplit.tryLira(
            id: 's1',
            methodSnapshot: cashSnapshot,
            amount: Money.fromWhole(100, Currency.tryLira),
          ),
          PaymentSplit.tryLira(
            id: 's2',
            methodSnapshot: cardSnapshot,
            amount: Money.fromWhole(100, Currency.tryLira),
          ),
        ],
        createdAt: DateTime(2026, 7, 28),
        revision: 1,
      );

      expect(session.totalSettled, Money.fromWhole(200, Currency.tryLira));
      expect(session.isFullySettled, isTrue);
      expect(session.remainingAmount.isZero, isTrue);
    });

    test('isFullySettled is false when splits sum to less than totalAmount',
        () {
      final session = PaymentSession(
        id: 'ps1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(200, Currency.tryLira),
        status: PaymentSessionStatus.collecting,
        splits: [
          PaymentSplit.tryLira(
            id: 's1',
            methodSnapshot: cashSnapshot,
            amount: Money.fromWhole(100, Currency.tryLira),
          ),
        ],
        createdAt: DateTime(2026, 7, 28),
        revision: 1,
      );

      expect(session.isFullySettled, isFalse);
      expect(session.remainingAmount, Money.fromWhole(100, Currency.tryLira));
    });

    test('a mixed TRY + foreign-currency split settles correctly', () {
      final snapshot = ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.eur,
        marketSellingRate: Money.fromWhole(47, Currency.tryLira),
        rateTimestamp: DateTime(2026, 7, 28),
        rateSource: 'manual',
      );
      final session = PaymentSession(
        id: 'ps1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(900, Currency.tryLira),
        status: PaymentSessionStatus.collecting,
        splits: [
          PaymentSplit.tryLira(
            id: 's1',
            methodSnapshot: cashSnapshot,
            amount: Money.fromWhole(60, Currency.tryLira),
          ),
          PaymentSplit.foreignCurrency(
            id: 's2',
            methodSnapshot: cardSnapshot,
            amount: Money.fromWhole(20, Currency.eur),
            exchangeRate: snapshot,
          ),
        ],
        createdAt: DateTime(2026, 7, 28),
        revision: 1,
      );

      // 60 TRY + (20 EUR -> 840 TRY) = 900 TRY
      expect(session.totalSettled, Money.fromWhole(900, Currency.tryLira));
      expect(session.isFullySettled, isTrue);
    });

    test('with no splits, totalSettled is zero and remaining equals total', () {
      final session = PaymentSession(
        id: 'ps1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(100, Currency.tryLira),
        status: PaymentSessionStatus.collecting,
        createdAt: DateTime(2026, 7, 28),
        revision: 1,
      );

      expect(session.totalSettled, Money.zero(Currency.tryLira));
      expect(session.isFullySettled, isFalse);
      expect(session.remainingAmount, Money.fromWhole(100, Currency.tryLira));
      expect(session.changeAmount.isZero, isTrue);
    });
  });

  group('PaymentSession — cash overpay and change', () {
    test('a cash overpay produces change and zero remaining', () {
      final session = PaymentSession(
        id: 'ps1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(645, Currency.tryLira),
        status: PaymentSessionStatus.collecting,
        splits: [
          PaymentSplit.tryLira(
            id: 's1',
            methodSnapshot: cashSnapshot,
            amount: Money.fromWhole(1000, Currency.tryLira),
          ),
        ],
        createdAt: DateTime(2026, 7, 28),
        revision: 1,
      );

      expect(session.totalSettled, Money.fromWhole(1000, Currency.tryLira));
      expect(session.remainingAmount.isZero, isTrue);
      expect(session.changeAmount, Money.fromWhole(355, Currency.tryLira));
      expect(session.isFullySettled, isTrue);
    });
  });

  group('PaymentSession — revision', () {
    test('copyWith without a revision override preserves it', () {
      final session = PaymentSession(
        id: 'ps1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(100, Currency.tryLira),
        status: PaymentSessionStatus.collecting,
        createdAt: DateTime(2026, 7, 28),
        revision: 3,
      );

      final updated = session.copyWith(status: PaymentSessionStatus.cancelled);

      expect(updated.revision, 3);
      expect(updated.status, PaymentSessionStatus.cancelled);
    });

    test('copyWith can bump the revision explicitly', () {
      final session = PaymentSession(
        id: 'ps1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(100, Currency.tryLira),
        status: PaymentSessionStatus.collecting,
        createdAt: DateTime(2026, 7, 28),
        revision: 1,
      );

      final updated = session.copyWith(revision: session.revision + 1);

      expect(updated.revision, 2);
    });
  });
}
