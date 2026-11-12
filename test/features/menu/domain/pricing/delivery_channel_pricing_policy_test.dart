import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/domain/pricing/channel_price_resolver.dart';
import 'package:abakus_one_v2/features/menu/domain/pricing/delivery_channel_pricing_policy.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-11-11 — product owner: Paket Servis is the Masa (dine-in) price
/// ×1.35, every product and every paid modifier rounded separately (half up)
/// to the nearest 5 TL, for the whole delivery channel. Replaces the earlier
/// BR-DELIVERY-002 rule (+140 TL, drinks +20 TL).

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

Money _tl(int whole) => Money.fromWhole(whole, Currency.tryLira);

void main() {
  const policy = DeliveryChannelPricingPolicy.value;

  Money delivery(double basePrice, {String categoryId = 'cat_bowl'}) =>
      ChannelPriceResolver.resolveProductUnitPrice(
        product: _product(basePrice: basePrice, categoryId: categoryId),
        categoryId: categoryId,
        channel: OrderChannel.delivery,
        policy: policy,
      );

  group('Paket Servis pricing — ×1.35, nearest 5 TL', () {
    test("the product owner's examples: 450 → 610, 430 → 580", () {
      expect(delivery(450), _tl(610)); // 607.50 → 610
      expect(delivery(430), _tl(580)); // 580.50 → 580
    });

    test('rounds half up to the nearest 5 TL', () {
      expect(delivery(100), _tl(135)); // 135.00
      expect(delivery(110), _tl(150)); // 148.50 → 150
      expect(delivery(10), _tl(15)); // 13.50 → 15
      expect(delivery(14), _tl(20)); // 18.90 → 20
      expect(delivery(13), _tl(20)); // 17.55 → 20
      expect(delivery(12), _tl(15)); // 16.20 → 15
    });

    test('drinks are scaled like every other product (no exemption)', () {
      expect(delivery(100, categoryId: 'cat_icecekler'), _tl(135));
    });

    test('each paid modifier is scaled and rounded on its own; free stays free',
        () {
      Money modifier(int whole) =>
          ChannelPriceResolver.resolveModifierExtraPrice(
            extraPrice: _tl(whole),
            channel: OrderChannel.delivery,
            policy: policy,
          );
      expect(modifier(40), _tl(55)); // 54 → 55
      expect(modifier(20), _tl(25)); // 27 → 25
      expect(modifier(0), _tl(0));
    });

    test('no other channel is affected by the delivery policy', () {
      for (final channel in [
        OrderChannel.takeaway,
        OrderChannel.dineInQr,
        OrderChannel.dineInStaff,
        OrderChannel.reservationPreorder,
      ]) {
        final result = ChannelPriceResolver.resolveProductUnitPrice(
          product: _product(basePrice: 450),
          categoryId: 'cat_bowl',
          channel: channel,
          policy: policy,
        );
        expect(result, _tl(450), reason: '$channel');
        expect(
          ChannelPriceResolver.resolveModifierExtraPrice(
            extraPrice: _tl(40),
            channel: channel,
            policy: policy,
          ),
          _tl(40),
          reason: '$channel modifier',
        );
      }
    });
  });
}
