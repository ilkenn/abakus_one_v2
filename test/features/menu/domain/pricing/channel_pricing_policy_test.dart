import 'package:abakus_one_v2/features/menu/domain/pricing/channel_pricing_policy.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChannelPricingPolicy.adjustmentFor', () {
    test('returns zero for a channel with no configured rule', () {
      const policy = ChannelPricingPolicy();
      final result = policy.adjustmentFor(
        OrderChannel.takeaway,
        'cat_bowl',
        Currency.tryLira,
      );
      expect(result, Money.zero(Currency.tryLira));
    });

    test('falls back to the channel default when no category override exists',
        () {
      final policy = ChannelPricingPolicy(
        channelDefaultAdjustments: {
          OrderChannel.takeaway: Money.fromWhole(20, Currency.tryLira),
        },
      );
      final result = policy.adjustmentFor(
        OrderChannel.takeaway,
        'cat_bowl',
        Currency.tryLira,
      );
      expect(result, Money.fromWhole(20, Currency.tryLira));
    });

    test('a category override wins over the channel default', () {
      final policy = ChannelPricingPolicy(
        channelDefaultAdjustments: {
          OrderChannel.takeaway: Money.fromWhole(20, Currency.tryLira),
        },
        categoryOverrides: {
          OrderChannel.takeaway: {
            'cat_icecekler': Money.zero(Currency.tryLira),
          },
        },
      );
      final drinkResult = policy.adjustmentFor(
        OrderChannel.takeaway,
        'cat_icecekler',
        Currency.tryLira,
      );
      final otherResult = policy.adjustmentFor(
        OrderChannel.takeaway,
        'cat_bowl',
        Currency.tryLira,
      );
      expect(drinkResult, Money.zero(Currency.tryLira));
      expect(otherResult, Money.fromWhole(20, Currency.tryLira));
    });

    test('a rule configured for one channel never leaks into another', () {
      final policy = ChannelPricingPolicy(
        channelDefaultAdjustments: {
          OrderChannel.takeaway: Money.fromWhole(20, Currency.tryLira),
        },
      );
      final result = policy.adjustmentFor(
        OrderChannel.dineInQr,
        'cat_bowl',
        Currency.tryLira,
      );
      expect(result, Money.zero(Currency.tryLira));
    });
  });

  group('ChannelPricingPolicy.defaultAdjustmentFor', () {
    test('ignores category overrides entirely', () {
      final policy = ChannelPricingPolicy(
        channelDefaultAdjustments: {
          OrderChannel.takeaway: Money.fromWhole(20, Currency.tryLira),
        },
        categoryOverrides: {
          OrderChannel.takeaway: {
            'cat_icecekler': Money.zero(Currency.tryLira),
          },
        },
      );
      final result =
          policy.defaultAdjustmentFor(OrderChannel.takeaway, Currency.tryLira);
      expect(result, Money.fromWhole(20, Currency.tryLira));
    });

    test('returns zero for an unconfigured channel', () {
      const policy = ChannelPricingPolicy();
      final result =
          policy.defaultAdjustmentFor(OrderChannel.delivery, Currency.tryLira);
      expect(result, Money.zero(Currency.tryLira));
    });
  });
}
