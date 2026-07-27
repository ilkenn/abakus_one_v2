import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Currency', () {
    test('isoCode matches ISO 4217 alphabetic codes', () {
      expect(Currency.tryLira.isoCode, 'TRY');
      expect(Currency.eur.isoCode, 'EUR');
      expect(Currency.usd.isoCode, 'USD');
    });

    test('minorUnitDigits is 2 for every supported currency', () {
      for (final currency in Currency.values) {
        expect(currency.minorUnitDigits, 2);
      }
    });

    test('minorUnitsPerWhole is 100 for every supported currency', () {
      for (final currency in Currency.values) {
        expect(currency.minorUnitsPerWhole, 100);
      }
    });

    test('exactly three currencies are supported', () {
      expect(Currency.values, hasLength(3));
    });
  });
}
