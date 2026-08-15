import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abakus_one_v2/features/reservation/presentation/providers/preorder_cart_provider.dart';

void main() {
  test('starts empty with zero total price and zero item count', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(preorderCartProvider), isEmpty);
    expect(container.read(preorderCartTotalPriceProvider), 0.0);
    expect(container.read(preorderCartTotalItemsCountProvider), 0);
  });

  test('total price and item count reflect added items', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(preorderCartProvider.notifier).addToCart(
          id: 'bowl-1',
          name: 'Poke Bowl',
          desc: '',
          price: 120,
          quantity: 2,
        );
    container.read(preorderCartProvider.notifier).addToCart(
          id: 'drink-1',
          name: 'Ayran',
          desc: '',
          price: 15,
        );

    expect(container.read(preorderCartTotalPriceProvider), 120 * 2 + 15);
    expect(container.read(preorderCartTotalItemsCountProvider), 3);
  });

  test('clearing the preorder cart resets both derived providers', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(preorderCartProvider.notifier);

    notifier.addToCart(id: 'bowl-1', name: 'Poke Bowl', desc: '', price: 120);
    notifier.clearCart();

    expect(container.read(preorderCartProvider), isEmpty);
    expect(container.read(preorderCartTotalPriceProvider), 0.0);
    expect(container.read(preorderCartTotalItemsCountProvider), 0);
  });
}
