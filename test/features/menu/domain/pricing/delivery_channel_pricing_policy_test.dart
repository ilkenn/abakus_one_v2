import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/domain/pricing/channel_price_resolver.dart';
import 'package:abakus_one_v2/features/menu/domain/pricing/delivery_channel_pricing_policy.dart';
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_line_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the LOCKED Faz P.1 delivery pricing rule (`docs/business_rules.md`)
/// against the same, unmodified `ChannelPriceResolver` every other channel
/// uses — via the isolated `DeliveryChannelPricingPolicy.value` constant,
/// **not** the live `InMemoryChannelPricingPolicyRepository`/
/// `channelPricingPolicySnapshotProvider` chain (see that repository's own
/// doc comment for why: seeding delivery there would have live-changed
/// Bowl Builder's real customer-facing price today, since
/// [OrderChannel.delivery] is this app's default shopping channel and
/// `bowl_builder_screen.dart` resolves a price for it with no
/// takeaway-only gate).

MenuProduct _product({
  double basePrice = 500,
  String categoryId = 'cat_bowl',
}) {
  return MenuProduct(
    id: 'prod-1',
    categoryId: categoryId,
    name: 'Test Product',
    description: '',
    basePrice: basePrice,
    imageKey: 'test',
  );
}

void main() {
  final policy = DeliveryChannelPricingPolicy.value;

  group('Delivery pricing — LOCKED rule (Faz P.1 req 5)', () {
    test('a standard product gets +140 TL on delivery (req 5)', () {
      final result = ChannelPriceResolver.resolveProductUnitPrice(
        product: _product(basePrice: 500, categoryId: 'cat_bowl'),
        categoryId: 'cat_bowl',
        channel: OrderChannel.delivery,
        policy: policy,
      );
      expect(result, Money.fromWhole(640, Currency.tryLira));
    });

    test(
        'a beverage (cat_icecekler) gets +20 TL on delivery, not +140 '
        '(req 5)', () {
      final result = ChannelPriceResolver.resolveProductUnitPrice(
        product: _product(basePrice: 100, categoryId: 'cat_icecekler'),
        categoryId: 'cat_icecekler',
        channel: OrderChannel.delivery,
        policy: policy,
      );
      expect(result, Money.fromWhole(120, Currency.tryLira));
    });

    test(
        'a Build Your Own Bowl unit gets +140 TL exactly once, applied to '
        'the ingredient sum (req 5)', () {
      final ingredientTotal = Money.fromWhole(180, Currency.tryLira);
      final result = ChannelPriceResolver.resolveBowlUnitPrice(
        ingredientTotal: ingredientTotal,
        channel: OrderChannel.delivery,
        policy: policy,
      );
      expect(result, Money.fromWhole(320, Currency.tryLira));
    });

    test(
        'the +140 TL bowl surcharge does not scale with ingredient count — '
        'it is a flat once-per-bowl amount, never per-ingredient (req 5)', () {
      // Three different ingredient counts, summed to three different
      // totals — the delivery adjustment added on top is always exactly
      // +140 TL, never +140 multiplied by an ingredient count.
      for (final ingredientTotal in [
        Money.fromWhole(60, Currency.tryLira), // e.g. 2 ingredients
        Money.fromWhole(150, Currency.tryLira), // e.g. 5 ingredients
        Money.fromWhole(300, Currency.tryLira), // e.g. 10 ingredients
      ]) {
        final result = ChannelPriceResolver.resolveBowlUnitPrice(
          ingredientTotal: ingredientTotal,
          channel: OrderChannel.delivery,
          policy: policy,
        );
        expect(
          result,
          ingredientTotal + Money.fromWhole(140, Currency.tryLira),
          reason: 'ingredientTotal=$ingredientTotal',
        );
      }
    });

    test(
        'the bowl surcharge still multiplies by order quantity via the '
        'existing OrderLine mechanism, unrelated to ingredient count '
        '(req 5)', () {
      final ingredientTotal = Money.fromWhole(100, Currency.tryLira);
      final unitPrice = ChannelPriceResolver.resolveBowlUnitPrice(
        ingredientTotal: ingredientTotal,
        channel: OrderChannel.delivery,
        policy: policy,
      );

      final cartItem = CartItem(
        id: 'custom_bowl_1',
        name: 'Kendi Bowlun',
        desc: '',
        price: unitPrice.minorUnits / unitPrice.currency.minorUnitsPerWhole,
        quantity: 2,
      );
      final line = CartLineMapper.mapLine(cartItem, TaxPolicy.defaultRate);

      // (100 + 140) * 2 = 480
      expect(line.lineSubtotal, Money.fromWhole(480, Currency.tryLira));
    });

    test(
        'delivery pricing does not affect takeaway/dine-in/reservation '
        'pricing — the isolated constant only ever configures '
        'OrderChannel.delivery (req 9, 10, 11)', () {
      for (final channel in [
        OrderChannel.takeaway,
        OrderChannel.dineInQr,
        OrderChannel.dineInStaff,
        OrderChannel.reservationPreorder,
      ]) {
        final result = ChannelPriceResolver.resolveProductUnitPrice(
          product: _product(basePrice: 500, categoryId: 'cat_bowl'),
          categoryId: 'cat_bowl',
          channel: channel,
          policy: policy,
        );
        expect(result, Money.fromWhole(500, Currency.tryLira),
            reason: '$channel');
      }
    });
  });
}
