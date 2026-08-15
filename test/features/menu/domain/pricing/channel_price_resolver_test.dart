import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/domain/pricing/channel_price_resolver.dart';
import 'package:abakus_one_v2/features/menu/domain/pricing/channel_price_rule.dart';
import 'package:abakus_one_v2/features/menu/domain/pricing/channel_pricing_policy.dart';
import 'package:abakus_one_v2/features/orders/domain/mappers/cart_line_mapper.dart';
import 'package:abakus_one_v2/features/orders/domain/pricing/tax_policy.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

MenuProduct _product({
  double basePrice = 500,
  String categoryId = 'cat_bowl',
  Map<OrderChannel, ChannelPriceRule> channelPriceOverrides = const {},
}) {
  return MenuProduct(
    id: 'prod-1',
    categoryId: categoryId,
    name: 'Test Product',
    description: '',
    basePrice: basePrice,
    imageKey: 'test',
    channelPriceOverrides: channelPriceOverrides,
  );
}

final _gelAlPolicy = ChannelPricingPolicy(
  channelDefaultAdjustments: {
    OrderChannel.takeaway: Money.fromWhole(20, Currency.tryLira),
  },
  categoryOverrides: {
    OrderChannel.takeaway: {
      'cat_icecekler': Money.zero(Currency.tryLira),
    },
  },
);

