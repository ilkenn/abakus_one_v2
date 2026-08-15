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

    test('İçecekler (cat_icecekler) is overridden to +0 on takeaway', () async {
      final repository = InMemoryChannelPricingPolicyRepository();
      final policy = await repository.current();
      expect(
        policy.adjustmentFor(
          OrderChannel.takeaway,
          'cat_icecekler',
          Currency.tryLira,
        ),
        Money.zero(Currency.tryLira),
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
      // the seeded İçecekler override must still be intact
      expect(
        policy.adjustmentFor(
          OrderChannel.takeaway,
          'cat_icecekler',
          Currency.tryLira,
        ),
        Money.zero(Currency.tryLira),
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
