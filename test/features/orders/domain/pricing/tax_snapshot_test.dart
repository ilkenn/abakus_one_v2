import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_snapshot.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TaxSnapshot.fromGrossAmount', () {
    test('bundles rate, taxableBase, and vatAmount from one gross amount', () {
      final snapshot = TaxSnapshot.fromGrossAmount(
        Money.fromWhole(110, Currency.tryLira),
        TaxPolicy.defaultRate,
      );

      expect(snapshot.rate, TaxPolicy.defaultRate);
      expect(snapshot.taxableBase, Money.fromWhole(100, Currency.tryLira));
      expect(snapshot.vatAmount, Money.fromWhole(10, Currency.tryLira));
    });
  });

  group('TaxSnapshot equality', () {
    test('two snapshots with equal fields are equal', () {
      final a = TaxSnapshot.fromGrossAmount(
        Money.fromWhole(110, Currency.tryLira),
        TaxPolicy.defaultRate,
      );
      final b = TaxSnapshot.fromGrossAmount(
        Money.fromWhole(110, Currency.tryLira),
        TaxPolicy.defaultRate,
      );

      expect(a, b);
    });
  });
}
