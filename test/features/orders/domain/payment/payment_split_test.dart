import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/payment/payment_split.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_snapshot.dart';
import 'package:abakus_one_v2/features/payment/domain/models/payment_method_seed_data.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/exchange_rate_snapshot.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cashSnapshot = PaymentMethodSnapshot.capture(PaymentMethodSeedData.cash);
  final cardSnapshot =
      PaymentMethodSnapshot.capture(PaymentMethodSeedData.creditCard);

  group('PaymentSplit.tryLira', () {
    test('settlementAmount equals amount for a TRY split', () {
      final split = PaymentSplit.tryLira(
        id: 's1',
        methodSnapshot: cashSnapshot,
        amount: Money.fromWhole(100, Currency.tryLira),
      );

      expect(split.settlementAmount, split.amount);
      expect(split.exchangeRate, isNull);
      expect(split.isForeignCurrency, isFalse);
      expect(split.isCash, isTrue);
    });

    test('rejects an amount not denominated in TRY', () {
      expect(
        () => PaymentSplit.tryLira(
          id: 's1',
          methodSnapshot: cashSnapshot,
          amount: Money.fromWhole(100, Currency.eur),
        ),
        throwsA(isA<CurrencyMismatchViolation>()),
      );
    });

    test('a card split is not reported as cash', () {
      final split = PaymentSplit.tryLira(
        id: 's1',
        methodSnapshot: cardSnapshot,
        amount: Money.fromWhole(100, Currency.tryLira),
      );

      expect(split.isCash, isFalse);
    });
  });

  group('PaymentSplit.foreignCurrency', () {
    late ExchangeRateSnapshot snapshot;

    setUp(() {
      snapshot = ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.eur,
        marketSellingRate: Money.fromWhole(47, Currency.tryLira),
        rateTimestamp: DateTime(2026, 7, 28),
        rateSource: 'manual',
      );
    });

    test(
        'settles the correct TRY amount via the exchange rate snapshot (worked example)',
        () {
      final split = PaymentSplit.foreignCurrency(
        id: 's2',
        methodSnapshot: cardSnapshot,
        amount: Money.fromWhole(20, Currency.eur),
        exchangeRate: snapshot,
      );

      expect(split.settlementAmount, Money.fromWhole(840, Currency.tryLira));
      expect(split.isForeignCurrency, isTrue);
      expect(split.exchangeRate, snapshot);
    });

    test('rejects a TRY amount with no conversion needed', () {
      expect(
        () => PaymentSplit.foreignCurrency(
          id: 's2',
          methodSnapshot: cardSnapshot,
          amount: Money.fromWhole(20, Currency.tryLira),
          exchangeRate: snapshot,
        ),
        throwsA(isA<ForeignCurrencyPaymentMissingExchangeRateViolation>()),
      );
    });

    test('rejects an amount in a currency the business does not accept', () {
      const notAccepted = Currency(
        isoCode: 'GBP',
        displayName: 'Sterlin',
        symbol: '£',
        decimalDigits: 2,
        isDefault: false,
        isActive: true,
        isAcceptedByBusiness: false,
      );

      expect(
        () => PaymentSplit.foreignCurrency(
          id: 's2',
          methodSnapshot: cardSnapshot,
          amount: Money.fromWhole(20, notAccepted),
          exchangeRate: snapshot,
        ),
        throwsA(isA<CurrencyNotAcceptedViolation>()),
      );
    });

    test('a later, newer snapshot never recalculates an already-created split',
        () {
      final split = PaymentSplit.foreignCurrency(
        id: 's2',
        methodSnapshot: cardSnapshot,
        amount: Money.fromWhole(20, Currency.eur),
        exchangeRate: snapshot,
      );
      final originalSettlement = split.settlementAmount;

      // A new snapshot with a different rate is captured later.
      ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.eur,
        marketSellingRate: Money.fromWhole(55, Currency.tryLira),
        rateTimestamp: DateTime(2026, 7, 29),
        rateSource: 'manual',
      );

      expect(split.settlementAmount, originalSettlement);
    });
  });
}