void main() {
  group('resolveProductUnitPrice — category default resolution', () {
    test('a non-drink product on takeaway gets the +20 TL channel default', () {
      final result = ChannelPriceResolver.resolveProductUnitPrice(
        product: _product(basePrice: 500, categoryId: 'cat_bowl'),
        categoryId: 'cat_bowl',
        channel: OrderChannel.takeaway,
        policy: _gelAlPolicy,
      );
      expect(result, Money.fromWhole(520, Currency.tryLira));
    });

    test('a drink (cat_icecekler) on takeaway is exempted (+0)', () {
      final result = ChannelPriceResolver.resolveProductUnitPrice(
        product: _product(basePrice: 100, categoryId: 'cat_icecekler'),
        categoryId: 'cat_icecekler',
        channel: OrderChannel.takeaway,
        policy: _gelAlPolicy,
      );
      expect(result, Money.fromWhole(100, Currency.tryLira));
    });

    test('dine-in pricing is completely unaffected by the takeaway policy', () {
      final result = ChannelPriceResolver.resolveProductUnitPrice(
        product: _product(basePrice: 500, categoryId: 'cat_bowl'),
        categoryId: 'cat_bowl',
        channel: OrderChannel.dineInQr,
        policy: _gelAlPolicy,
      );
      expect(result, Money.fromWhole(500, Currency.tryLira));
    });

    test('delivery pricing is completely unaffected by the takeaway policy',
        () {
      final result = ChannelPriceResolver.resolveProductUnitPrice(
        product: _product(basePrice: 500, categoryId: 'cat_bowl'),
        categoryId: 'cat_bowl',
        channel: OrderChannel.delivery,
        policy: _gelAlPolicy,
      );
      expect(result, Money.fromWhole(500, Currency.tryLira));
    });
  });

  group('resolveProductUnitPrice — product-level overrides', () {
    test('UseChannelDefault behaves exactly like no override at all', () {
      final result = ChannelPriceResolver.resolveProductUnitPrice(
        product: _product(
          basePrice: 500,
          categoryId: 'cat_bowl',
          channelPriceOverrides: const {
            OrderChannel.takeaway: UseChannelDefault(),
          },
        ),
        categoryId: 'cat_bowl',
        channel: OrderChannel.takeaway,
        policy: _gelAlPolicy,
      );
      expect(result, Money.fromWhole(520, Currency.tryLira));
    });

    test('ChannelFixedAdjustment overrides the category default', () {
      final result = ChannelPriceResolver.resolveProductUnitPrice(
        product: _product(
          basePrice: 500,
          categoryId: 'cat_bowl',
          channelPriceOverrides: {
            OrderChannel.takeaway:
                ChannelFixedAdjustment(Money.fromWhole(35, Currency.tryLira)),
          },
        ),
        categoryId: 'cat_bowl',
        channel: OrderChannel.takeaway,
        policy: _gelAlPolicy,
      );
      expect(result, Money.fromWhole(535, Currency.tryLira));
    });

    test('ChannelExplicitPrice replaces the price entirely, ignoring basePrice',
        () {
      final result = ChannelPriceResolver.resolveProductUnitPrice(
        product: _product(
          basePrice: 500,
          categoryId: 'cat_bowl',
          channelPriceOverrides: {
            OrderChannel.takeaway:
                ChannelExplicitPrice(Money.fromWhole(599, Currency.tryLira)),
          },
        ),
        categoryId: 'cat_bowl',
        channel: OrderChannel.takeaway,
        policy: _gelAlPolicy,
      );
      expect(result, Money.fromWhole(599, Currency.tryLira));
    });

    test('a product override for one channel does not affect another channel',
        () {
      final product = _product(
        basePrice: 500,
        categoryId: 'cat_bowl',
        channelPriceOverrides: {
          OrderChannel.takeaway:
              ChannelExplicitPrice(Money.fromWhole(599, Currency.tryLira)),
        },
      );
      final result = ChannelPriceResolver.resolveProductUnitPrice(
        product: product,
        categoryId: 'cat_bowl',
        channel: OrderChannel.dineInQr,
        policy: _gelAlPolicy,
      );
      expect(result, Money.fromWhole(500, Currency.tryLira));
    });

    test(
        'a drink with an explicit product override ignores the category exemption',
        () {
      final result = ChannelPriceResolver.resolveProductUnitPrice(
        product: _product(
          basePrice: 100,
          categoryId: 'cat_icecekler',
          channelPriceOverrides: {
            OrderChannel.takeaway:
                ChannelFixedAdjustment(Money.fromWhole(5, Currency.tryLira)),
          },
        ),
        categoryId: 'cat_icecekler',
        channel: OrderChannel.takeaway,
        policy: _gelAlPolicy,
      );
      expect(result, Money.fromWhole(105, Currency.tryLira));
    });
  });

  group('resolveProductUnitPrice — negative-price guard', () {
    test(
        'throws NegativeAmountViolation when a fixed adjustment would go negative',
        () {
      expect(
        () => ChannelPriceResolver.resolveProductUnitPrice(
          product: _product(
            basePrice: 10,
            categoryId: 'cat_bowl',
            channelPriceOverrides: {
              OrderChannel.takeaway: ChannelFixedAdjustment(
                -Money.fromWhole(20, Currency.tryLira),
              ),
            },
          ),
          categoryId: 'cat_bowl',
          channel: OrderChannel.takeaway,
          policy: _gelAlPolicy,
        ),
        throwsA(isA<NegativeAmountViolation>()),
      );
    });
  });

  group('resolveBowlUnitPrice — Bowl Builder, applied once per bowl', () {
    test('adds the channel default exactly once to the ingredient sum', () {
      final ingredientTotal = Money.fromWhole(100, Currency.tryLira);
      final result = ChannelPriceResolver.resolveBowlUnitPrice(
        ingredientTotal: ingredientTotal,
        channel: OrderChannel.takeaway,
        policy: _gelAlPolicy,
      );
      expect(result, Money.fromWhole(120, Currency.tryLira));
    });

    test('dine-in bowl pricing is unaffected (no configured default)', () {
      final ingredientTotal = Money.fromWhole(100, Currency.tryLira);
      final result = ChannelPriceResolver.resolveBowlUnitPrice(
        ingredientTotal: ingredientTotal,
        channel: OrderChannel.dineInQr,
        policy: _gelAlPolicy,
      );
      expect(result, ingredientTotal);
    });

    test(
      'a bowl ordered at quantity 2 applies the adjustment twice, via the '
      'existing OrderLine quantity multiplication — not a resolver concern',
      () {
        final ingredientTotal = Money.fromWhole(100, Currency.tryLira);
        final unitPrice = ChannelPriceResolver.resolveBowlUnitPrice(
          ingredientTotal: ingredientTotal,
          channel: OrderChannel.takeaway,
          policy: _gelAlPolicy,
        );

        final cartItem = CartItem(
          id: 'custom_bowl_1',
          name: 'Kendi Bowlun',
          desc: '',
          price: unitPrice.minorUnits / unitPrice.currency.minorUnitsPerWhole,
          quantity: 2,
        );
        final line = CartLineMapper.mapLine(cartItem, TaxPolicy.defaultRate);

        // (100 + 20) * 2 = 240 — the +20 TL is applied once per bowl unit,
        // never per ingredient, and scales with quantity exactly like every
        // other line total in this codebase.
        expect(line.lineSubtotal, Money.fromWhole(240, Currency.tryLira));
      },
    );

    test(
        'throws NegativeAmountViolation if the ingredient total plus adjustment is negative',
        () {
      final policy = ChannelPricingPolicy(
        channelDefaultAdjustments: {
          OrderChannel.takeaway: -Money.fromWhole(50, Currency.tryLira),
        },
      );
      expect(
        () => ChannelPriceResolver.resolveBowlUnitPrice(
          ingredientTotal: Money.fromWhole(10, Currency.tryLira),
          channel: OrderChannel.takeaway,
          policy: policy,
        ),
        throwsA(isA<NegativeAmountViolation>()),
      );
    });
  });
}
