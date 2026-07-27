import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_rate.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(
      'TaxRate.vatAmountOf / taxableBaseOf — VAT extraction from a gross amount',
      () {
    test('extracts VAT from a gross amount at the default 10% rate', () {
      // gross 110.00 TRY at 10% VAT-inclusive -> VAT = 110 * 10 / 110 = 10.00
      final gross = Money.fromWhole(110, Currency.tryLira);
      final vat = TaxPolicy.defaultRate.vatAmountOf(gross);
      final taxableBase = TaxPolicy.defaultRate.taxableBaseOf(gross);

      expect(vat, Money.fromWhole(10, Currency.tryLira));
      expect(taxableBase, Money.fromWhole(100, Currency.tryLira));
    });

    test('taxableBase + vatAmount always equals the original gross amount', () {
      const gross = Money(19999, Currency.tryLira); // an odd, non-round amount
      final vat = TaxPolicy.defaultRate.vatAmountOf(gross);
      final taxableBase = TaxPolicy.defaultRate.taxableBaseOf(gross);

      expect(taxableBase + vat, gross);
    });

    test('VAT is never added on top of the gross amount', () {
      // The extraction formula must never produce a taxableBase greater
      // than the gross amount itself.
      final gross = Money.fromWhole(100, Currency.tryLira);
      final taxableBase = TaxPolicy.defaultRate.taxableBaseOf(gross);
      expect(taxableBase <= gross, isTrue);
    });

    test('a zero rate extracts zero VAT', () {
      const zeroRate = TaxRate.fromBasisPoints(0);
      final gross = Money.fromWhole(100, Currency.tryLira);
      expect(zeroRate.vatAmountOf(gross), Money.zero(Currency.tryLira));
      expect(zeroRate.taxableBaseOf(gross), gross);
    });

    test('a non-default rate (e.g. 20%) extracts VAT correctly', () {
      const twentyPercent = TaxRate.fromBasisPoints(2000);
      // gross 120.00 at 20% VAT-inclusive -> VAT = 120 * 20 / 120 = 20.00
      final gross = Money.fromWhole(120, Currency.tryLira);
      expect(
        twentyPercent.vatAmountOf(gross),
        Money.fromWhole(20, Currency.tryLira),
      );
    });

    test('rounds a fractional VAT amount half away from zero', () {
      // gross 100 minor units (1.00 TRY) at 10%: 100 * 1000 / 11000 =
      // 9.0909... -> rounds to 9
      const gross = Money(100, Currency.tryLira);
      expect(TaxPolicy.defaultRate.vatAmountOf(gross).minorUnits, 9);
    });
  });

  group('TaxRate construction', () {
    test('rejects a negative basis-point rate', () {
      expect(
        () => TaxRate.fromBasisPoints(-1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('equality is based on basisPoints', () {
      expect(
        const TaxRate.fromBasisPoints(1000),
        const TaxRate.fromBasisPoints(1000),
      );
      expect(
        const TaxRate.fromBasisPoints(1000) ==
            const TaxRate.fromBasisPoints(2000),
        isFalse,
      );
    });
  });

  group('TaxPolicy.defaultRate', () {
    test('the configured default is exactly 10.00% (1000 basis points)', () {
      expect(TaxPolicy.defaultRate.basisPoints, 1000);
    });
  });
}
