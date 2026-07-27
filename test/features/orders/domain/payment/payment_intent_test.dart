import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/orders/domain/payment/payment_intent.dart';
import 'package:abakus_one_v2/features/orders/domain/payment/payment_split.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_enums.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/exchange_rate_snapshot.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentIntent — split payment', () {
    test('totalSettled sums every split\'s settlementAmount', () {
      final intent = PaymentIntent(
        id: 'pi1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(200, Currency.tryLira),
        status: PaymentStatus.pending,
        splits: [
          PaymentSplit.tryLira(
            id: 's1',
            method: PaymentMethodType.cash,
            amount: Money.fromWhole(100, Currency.tryLira),
          ),
          PaymentSplit.tryLira(
            id: 's2',
            method: PaymentMethodType.creditCard,
            amount: Money.fromWhole(100, Currency.tryLira),
          ),
        ],
        createdAt: DateTime(2026, 7, 28),
      );

      expect(intent.totalSettled, Money.fromWhole(200, Currency.tryLira));
      expect(intent.isFullySettled, isTrue);
    });

    test('isFullySettled is false when splits sum to less than totalAmount',
        () {
      final intent = PaymentIntent(
        id: 'pi1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(200, Currency.tryLira),
        status: PaymentStatus.pending,
        splits: [
          PaymentSplit.tryLira(
            id: 's1',
            method: PaymentMethodType.cash,
            amount: Money.fromWhole(100, Currency.tryLira),
          ),
        ],
        createdAt: DateTime(2026, 7, 28),
      );

      expect(intent.isFullySettled, isFalse);
    });

    test('a mixed TRY + foreign-currency split settles correctly', () {
      final snapshot = ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.eur,
        marketSellingRate: Money.fromWhole(47, Currency.tryLira),
        rateTimestamp: DateTime(2026, 7, 28),
        rateSource: 'manual',
      );
      final intent = PaymentIntent(
        id: 'pi1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(900, Currency.tryLira),
        status: PaymentStatus.pending,
        splits: [
          PaymentSplit.tryLira(
            id: 's1',
            method: PaymentMethodType.cash,
            amount: Money.fromWhole(60, Currency.tryLira),
          ),
          PaymentSplit.foreignCurrency(
            id: 's2',
            method: PaymentMethodType.creditCard,
            amount: Money.fromWhole(20, Currency.eur),
            exchangeRate: snapshot,
          ),
        ],
        createdAt: DateTime(2026, 7, 28),
      );

      // 60 TRY + (20 EUR -> 840 TRY) = 900 TRY
      expect(intent.totalSettled, Money.fromWhole(900, Currency.tryLira));
      expect(intent.isFullySettled, isTrue);
    });

    test('with no splits, totalSettled is zero', () {
      final intent = PaymentIntent(
        id: 'pi1',
        orderId: OrderId('order-1'),
        totalAmount: Money.fromWhole(100, Currency.tryLira),
        status: PaymentStatus.pending,
        createdAt: DateTime(2026, 7, 28),
      );

      expect(intent.totalSettled, Money.zero(Currency.tryLira));
      expect(intent.isFullySettled, isFalse);
    });
  });
}
