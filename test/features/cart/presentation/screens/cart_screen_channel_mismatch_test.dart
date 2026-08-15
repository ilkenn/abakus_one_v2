import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abakus_one_v2/features/cart/domain/models/cart_item.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/cart_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/providers/shopping_channel_provider.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/cart_screen.dart';
import 'package:abakus_one_v2/features/cart/presentation/screens/takeaway_checkout_screen.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';

/// Faz C — "kanal değiştirildiğinde eski kanal fiyatları sepette sessizce
/// kalmamalı." Covers `CartScreen`'s new channel-mismatch guard in
/// isolation from every other cart behavior already covered elsewhere.
void main() {
  Future<ProviderContainer> pumpCart(
    WidgetTester tester, {
    required List<CartItem> items,
    required bool selectTakeaway,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    for (final item in items) {
      container.read(cartProvider.notifier).addToCart(
            id: item.id,
            name: item.name,
            desc: item.desc,
            price: item.price,
            quantity: item.quantity,
            pricedForChannel: item.pricedForChannel,
          );
    }
    if (selectTakeaway) {
      container.read(shoppingChannelProvider.notifier).selectTakeaway(
            restaurantId: 'restaurant-1',
            branchId: 'branch-1',
            branchDisplayName: 'Abaküs Ortaköy',
          );
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CartScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'takeaway seçiliyken delivery fiyatlı bir ürün varsa uyarı gösterilir '
    've Siparişi Tamamla devre dışı kalır',
    (tester) async {
      await pumpCart(
        tester,
        items: [
          const CartItem(
            id: 'p1',
            name: 'Bowl',
            desc: '',
            price: 100.0,
            quantity: 1,
            pricedForChannel: OrderChannel.delivery,
          ),
        ],
        selectTakeaway: true,
      );

      expect(
        find.textContaining('farklı bir sipariş modu için fiyatlandırılmış'),
        findsOneWidget,
      );
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Siparişi Tamamla'),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets(
    'sepetteki her ürün takeaway için fiyatlandırılmışsa uyarı gösterilmez '
    've Gel Al checkout ekranına geçilir',
    (tester) async {
      await pumpCart(
        tester,
        items: [
          const CartItem(
            id: 'p1',
            name: 'Bowl',
            desc: '',
            price: 120.0,
            quantity: 1,
            pricedForChannel: OrderChannel.takeaway,
          ),
        ],
        selectTakeaway: true,
      );

      expect(
        find.textContaining('farklı bir sipariş modu için fiyatlandırılmış'),
        findsNothing,
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Siparişi Tamamla'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TakeawayCheckoutScreen), findsOneWidget);
    },
  );

  testWidgets('Sepeti Temizle uyarıyı çözer ve sepeti boşaltır', (
    tester,
  ) async {
    final container = await pumpCart(
      tester,
      items: [
        const CartItem(
          id: 'p1',
          name: 'Bowl',
          desc: '',
          price: 100.0,
          quantity: 1,
          pricedForChannel: OrderChannel.delivery,
        ),
      ],
      selectTakeaway: true,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sepeti Temizle'));
    await tester.pumpAndSettle();

    expect(container.read(cartProvider), isEmpty);
  });

  testWidgets(
    'normal delivery alışverişinde (takeaway seçili değil) uyarı hiç '
    'gösterilmez — null pricedForChannel delivery ile uyumlu kabul edilir',
    (tester) async {
      await pumpCart(
        tester,
        items: [
          const CartItem(
              id: 'p1', name: 'Bowl', desc: '', price: 100.0, quantity: 1),
        ],
        selectTakeaway: false,
      );

      expect(
        find.textContaining('farklı bir sipariş modu için fiyatlandırılmış'),
        findsNothing,
      );
    },
  );
}
