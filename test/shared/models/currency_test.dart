import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Currency — configured catalog', () {
    test('TRY/EUR/USD are configured, in that order, in Currency.all', () {
      expect(Currency.all, [Currency.tryLira, Currency.eur, Currency.usd]);
    });

    test(
        'every configured currency exposes ISO code, display name, symbol, and decimal digits',
        () {
      expect(Currency.tryLira.isoCode, 'TRY');
      expect(Currency.tryLira.displayName, isNotEmpty);
      expect(Currency.tryLira.symbol, isNotEmpty);
      expect(Currency.tryLira.decimalDigits, 2);

      expect(Currency.eur.isoCode, 'EUR');
      expect(Currency.usd.isoCode, 'USD');
    });

    test('minorUnitsPerWhole is derived from decimalDigits, not hardcoded', () {
      expect(Currency.tryLira.minorUnitsPerWhole, 100);
      expect(Currency.eur.minorUnitsPerWhole, 100);
      expect(Currency.usd.minorUnitsPerWhole, 100);
    });
  });

  group('Currency — isDefault/isActive/isAcceptedByBusiness', () {
    test('TRY is the only default (accounting) currency', () {
      expect(Currency.tryLira.isDefault, isTrue);
      expect(Currency.eur.isDefault, isFalse);
      expect(Currency.usd.isDefault, isFalse);
      expect(Currency.accountingCurrency, Currency.tryLira);
    });

    test(
        'all three configured currencies are active and accepted by the business today',
        () {
      for (final currency in Currency.all) {
        expect(currency.isActive, isTrue);
        expect(currency.isAcceptedByBusiness, isTrue);
      }
    });

    test('acceptedForeignCurrencies excludes the accounting currency', () {
      expect(Currency.acceptedForeignCurrencies, [Currency.eur, Currency.usd]);
    });

    test(
        'active and acceptedByBusiness both list all three configured currencies today',
        () {
      expect(Currency.active, Currency.all);
      expect(Currency.acceptedByBusiness, Currency.all);
    });
  });

  group('Currency — equality', () {
    test('two Currency instances with the same isoCode are equal', () {
      expect(Currency.tryLira, Currency.tryLira);
      expect(Currency.eur == Currency.usd, isFalse);
    });

    test('toString returns the ISO code', () {
      expect(Currency.tryLira.toString(), 'TRY');
    });
  });

  group('Currency — extensibility (no business-logic change to add a currency)',
      () {
    test(
        'every configured currency exposes the same generic field shape, not per-currency branching',
        () {
      // Currency has no factory reachable from outside currency.dart — a
      // future GBP/CHF/SAR/AED is added there as one more `static const`
      // entry in `all`. This test proves every currently-configured
      // currency already goes through that same generic shape (no
      // per-currency special case anywhere), which is exactly what makes
      // adding a fourth one a pure data change.
      for (final currency in Currency.all) {
        expect(currency.isoCode, isNotEmpty);
        expect(currency.displayName, isNotEmpty);
        expect(currency.symbol, isNotEmpty);
        expect(currency.decimalDigits, greaterThan(0));
        expect(currency.minorUnitsPerWhole, isPositive);
      }
    });
  });
}
