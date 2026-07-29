import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_settlement_variance.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CourierSettlementVariance.compute', () {
    test('is exact when declared equals expected', () {
      final variance = CourierSettlementVariance.compute(
        expectedAmount: Money.fromWhole(100, Currency.tryLira),
        declaredAmount: Money.fromWhole(100, Currency.tryLira),
      );

      expect(variance.type, CourierVarianceType.exact);
      expect(variance.isExact, isTrue);
      expect(variance.amount.isZero, isTrue);
    });

    test('is short when declared is less than expected', () {
      final variance = CourierSettlementVariance.compute(
        expectedAmount: Money.fromWhole(100, Currency.tryLira),
        declaredAmount: Money.fromWhole(80, Currency.tryLira),
      );

      expect(variance.type, CourierVarianceType.short);
      expect(variance.amount, Money.fromWhole(20, Currency.tryLira));
    });

    test('is over when declared exceeds expected', () {
      final variance = CourierSettlementVariance.compute(
        expectedAmount: Money.fromWhole(100, Currency.tryLira),
        declaredAmount: Money.fromWhole(120, Currency.tryLira),
      );

      expect(variance.type, CourierVarianceType.over);
      expect(variance.amount, Money.fromWhole(20, Currency.tryLira));
    });
  });
}
