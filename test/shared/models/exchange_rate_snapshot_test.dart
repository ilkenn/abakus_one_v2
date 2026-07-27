import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/exchange_rate_policy.dart';
import 'package:abakus_one_v2/shared/models/exchange_rate_snapshot.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final timestamp = DateTime(2026, 7, 28, 9, 0);

  group('ExchangeRateSnapshot.capture', () {
    test(
        'computes acceptanceRate = marketSellingRate - fixedMargin (worked example)',
        () {
      // EUR market selling rate 47.00 TRY, fixed margin 5.00 TRY ->
      // acceptance rate 42.00 TRY, per the approved decision's own example.
      final snapshot = ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.eur,
        marketSellingRate: Money.fromWhole(47, Currency.tryLira),
        rateTimestamp: timestamp,
        rateSource: 'manual',
      );

      expect(snapshot.acceptanceRate, Money.fromWhole(42, Currency.tryLira));
      expect(snapshot.targetCurrency, Currency.tryLira);
      expect(snapshot.fixedMargin, ExchangeRatePolicy.fixedMargin);
    });

    test(
        'a custom fixedMargin overrides the policy default and is captured as given',
        () {
      final snapshot = ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.usd,
        marketSellingRate: Money.fromWhole(40, Currency.tryLira),
        fixedMargin: Money.fromWhole(3, Currency.tryLira),
        rateTimestamp: timestamp,
        rateSource: 'manual',
      );

      expect(snapshot.fixedMargin, Money.fromWhole(3, Currency.tryLira));
      expect(snapshot.acceptanceRate, Money.fromWhole(37, Currency.tryLira));
    });

    test('rejects a source currency of TRY', () {
      expect(
        () => ExchangeRateSnapshot.capture(
          sourceCurrency: Currency.tryLira,
          marketSellingRate: Money.fromWhole(47, Currency.tryLira),
          rateTimestamp: timestamp,
          rateSource: 'manual',
        ),
        throwsA(isA<UnsupportedExchangeRateCurrencyViolation>()),
      );
    });

    test('rejects a non-positive acceptance rate (margin >= market rate)', () {
      expect(
        () => ExchangeRateSnapshot.capture(
          sourceCurrency: Currency.eur,
          marketSellingRate: Money.fromWhole(5, Currency.tryLira),
          fixedMargin: Money.fromWhole(5, Currency.tryLira),
          rateTimestamp: timestamp,
          rateSource: 'manual',
        ),
        throwsA(isA<NonPositiveAcceptanceRateViolation>()),
      );
    });

    test('rejects a market selling rate not denominated in TRY', () {
      expect(
        () => ExchangeRateSnapshot.capture(
          sourceCurrency: Currency.eur,
          marketSellingRate: Money.fromWhole(47, Currency.usd),
          rateTimestamp: timestamp,
          rateSource: 'manual',
        ),
        throwsA(isA<UnsupportedExchangeRateCurrencyViolation>()),
      );
    });

    test('rejects a source currency the business does not currently accept',
        () {
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
        () => ExchangeRateSnapshot.capture(
          sourceCurrency: notAccepted,
          marketSellingRate: Money.fromWhole(55, Currency.tryLira),
          rateTimestamp: timestamp,
          rateSource: 'manual',
        ),
        throwsA(isA<CurrencyNotAcceptedViolation>()),
      );
    });
  });

  group('ExchangeRateSnapshot.convertToTry', () {
    test(
        '20 EUR at a 42.00 acceptance rate settles 840.00 TRY (worked example)',
        () {
      final snapshot = ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.eur,
        marketSellingRate: Money.fromWhole(47, Currency.tryLira),
        rateTimestamp: timestamp,
        rateSource: 'manual',
      );

      final settled = snapshot.convertToTry(Money.fromWhole(20, Currency.eur));

      expect(settled, Money.fromWhole(840, Currency.tryLira));
    });

    test('rejects an amount not in the snapshot\'s sourceCurrency', () {
      final snapshot = ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.eur,
        marketSellingRate: Money.fromWhole(47, Currency.tryLira),
        rateTimestamp: timestamp,
        rateSource: 'manual',
      );

      expect(
        () => snapshot.convertToTry(Money.fromWhole(20, Currency.usd)),
        throwsA(isA<CurrencyMismatchViolation>()),
      );
    });

    test(
        'a later change to a new snapshot never alters an earlier one (historical rates frozen)',
        () {
      final firstSnapshot = ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.eur,
        marketSellingRate: Money.fromWhole(47, Currency.tryLira),
        rateTimestamp: timestamp,
        rateSource: 'manual',
      );
      final firstSettlement =
          firstSnapshot.convertToTry(Money.fromWhole(20, Currency.eur));

      // A new, later snapshot with a different market rate.
      ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.eur,
        marketSellingRate: Money.fromWhole(50, Currency.tryLira),
        rateTimestamp: timestamp.add(const Duration(days: 1)),
        rateSource: 'manual',
      );

      // The first snapshot's own conversion is unchanged.
      expect(
        firstSnapshot.convertToTry(Money.fromWhole(20, Currency.eur)),
        firstSettlement,
      );
    });
  });

  group('ExchangeRateSnapshot.convertFromTry', () {
    test(
        '650.00 TRY at a 42.00 acceptance rate is ~15.48 EUR (worked receipt example)',
        () {
      final snapshot = ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.eur,
        marketSellingRate: Money.fromWhole(47, Currency.tryLira),
        rateTimestamp: timestamp,
        rateSource: 'manual',
      );

      final equivalent =
          snapshot.convertFromTry(Money.fromWhole(650, Currency.tryLira));

      expect(equivalent, const Money(1548, Currency.eur));
    });

    test('is the exact inverse of convertToTry for a round-trippable amount',
        () {
      final snapshot = ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.eur,
        marketSellingRate: Money.fromWhole(47, Currency.tryLira),
        rateTimestamp: timestamp,
        rateSource: 'manual',
      );
      final originalEur = Money.fromWhole(20, Currency.eur);

      final tryAmount = snapshot.convertToTry(originalEur);
      final backToEur = snapshot.convertFromTry(tryAmount);

      expect(backToEur, originalEur);
    });

    test('rejects an amount not in the snapshot\'s targetCurrency', () {
      final snapshot = ExchangeRateSnapshot.capture(
        sourceCurrency: Currency.eur,
        marketSellingRate: Money.fromWhole(47, Currency.tryLira),
        rateTimestamp: timestamp,
        rateSource: 'manual',
      );

      expect(
        () => snapshot.convertFromTry(Money.fromWhole(650, Currency.usd)),
        throwsA(isA<CurrencyMismatchViolation>()),
      );
    });
  });
}
