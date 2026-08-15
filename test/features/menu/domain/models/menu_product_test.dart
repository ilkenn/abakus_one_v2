import 'package:abakus_one_v2/features/menu/domain/models/menu_product.dart';
import 'package:abakus_one_v2/features/menu/domain/pricing/channel_price_rule.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MenuProduct.channelPriceOverrides', () {
    test('defaults to empty — existing product literals stay unchanged', () {
      const product = MenuProduct(
        id: 'p1',
        categoryId: 'cat_bowl',
        name: 'Bowl',
        description: '',
        basePrice: 500,
        imageKey: 'bowl',
      );
      expect(product.channelPriceOverrides, isEmpty);
    });

    test(
        'copyWith replaces channelPriceOverrides without touching other fields',
        () {
      const product = MenuProduct(
        id: 'p1',
        categoryId: 'cat_bowl',
        name: 'Bowl',
        description: '',
        basePrice: 500,
        imageKey: 'bowl',
      );
      final updated = product.copyWith(
        channelPriceOverrides: {
          OrderChannel.takeaway:
              ChannelExplicitPrice(Money.fromWhole(599, Currency.tryLira)),
        },
      );
      expect(updated.channelPriceOverrides[OrderChannel.takeaway],
          ChannelExplicitPrice(Money.fromWhole(599, Currency.tryLira)));
      expect(updated.basePrice, product.basePrice);
      expect(updated.name, product.name);
    });

    test('copyWith with no argument preserves the existing overrides', () {
      final product = MenuProduct(
        id: 'p1',
        categoryId: 'cat_bowl',
        name: 'Bowl',
        description: '',
        basePrice: 500,
        imageKey: 'bowl',
        channelPriceOverrides: {
          OrderChannel.takeaway:
              ChannelFixedAdjustment(Money.fromWhole(20, Currency.tryLira)),
        },
      );
      final updated = product.copyWith(name: 'Bowl v2');
      expect(updated.channelPriceOverrides, product.channelPriceOverrides);
    });
  });
}
