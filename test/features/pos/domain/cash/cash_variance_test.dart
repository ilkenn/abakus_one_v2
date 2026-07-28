import 'package:abakus_one_v2/features/pos/domain/cash/cash_variance.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CashVariance.compute', () {
    test('actual equal to expected is exact', () {
      final variance = CashVariance.compute(
        expectedAmount: Money.fromWhole(500, Currency.tryLira),
        actualAmount: Money.fromWhole(500, Currency.tryLira),
      );

      expect(variance.type, CashVarianceType.exact);
      expect(variance.isExact, isTrue);
      expect(variance.amount.isZero, isTrue);
    });

    test('actual above expected is an overage', () {
      final variance = CashVariance.compute(
        expectedAmount: Money.fromWhole(500, Currency.tryLira),
        actualAmount: Money.fromWhole(520, Currency.tryLira),
      );

      expect(variance.type, CashVarianceType.over);
      expect(variance.amount, Money.fromWhole(20, Currency.tryLira));
    });

    test('actual below expected is a shortage, amount stays non-negative', () {
      final variance = CashVariance.compute(
        expectedAmount: Money.fromWhole(500, Currency.tryLira),
        actualAmount: Money.fromWhole(480, Currency.tryLira),
      );

      expect(variance.type, CashVarianceType.short);
      expect(variance.amount, Money.fromWhole(20, Currency.tryLira));
      expect(variance.amount.isNegative, isFalse);
    });
  });
}
