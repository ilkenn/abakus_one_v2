import 'package:abakus_one_v2/features/menu/domain/pricing/channel_price_rule.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UseChannelDefault', () {
    test('two instances are equal', () {
      expect(const UseChannelDefault(), const UseChannelDefault());
    });
  });

  group('ChannelFixedAdjustment', () {
    test('equal when the adjustment matches', () {
      final a = ChannelFixedAdjustment(Money.fromWhole(20, Currency.tryLira));
      final b = ChannelFixedAdjustment(Money.fromWhole(20, Currency.tryLira));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when the adjustment differs', () {
      final a = ChannelFixedAdjustment(Money.fromWhole(20, Currency.tryLira));
      final b = ChannelFixedAdjustment(Money.fromWhole(30, Currency.tryLira));
      expect(a, isNot(b));
    });
  });

  group('ChannelExplicitPrice', () {
    test('equal when the price matches', () {
      final a = ChannelExplicitPrice(Money.fromWhole(599, Currency.tryLira));
      final b = ChannelExplicitPrice(Money.fromWhole(599, Currency.tryLira));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when the price differs', () {
      final a = ChannelExplicitPrice(Money.fromWhole(599, Currency.tryLira));
      final b = ChannelExplicitPrice(Money.fromWhole(499, Currency.tryLira));
      expect(a, isNot(b));
    });

    test('different rule types are never equal', () {
      final fixed =
          ChannelFixedAdjustment(Money.fromWhole(20, Currency.tryLira));
      final explicit =
          ChannelExplicitPrice(Money.fromWhole(20, Currency.tryLira));
      expect(fixed, isNot(explicit));
      expect(fixed, isNot(const UseChannelDefault()));
    });
  });
}
