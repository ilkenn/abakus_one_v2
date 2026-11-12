import 'package:abakus_one_v2/features/menu/data/channel_pricing_policy_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryChannelPricingPolicyRepository seed data', () {
    test('takeaway defaults to +20 TRY', () async {
      final repository = InMemoryChannelPricingPolicyRepository();
      final policy = await repository.current();
      expect(
        policy.defaultAdjustmentFor(OrderChannel.takeaway, Currency.tryLira),
        Money.fromWhole(20, Currency.tryLira),
      );
    });

    // 2026-11-11 — product owner: the BR-PRICE-004 drinks exemption is
    // withdrawn; every product, drinks included, is +20 TL on Gel-Al.
    test('İçecekler (cat_icecekler) is +20 on takeaway like every product',
        () async {
      final repository = InMemoryChannelPricingPolicyRepository();
      final policy = await repository.current();
      expect(
        policy.adjustmentFor(
          OrderChannel.takeaway,
          'cat_icecekler',
          Currency.tryLira,
        ),
        Money.fromWhole(20, Currency.tryLira),
      );
    });

    test('delivery is priced ×1.35, nearest 5 TL (2026-11-11)', () async {
      final policy = await InMemoryChannelPricingPolicyRepository().current();
      expect(
        policy.applyMultiplier(
            OrderChannel.delivery, Money.fromWhole(450, Currency.tryLira)),
        Money.fromWhole(610, Currency.tryLira),
      );
      expect(
        policy.applyMultiplier(
            OrderChannel.takeaway, Money.fromWhole(450, Currency.tryLira)),
        Money.fromWhole(450, Currency.tryLira),
        reason: 'takeaway has no multiplier',
      );
    });

    test(
        'every other channel has no configured default (dine-in/delivery unaffected)',
        () async {
      final repository = InMemoryChannelPricingPolicyRepository();
      final policy = await repository.current();
      for (final channel in [
        OrderChannel.dineInQr,
        OrderChannel.dineInStaff,
        OrderChannel.delivery,
        OrderChannel.reservationPreorder,
      ]) {
        expect(
          policy.defaultAdjustmentFor(channel, Currency.tryLira),
          Money.zero(Currency.tryLira),
          reason: '$channel must not be affected by the takeaway seed data',
        );
      }
    });
  });

  group('InMemoryChannelPricingPolicyRepository mutation', () {
    test('setChannelDefaultAdjustment overwrites the current default',
        () async {
      final repository = InMemoryChannelPricingPolicyRepository();
      await repository.setChannelDefaultAdjustment(
        OrderChannel.takeaway,
        Money.fromWhole(25, Currency.tryLira),
      );
      final policy = await repository.current();
      expect(
        policy.defaultAdjustmentFor(OrderChannel.takeaway, Currency.tryLira),
        Money.fromWhole(25, Currency.tryLira),
      );
    });

    test('setCategoryOverride adds a new category override', () async {
      final repository = InMemoryChannelPricingPolicyRepository();
      await repository.setCategoryOverride(
        OrderChannel.takeaway,
        'cat_soups',
        Money.fromWhole(10, Currency.tryLira),
      );
      final policy = await repository.current();
      expect(
        policy.adjustmentFor(
            OrderChannel.takeaway, 'cat_soups', Currency.tryLira),
        Money.fromWhole(10, Currency.tryLira),
      );
      // categories without an override keep the channel default
      expect(
        policy.adjustmentFor(
          OrderChannel.takeaway,
          'cat_icecekler',
          Currency.tryLira,
        ),
        Money.fromWhole(20, Currency.tryLira),
      );
    });

    test(
        'clearCategoryOverride removes an override, falling back to the channel default',
        () async {
      final repository = InMemoryChannelPricingPolicyRepository();
      await repository.clearCategoryOverride(
        OrderChannel.takeaway,
        'cat_icecekler',
      );
      final policy = await repository.current();
      expect(
        policy.adjustmentFor(
          OrderChannel.takeaway,
          'cat_icecekler',
          Currency.tryLira,
        ),
        Money.fromWhole(20, Currency.tryLira),
      );
    });

    test(
        'setCategoryOverride for a channel with no prior overrides at all works',
        () async {
      final repository = InMemoryChannelPricingPolicyRepository();
      await repository.setCategoryOverride(
        OrderChannel.delivery,
        'cat_icecekler',
        Money.fromWhole(5, Currency.tryLira),
      );
      final policy = await repository.current();
      expect(
        policy.adjustmentFor(
          OrderChannel.delivery,
          'cat_icecekler',
          Currency.tryLira,
        ),
        Money.fromWhole(5, Currency.tryLira),
      );
    });
  });
}
